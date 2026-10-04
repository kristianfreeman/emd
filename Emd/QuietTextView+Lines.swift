import AppKit

extension QuietTextView {
    func styleLine(_ line: NSRange, ns: NSString, inCode: Bool, style: inout LineStyle) -> Bool {
        let editing = caretIsIn(line, ns: ns)
        applyBase(line, editing: editing, style: &style)
        let context = LineContext(line: line, ns: ns, inCode: inCode, editing: editing)
        return styledKind(context, style: &style)
    }

    func applyBase(_ line: NSRange, editing: Bool, style: inout LineStyle) {
        guard style.replaceBase else { return }
        style.storage.setAttributes(lineAttributes(style.base, editing: editing, style: style), range: line)
    }

    func lineAttributes(_ base: NSFont, editing: Bool, style: LineStyle) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: base,
            .foregroundColor: syntaxInk,
            .paragraphStyle: style.paragraph,
        ]
        guard focusMode, !editing else { return attributes }
        attributes.merge(focusAttributes()) { _, focus in focus }
        return attributes
    }

    /// What a line away from the caret wears in focus mode.
    func focusAttributes() -> [NSAttributedString.Key: Any] {
        let paper = backgroundColor
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: focusDepth.ink(muted: mutedColor, paper: paper)
        ]
        let radius = focusDepth.blurRadius(fontSize: baseFont?.pointSize ?? 15)
        if radius > 0 { attributes[.focusBlur] = radius }
        return attributes
    }

    func styledKind(_ context: LineContext, style: inout LineStyle) -> Bool {
        let text = context.ns.substring(with: context.line)
        if isFence(text) { return fenceResult(context, style: &style) }
        if context.inCode { return codeResult(context, style: &style) }
        if styleImageLine(context, text: text, style: &style) { return false }
        if styleFootnoteLine(context, text: text, style: &style) { return false }
        styleListLine(context.line, text: text, style: &style)
        styleProse(context.line, text: text, editing: context.editing, style: &style)
        return false
    }

    func isFence(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```")
    }

    func fenceResult(_ context: LineContext, style: inout LineStyle) -> Bool {
        let content = strippedNewline(context.line, ns: context.ns)
        noteMarkers(content, editing: context.editing, style: &style)
        return !context.inCode
    }

    func codeResult(_ context: LineContext, style: inout LineStyle) -> Bool {
        let content = strippedNewline(context.line, ns: context.ns)
        let mono = MarkdownFonts.mono(style.base.pointSize * 0.92)
        style.storage.addAttribute(.font, value: mono, range: content)
        return true
    }

    func styleProse(_ line: NSRange, text: String, editing: Bool, style: inout LineStyle) {
        let font = headingFont(line, text: text, editing: editing, style: &style)
        for run in MarkdownRuns.inline(in: text) {
            paint(run, on: line, font: font, style: &style)
        }
    }

    func headingFont(_ line: NSRange, text: String, editing: Bool, style: inout LineStyle) -> NSFont {
        guard let match = headingMatch(text) else { return style.base }
        let paint = HeadingPaint(match: match, line: line, text: text, editing: editing)
        return scaledHeading(paint, style: &style)
    }

    func headingMatch(_ text: String) -> NSTextCheckingResult? {
        guard let heading = Self.headingExpression else { return nil }
        let lineNS = text as NSString
        return heading.firstMatch(in: text, range: NSRange(location: 0, length: lineNS.length))
    }

    func scaledHeading(_ paint: HeadingPaint, style: inout LineStyle) -> NSFont {
        let lineNS = paint.text as NSString
        let level = lineNS.substring(with: paint.match.range(at: 1)).count
        let index = max(0, min(level, 6) - 1)
        let font = MarkdownFonts.sized(style.base, style.base.pointSize * Self.headingScales[index])
        let content = strippedNewline(paint.line, ns: string as NSString)
        style.storage.addAttribute(.font, value: font, range: content)
        noteMarkers(offset(paint.match.range, by: paint.line.location), editing: paint.editing, style: &style)
        return font
    }

    func paint(_ run: MarkdownRun, on line: NSRange, font: NSFont, style: inout LineStyle) {
        let inner = offset(run.inner, by: line.location)
        paintKind(run.kind, font: font, range: inner, storage: style.storage)
        hideMarkers(run, on: line, inner: inner, style: &style)
    }

    func hideMarkers(_ run: MarkdownRun, on line: NSRange, inner: NSRange, style: inout LineStyle) {
        // A link keeps its Markdown hidden; ⌘K edits the address. Other markers show while the caret touches them.
        let show = run.kind != .link && markerShown(inner, markers: run.markers, line: line)
        for marker in run.markers {
            noteMarkers(offset(marker, by: line.location), editing: show, style: &style)
        }
    }

    func markerShown(_ inner: NSRange, markers: [NSRange], line: NSRange) -> Bool {
        if caretTouches(inner) { return true }
        return markers.contains { caretTouches(self.offset($0, by: line.location)) }
    }

    func paintKind(_ kind: MarkdownRun.Kind, font: NSFont, range: NSRange, storage: NSTextStorage) {
        switch kind {
        case .bold:
            storage.addAttribute(.font, value: MarkdownFonts.bold(font), range: range)
        case .italic:
            storage.addAttribute(.font, value: MarkdownFonts.italic(font), range: range)
        case .code:
            storage.addAttribute(.font, value: MarkdownFonts.mono(font.pointSize * 0.92), range: range)
        case .link:
            storage.addAttribute(.foregroundColor, value: accent, range: range)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .footnote:
            storage.addAttributes(Self.raised(font, color: accent), range: range)
        }
    }

    /// A footnote label: small, raised, and in the accent, the way the site draws it.
    static func raised(_ font: NSFont, color: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: MarkdownFonts.sized(font, font.pointSize * 0.72),
            .baselineOffset: font.pointSize * 0.3,
            .foregroundColor: color,
        ]
    }

    static let noteLabel = try? NSRegularExpression(pattern: #"^\[\^[\p{L}\p{N}_-]+\]:"#)

    /// `[^1]: The note.` reads as a note: a little smaller, its label raised like the reference.
    func styleFootnoteLine(_ context: LineContext, text: String, style: inout LineStyle) -> Bool {
        // Every restyled line comes through here, so anything but a note line leaves on a prefix check.
        guard text.hasPrefix("[^"),
            let match = Self.noteLabel?.firstMatch(
                in: text, range: NSRange(location: 0, length: (text as NSString).length))
        else { return false }
        let small = MarkdownFonts.sized(style.base, style.base.pointSize * 0.9)
        style.storage.addAttribute(.font, value: small, range: strippedNewline(context.line, ns: context.ns))
        let label = NSRange(location: context.line.location + 2, length: match.range.length - 4)
        style.storage.addAttributes(Self.raised(small, color: accent), range: label)
        noteMarkers(NSRange(location: context.line.location, length: 2), editing: true, style: &style)
        noteMarkers(NSRange(location: NSMaxRange(label), length: 2), editing: true, style: &style)
        for run in MarkdownRuns.inline(in: text) {
            paint(run, on: context.line, font: small, style: &style)
        }
        return true
    }

    func caretTouches(_ range: NSRange) -> Bool {
        let caret = selectedRange()
        if caret.length == 0 {
            return caret.location >= range.location && caret.location <= NSMaxRange(range)
        }
        return NSIntersectionRange(caret, range).length > 0
    }

    func caretIsIn(_ line: NSRange, ns: NSString) -> Bool {
        let caret = selectedRange()
        if caret.length > 0 {
            return NSIntersectionRange(line, caret).length > 0
        }
        return caretFits(line, ns: ns, location: caret.location)
    }

    func caretFits(_ line: NSRange, ns: NSString, location: Int) -> Bool {
        let end = NSMaxRange(line)
        if endsWithBreak(line, ns: ns) {
            return location >= line.location && location < end
        }
        return location >= line.location && location <= end
    }

    func endsWithBreak(_ line: NSRange, ns: NSString) -> Bool {
        guard line.length > 0 else { return false }
        let last = ns.character(at: NSMaxRange(line) - 1)
        return last == 0x0A || last == 0x0D
    }

    func strippedNewline(_ line: NSRange, ns: NSString) -> NSRange {
        guard endsWithBreak(line, ns: ns) else { return line }
        return NSRange(location: line.location, length: line.length - 1)
    }

    func offset(_ range: NSRange, by delta: Int) -> NSRange {
        NSRange(location: range.location + delta, length: range.length)
    }

    func noteMarkers(_ range: NSRange, editing: Bool, style: inout LineStyle) {
        guard range.length > 0, range.location != NSNotFound else { return }
        if editing {
            style.storage.addAttribute(.foregroundColor, value: mutedColor, range: range)
        } else {
            style.hidden.insert(integersIn: range.location..<NSMaxRange(range))
        }
    }
}

struct LineContext {
    var line: NSRange
    var ns: NSString
    var inCode: Bool
    var editing: Bool
}

struct HeadingPaint {
    var match: NSTextCheckingResult
    var line: NSRange
    var text: String
    var editing: Bool
}
