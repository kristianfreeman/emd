import AppKit

extension QuietTextView {
    func restyle() {
        restyle(around: nil)
    }

    func noteCaretLine() {
        let ns = string as NSString
        guard ns.length > 0 else {
            lastCaretLine = nil
            return
        }
        lastCaretLine = ns.lineRange(for: selectedRange())
    }

    /// Restyle the caret line, and the line the caret just left, without walking the rest of the post.
    func restyleCaretLine() {
        let ns = string as NSString
        guard ns.length > 0 else { return }
        let line = ns.lineRange(for: selectedRange())
        let previous = lastCaretLine
        lastCaretLine = line
        restyle(around: line)
        restylePrevious(previous, current: line)
    }

    func restylePrevious(_ previous: NSRange?, current: NSRange) {
        guard let previous, !NSEqualRanges(previous, current) else { return }
        restyle(around: previous)
    }

    /// `nil` restyles the whole document. A range restyles only the lines that cover it.
    func restyle(around edited: NSRange?) {
        guard canRestyle() else { return }
        let span = Pace.begin("restyle")
        styling = true
        defer { finishRestyle(span, edited: edited) }
        undoManager?.disableUndoRegistration()
        defer { undoManager?.enableUndoRegistration() }
        let paragraph = copiedParagraph()
        paint(edited, paragraph: paragraph)
        guard let base = baseFont else { return }
        typingAttributes = typedAttributes(base, color: syntaxInk, style: paragraph)
    }

    func canRestyle() -> Bool {
        !styling && textStorage != nil && baseFont != nil
    }

    func finishRestyle(_ span: Pace.Span, edited: NSRange?) {
        styling = false
        Pace.end(span, detail: restyleDetail(edited))
    }

    func restyleDetail(_ edited: NSRange?) -> String {
        guard edited == nil else { return "line" }
        return "full \(string.utf16.count)"
    }

    func copiedParagraph() -> NSMutableParagraphStyle {
        let current = defaultParagraphStyle ?? NSParagraphStyle.default
        return current.mutableCopy() as! NSMutableParagraphStyle
    }

    func paint(_ edited: NSRange?, paragraph: NSMutableParagraphStyle) {
        guard let storage = textStorage, let base = baseFont else { return }
        let input = PaintInput(
            edited: edited,
            ns: string as NSString,
            storage: storage,
            base: base,
            paragraph: paragraph
        )
        storage.beginEditing()
        route(input)
        storage.endEditing()
        invalidateEdited(edited, ns: input.ns)
    }

    func route(_ input: PaintInput) {
        var style = LineStyle(
            base: input.base,
            paragraph: input.paragraph,
            storage: input.storage,
            hidden: hiddenCharacters,
            replaceBase: false,
            bullets: bulletCharacters
        )
        if input.ns.length == 0 {
            hiddenCharacters = IndexSet()
            bulletCharacters = IndexSet()
            return
        }
        if let edited = input.edited {
            style.replaceBase = true
            paintLines(edited, ns: input.ns, style: &style)
            hiddenCharacters = style.hidden
            bulletCharacters = style.bullets
            return
        }
        style.hidden = IndexSet()
        style.bullets = IndexSet()
        paintDocument(ns: input.ns, style: &style)
        hiddenCharacters = style.hidden
        bulletCharacters = style.bullets
    }

    func paintLines(_ edited: NSRange, ns: NSString, style: inout LineStyle) {
        let covering = coveringRange(edited, ns: ns)
        var cursor = covering.location
        let end = NSMaxRange(covering)
        var inCode = fenceOpen(before: covering.location, ns: ns)
        while cursor < end && cursor < ns.length {
            cursor = paintOne(&inCode, cursor: cursor, ns: ns, style: &style)
        }
        lastCaretLine = ns.lineRange(for: selectedRange())
    }

    func paintDocument(ns: NSString, style: inout LineStyle) {
        let full = NSRange(location: 0, length: ns.length)
        style.storage.setAttributes(documentAttributes(style), range: full)
        paintFocus(ns, storage: style.storage)
        var location = 0
        var inCode = false
        while location < ns.length {
            location = paintOne(&inCode, cursor: location, ns: ns, style: &style)
        }
        lastCaretLine = ns.lineRange(for: selectedRange())
    }

    func documentAttributes(_ style: LineStyle) -> [NSAttributedString.Key: Any] {
        [
            .font: style.base,
            .foregroundColor: syntaxInk,
            .paragraphStyle: style.paragraph,
        ]
    }

    func paintFocus(_ ns: NSString, storage: NSTextStorage) {
        guard focusMode else { return }
        let full = NSRange(location: 0, length: ns.length)
        let active = ns.paragraphRange(for: selectedRange())
        storage.addAttributes(focusAttributes(), range: full)
        storage.removeAttribute(.focusBlur, range: active)
        storage.addAttribute(.foregroundColor, value: syntaxInk, range: active)
    }

    func paintOne(_ inCode: inout Bool, cursor: Int, ns: NSString, style: inout LineStyle) -> Int {
        let line = ns.lineRange(for: NSRange(location: cursor, length: 0))
        style.hidden.remove(integersIn: line.location..<NSMaxRange(line))
        style.bullets.remove(integersIn: line.location..<NSMaxRange(line))
        inCode = styleLine(line, ns: ns, inCode: inCode, style: &style)
        return NSMaxRange(line)
    }

    func invalidateEdited(_ edited: NSRange?, ns: NSString) {
        guard let edited, let layout = layoutManager, ns.length > 0 else { return }
        let covering = coveringRange(edited, ns: ns)
        layout.invalidateGlyphs(forCharacterRange: covering, changeInLength: 0, actualCharacterRange: nil)
        layout.invalidateLayout(forCharacterRange: covering, actualCharacterRange: nil)
    }

    func coveringRange(_ edited: NSRange, ns: NSString) -> NSRange {
        let location = min(max(0, edited.location), ns.length)
        let length = min(edited.length, ns.length - location)
        return ns.lineRange(for: NSRange(location: location, length: length))
    }

    /// Whether a code fence is open where `location`'s line starts. It jumps between backtick runs
    /// instead of walking every line, since it runs on each keystroke.
    func fenceOpen(before location: Int, ns: NSString) -> Bool {
        var inCode = false
        var cursor = 0
        while let run = nextTicks(from: cursor, before: location, ns: ns) {
            inCode = inCode != leadsLine(run.hit, line: run.line, ns: ns)
            cursor = NSMaxRange(run.line)
        }
        return inCode
    }

    /// The next ``` whose line starts before `location`, and that line.
    private func nextTicks(from cursor: Int, before location: Int, ns: NSString) -> (hit: Int, line: NSRange)? {
        guard cursor < ns.length else { return nil }
        let hit = ns.range(of: "```", options: .literal, range: NSRange(location: cursor, length: ns.length - cursor))
        guard hit.location != NSNotFound else { return nil }
        let line = ns.lineRange(for: NSRange(location: hit.location, length: 0))
        return line.location < location ? (hit.location, line) : nil
    }

    private func leadsLine(_ position: Int, line: NSRange, ns: NSString) -> Bool {
        let lead = ns.substring(with: NSRange(location: line.location, length: position - line.location))
        return lead.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

struct PaintInput {
    var edited: NSRange?
    var ns: NSString
    var storage: NSTextStorage
    var base: NSFont
    var paragraph: NSMutableParagraphStyle
}

struct LineStyle {
    var base: NSFont
    var paragraph: NSParagraphStyle
    var storage: NSTextStorage
    var hidden: IndexSet
    var replaceBase: Bool
    /// List markers drawn as a bullet glyph.
    var bullets = IndexSet()
}

/// Hidden markers and bullets are character positions. An edit moves every one after it, so they shift with
/// the text before TextKit makes glyphs for it. Stale positions hid the wrong characters below an edit until
/// the next full restyle, and sent TextKit back over the whole post for glyphs on some keystrokes.
extension QuietTextView: NSTextStorageDelegate {
    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        hiddenCharacters = Self.shifted(hiddenCharacters, edited: editedRange, delta: delta)
        bulletCharacters = Self.shifted(bulletCharacters, edited: editedRange, delta: delta)
    }

    static func shifted(_ set: IndexSet, edited: NSRange, delta: Int) -> IndexSet {
        guard !set.isEmpty else { return set }
        var result = set
        let oldEnd = edited.location + edited.length - delta
        result.remove(integersIn: edited.location..<max(edited.location, oldEnd))
        result.shift(startingAt: oldEnd, by: delta)
        return result
    }
}
