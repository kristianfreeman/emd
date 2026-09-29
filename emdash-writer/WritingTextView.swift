import AppKit
import SwiftUI

struct WritingColumn: NSViewRepresentable {
    @Binding var title: String
    @Binding var bodyText: String
    var fontChoice: WriterFont
    var fontSize: CGFloat
    var palette: Palette
    var focusMode: Bool
    var typewriter: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = true
        scroll.borderType = .noBorder
        scroll.backgroundColor = palette.nsPaper

        let column = ColumnView()
        column.titleView.delegate = context.coordinator
        column.bodyView.delegate = context.coordinator
        context.coordinator.column = column
        context.coordinator.scroll = scroll
        column.frame = NSRect(x: 0, y: 0, width: 680, height: 400)
        scroll.documentView = column
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.apply(self, to: column)
        return scroll
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 680, height: 640))
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let column = scroll.documentView as? ColumnView else { return }
        scroll.backgroundColor = palette.nsPaper
        context.coordinator.apply(self, to: column)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: WritingColumn
        weak var column: ColumnView?
        weak var scroll: NSScrollView?
        private var applying = false
        private var paintedKey = ""
        private var pendingEdit: NSRange?
        private var skipNextCaretRestyle = false

        init(_ parent: WritingColumn) {
            self.parent = parent
        }

        func apply(_ parent: WritingColumn, to column: ColumnView) {
            self.parent = parent
            applying = true
            defer { applying = false }
            column.titleView.placeholder = "Title"
            column.titleView.configure(
                font: parent.fontChoice.nsFont(size: parent.fontSize * 1.22),
                color: parent.palette.nsInk,
                muted: parent.palette.nsMuted,
                paper: parent.palette.nsPaper,
                lineHeight: 1.12,
                paragraphSpacing: 0
            )
            column.bodyView.accent = parent.palette.nsAccent
            column.bodyView.focusMode = parent.focusMode
            column.bodyView.configure(
                font: parent.fontChoice.nsFont(size: parent.fontSize),
                color: parent.palette.nsInk,
                muted: parent.palette.nsMuted,
                paper: parent.palette.nsPaper,
                lineHeight: 1.32,
                paragraphSpacing: parent.fontSize * 0.28
            )
            column.bodyView.typewriter = parent.typewriter
            let titleChanged = column.titleView.string != parent.title
            if titleChanged {
                column.titleView.string = parent.title
            }
            let bodyChanged = column.bodyView.string != parent.bodyText
            if bodyChanged {
                column.bodyView.string = parent.bodyText
            }
            let styleKey = "\(parent.fontChoice.rawValue)|\(parent.fontSize)|\(parent.focusMode)|\(parent.palette.ink)|\(parent.palette.paper)"
            let styleChanged = paintedKey != styleKey
            paintedKey = styleKey
            if bodyChanged || styleChanged {
                column.bodyView.restyle()
            }
            if bodyChanged || titleChanged || styleChanged || column.bounds.width < 2 {
                column.needsLayout = true
            }
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard !applying, textView === column?.bodyView else { return true }
            let length = (replacementString as NSString?)?.length ?? 0
            pendingEdit = NSRange(location: affectedCharRange.location, length: length)
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard !applying, let view = notification.object as? NSTextView, let column else { return }
            if view === column.titleView {
                parent.title = view.string
            } else if view === column.bodyView {
                parent.bodyText = view.string
                let edited = pendingEdit
                pendingEdit = nil
                skipNextCaretRestyle = true
                column.bodyView.restyle(around: edited)
            }
            column.needsLayout = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? QuietTextView, view === column?.bodyView else { return }
            if skipNextCaretRestyle {
                skipNextCaretRestyle = false
                view.noteCaretLine()
            } else {
                view.restyleCaretLine()
            }
            guard view.typewriter, let scroll, let column else { return }
            guard let layout = view.layoutManager, let container = view.textContainer else { return }
            let glyphRange = layout.glyphRange(forCharacterRange: view.selectedRange(), actualCharacterRange: nil)
            let caret = layout.boundingRect(forGlyphRange: glyphRange, in: container)
            column.layoutSubtreeIfNeeded()
            let inColumn = view.convert(caret, to: column)
            let clipHeight = scroll.contentView.bounds.height
            var origin = scroll.contentView.bounds.origin
            let target = inColumn.midY - clipHeight * 0.42
            let limit = max(0, column.bounds.height - clipHeight)
            origin.y = min(max(0, target), limit)
            scroll.contentView.setBoundsOrigin(origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}

final class ColumnView: NSView {
    let titleView = QuietTextView.editor()
    let bodyView = QuietTextView.editor()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(titleView)
        addSubview(bodyView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var layingOut = false

    override func layout() {
        super.layout()
        guard !layingOut else { return }
        layingOut = true
        defer { layingOut = false }

        let available = enclosingScrollView?.contentSize.width ?? bounds.width
        let columnWidth = max(available, 1)
        let textWidth = min(680, max(240, columnWidth - 72))
        let x = max(36, (columnWidth - textWidth) / 2)
        let span = Pace.begin("layout")
        let titleHeight = measure(titleView, width: textWidth)
        titleView.frame = NSRect(x: x, y: 72, width: textWidth, height: titleHeight)
        let bodyY = titleView.frame.maxY + 28
        let bodyHeight = measure(bodyView, width: textWidth)
        Pace.end(span, detail: "\(bodyView.string.utf16.count)")
        bodyView.frame = NSRect(x: x, y: bodyY, width: textWidth, height: bodyHeight)
        let height = bodyView.frame.maxY + 120
        if abs(frame.width - columnWidth) > 0.5 || abs(frame.height - height) > 0.5 {
            frame = NSRect(x: 0, y: 0, width: columnWidth, height: height)
        }
    }

    private func measure(_ view: QuietTextView, width: CGFloat) -> CGFloat {
        let inset = view.textContainerInset.width * 2
        let textWidth = max(1, width - inset)
        // Assigning the container size invalidates every line. Skip it when the column width has not changed.
        if let container = view.textContainer, abs(container.containerSize.width - textWidth) > 0.5 {
            container.containerSize = NSSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude)
        }
        guard let layout = view.layoutManager, let container = view.textContainer else { return 36 }
        layout.ensureLayout(for: container)
        return max(36, ceil(layout.usedRect(for: container).height + view.textContainerInset.height * 2 + 8))
    }
}

final class QuietTextView: NSTextView, NSLayoutManagerDelegate {
    var placeholder = ""
    var mutedColor: NSColor = .secondaryLabelColor
    var focusMode = false
    var typewriter = false
    var accent: NSColor = .controlAccentColor
    private var syntaxInk: NSColor = .labelColor
    private var hiddenCharacters = IndexSet()
    private var styling = false
    private var generatingGlyphs = false

    /// TextKit 1. `NSTextView()` on current macOS is TextKit 2 and leaves `layoutManager` nil, so markdown styles never draw.
    static func editor() -> QuietTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        layout.addTextContainer(container)
        let view = QuietTextView(frame: .zero, textContainer: container)
        view.layoutManager?.delegate = view
        return view
    }

    override func didChangeText() {
        super.didChangeText()
        superview?.needsLayout = true
    }

    private var appliedStyle = ""

    func configure(font: NSFont, color: NSColor, muted: NSColor, paper: NSColor, lineHeight: CGFloat, paragraphSpacing: CGFloat) {
        let stamp = "\(font.fontName)|\(font.pointSize)|\(lineHeight)|\(paragraphSpacing)|\(color)|\(paper)"
        if stamp == appliedStyle { return }
        appliedStyle = stamp
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeight
        style.paragraphSpacing = paragraphSpacing
        defaultParagraphStyle = style
        self.font = font
        textColor = color
        syntaxInk = color
        mutedColor = muted
        backgroundColor = paper
        insertionPointColor = color
        isRichText = true
        usesFontPanel = false
        importsGraphics = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isEditable = true
        isSelectable = true
        allowsUndo = true
        drawsBackground = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = true
        isGrammarCheckingEnabled = false
        smartInsertDeleteEnabled = false
        focusRingType = .none
        layoutManager?.delegate = self
        textContainerInset = NSSize(width: 2, height: 2)
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = false
        textContainer?.heightTracksTextView = false
        isHorizontallyResizable = false
        isVerticallyResizable = false
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        minSize = NSSize(width: 0, height: 0)
        typingAttributes = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        selectedTextAttributes = [
            .backgroundColor: accent.withAlphaComponent(0.28),
            .foregroundColor: color,
        ]
    }

    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    private static let headingExpression = try? NSRegularExpression(pattern: #"^(#{1,6})[ \t]+"#)
    private var lastCaretLine: NSRange?

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
        if let previous, !NSEqualRanges(previous, line) {
            restyle(around: previous)
        }
    }

    /// `nil` restyles the whole document. A range restyles only the lines that cover it.
    func restyle(around edited: NSRange?) {
        guard !styling, let storage = textStorage, let base = font else { return }
        let span = Pace.begin("restyle")
        styling = true
        defer {
            styling = false
            Pace.end(span, detail: edited == nil ? "full \(string.utf16.count)" : "line")
        }
        undoManager?.disableUndoRegistration()
        defer { undoManager?.enableUndoRegistration() }

        let ns = string as NSString
        let paragraph = (defaultParagraphStyle ?? NSParagraphStyle.default).mutableCopy() as! NSMutableParagraphStyle
        storage.beginEditing()
        if ns.length == 0 {
            hiddenCharacters = IndexSet()
        } else if let edited {
            let location = min(max(0, edited.location), ns.length)
            let length = min(edited.length, ns.length - location)
            let covering = ns.lineRange(for: NSRange(location: location, length: length))
            var cursor = covering.location
            let end = NSMaxRange(covering)
            var inCode = fenceOpen(before: covering.location, ns: ns)
            while cursor < end && cursor < ns.length {
                let line = ns.lineRange(for: NSRange(location: cursor, length: 0))
                hiddenCharacters.remove(integersIn: line.location..<NSMaxRange(line))
                inCode = styleLine(line, ns: ns, base: base, inCode: inCode, paragraph: paragraph, storage: storage, replaceBase: true)
                cursor = NSMaxRange(line)
            }
            lastCaretLine = ns.lineRange(for: selectedRange())
        } else {
            let full = NSRange(location: 0, length: ns.length)
            var hidden = IndexSet()
            storage.setAttributes([
                .font: base,
                .foregroundColor: syntaxInk,
                .paragraphStyle: paragraph,
            ], range: full)
            if focusMode {
                let active = ns.paragraphRange(for: selectedRange())
                storage.addAttribute(.foregroundColor, value: mutedColor, range: full)
                storage.addAttribute(.foregroundColor, value: syntaxInk, range: active)
            }
            var location = 0
            var inCode = false
            while location < ns.length {
                let line = ns.lineRange(for: NSRange(location: location, length: 0))
                inCode = styleLine(line, ns: ns, base: base, inCode: inCode, paragraph: paragraph, storage: storage, replaceBase: false, hidden: &hidden)
                location = NSMaxRange(line)
            }
            hiddenCharacters = hidden
            lastCaretLine = ns.lineRange(for: selectedRange())
        }
        storage.endEditing()
        if let edited, let layout = layoutManager, ns.length > 0 {
            let location = min(max(0, edited.location), ns.length)
            let length = min(edited.length, ns.length - location)
            let covering = ns.lineRange(for: NSRange(location: location, length: length))
            layout.invalidateGlyphs(forCharacterRange: covering, changeInLength: 0, actualCharacterRange: nil)
            layout.invalidateLayout(forCharacterRange: covering, actualCharacterRange: nil)
        }
        typingAttributes = [
            .font: base,
            .foregroundColor: syntaxInk,
            .paragraphStyle: paragraph,
        ]
    }

    @discardableResult
    private func styleLine(
        _ line: NSRange,
        ns: NSString,
        base: NSFont,
        inCode: Bool,
        paragraph: NSParagraphStyle,
        storage: NSTextStorage,
        replaceBase: Bool,
        hidden: inout IndexSet
    ) -> Bool {
        let editing = caretIsIn(line, ns: ns)
        let text = ns.substring(with: line)
        let content = strippedNewline(line, ns: ns)
        if replaceBase {
            storage.setAttributes([
                .font: base,
                .foregroundColor: focusMode && !editing ? mutedColor : syntaxInk,
                .paragraphStyle: paragraph,
            ], range: line)
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") {
            noteMarkers(content, editing: editing, hidden: &hidden, storage: storage)
            return !inCode
        }
        if inCode {
            storage.addAttribute(.font, value: MarkdownFonts.mono(base.pointSize * 0.92), range: content)
            return true
        }
        styleProse(line, text: text, base: base, editing: editing, hidden: &hidden, storage: storage)
        return false
    }

    private func styleLine(
        _ line: NSRange,
        ns: NSString,
        base: NSFont,
        inCode: Bool,
        paragraph: NSParagraphStyle,
        storage: NSTextStorage,
        replaceBase: Bool
    ) -> Bool {
        var hidden = hiddenCharacters
        let next = styleLine(line, ns: ns, base: base, inCode: inCode, paragraph: paragraph, storage: storage, replaceBase: replaceBase, hidden: &hidden)
        hiddenCharacters = hidden
        return next
    }

    private func fenceOpen(before location: Int, ns: NSString) -> Bool {
        var inCode = false
        var cursor = 0
        while cursor < location && cursor < ns.length {
            let line = ns.lineRange(for: NSRange(location: cursor, length: 0))
            let text = ns.substring(with: line)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") {
                inCode.toggle()
            }
            let next = NSMaxRange(line)
            if next <= cursor { break }
            cursor = next
        }
        return inCode
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        if generatingGlyphs || hiddenCharacters.isEmpty { return 0 }
        let count = glyphRange.length
        guard count > 0 else { return 0 }
        var updated = Array(UnsafeBufferPointer(start: props, count: count))
        var hide = false
        for index in 0..<count where hiddenCharacters.contains(charIndexes[index]) {
            updated[index].insert(.null)
            hide = true
        }
        guard hide else { return 0 }
        generatingGlyphs = true
        updated.withUnsafeBufferPointer { buffer in
            guard let properties = buffer.baseAddress else { return }
            layoutManager.setGlyphs(
                glyphs,
                properties: properties,
                characterIndexes: charIndexes,
                font: aFont,
                forGlyphRange: glyphRange
            )
        }
        generatingGlyphs = false
        return count
    }

    private func styleProse(
        _ line: NSRange,
        text: String,
        base: NSFont,
        editing: Bool,
        hidden: inout IndexSet,
        storage: NSTextStorage
    ) {
        var lineFont = base
        let lineNS = text as NSString
        if let heading = Self.headingExpression,
           let match = heading.firstMatch(in: text, range: NSRange(location: 0, length: lineNS.length)) {
            let level = lineNS.substring(with: match.range(at: 1)).count
            let scale = [1.34, 1.22, 1.12, 1.06, 1.03, 1.0][max(0, min(level, 6) - 1)]
            lineFont = MarkdownFonts.sized(base, base.pointSize * scale)
            storage.addAttribute(.font, value: lineFont, range: strippedNewline(line, ns: string as NSString))
            noteMarkers(offset(match.range, by: line.location), editing: editing, hidden: &hidden, storage: storage)
        }
        for run in MarkdownRuns.inline(in: text) {
            let inner = offset(run.inner, by: line.location)
            switch run.kind {
            case .bold:
                storage.addAttribute(.font, value: MarkdownFonts.bold(lineFont), range: inner)
            case .italic:
                storage.addAttribute(.font, value: MarkdownFonts.italic(lineFont), range: inner)
            case .code:
                storage.addAttribute(.font, value: MarkdownFonts.mono(lineFont.pointSize * 0.92), range: inner)
            case .link:
                storage.addAttribute(.foregroundColor, value: accent, range: inner)
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: inner)
            }
            let showMarkers = caretTouches(inner) || run.markers.contains { caretTouches(offset($0, by: line.location)) }
            for marker in run.markers {
                noteMarkers(offset(marker, by: line.location), editing: showMarkers, hidden: &hidden, storage: storage)
            }
        }
    }

    private func caretTouches(_ range: NSRange) -> Bool {
        let caret = selectedRange()
        if caret.length == 0 {
            return caret.location >= range.location && caret.location <= NSMaxRange(range)
        }
        return NSIntersectionRange(caret, range).length > 0
    }

    private func caretIsIn(_ line: NSRange, ns: NSString) -> Bool {
        let caret = selectedRange()
        if caret.length > 0 {
            return NSIntersectionRange(line, caret).length > 0
        }
        let end = NSMaxRange(line)
        if line.length > 0 {
            let last = ns.character(at: end - 1)
            if last == 0x0A || last == 0x0D {
                return caret.location >= line.location && caret.location < end
            }
        }
        return caret.location >= line.location && caret.location <= end
    }

    private func strippedNewline(_ line: NSRange, ns: NSString) -> NSRange {
        guard line.length > 0 else { return line }
        let last = ns.character(at: NSMaxRange(line) - 1)
        if last == 0x0A || last == 0x0D {
            return NSRange(location: line.location, length: line.length - 1)
        }
        return line
    }

    private func offset(_ range: NSRange, by delta: Int) -> NSRange {
        NSRange(location: range.location + delta, length: range.length)
    }

    private func noteMarkers(_ range: NSRange, editing: Bool, hidden: inout IndexSet, storage: NSTextStorage) {
        guard range.length > 0, range.location != NSNotFound else { return }
        if editing {
            storage.addAttribute(.foregroundColor, value: mutedColor, range: range)
        } else {
            hidden.insert(integersIn: range.location..<NSMaxRange(range))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty, let font else { return }
        let point = NSPoint(x: textContainerInset.width, y: textContainerInset.height)
        NSAttributedString(string: placeholder, attributes: [
            .font: font,
            .foregroundColor: mutedColor,
        ]).draw(at: point)
    }
}

enum MarkdownFonts {
    static func sized(_ font: NSFont, _ size: CGFloat) -> NSFont {
        NSFont(descriptor: font.fontDescriptor, size: size) ?? .systemFont(ofSize: size)
    }

    static func bold(_ font: NSFont) -> NSFont {
        faced(font, trait: .bold, weight: .bold) ?? .systemFont(ofSize: font.pointSize, weight: .bold)
    }

    static func italic(_ font: NSFont) -> NSFont {
        faced(font, trait: .italic, weight: nil) ?? NSFontManager.shared.convert(.systemFont(ofSize: font.pointSize), toHaveTrait: .italicFontMask)
    }

    static func mono(_ size: CGFloat) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static func faced(_ font: NSFont, trait: NSFontDescriptor.SymbolicTraits, weight: NSFont.Weight?) -> NSFont? {
        if let weight {
            let described = font.fontDescriptor.addingAttributes([
                .traits: [
                    NSFontDescriptor.TraitKey.symbolic: trait.rawValue,
                    NSFontDescriptor.TraitKey.weight: weight.rawValue,
                ],
            ])
            if let next = NSFont(descriptor: described, size: font.pointSize),
               NSFontManager.shared.weight(of: next) > NSFontManager.shared.weight(of: font) + 1 {
                return next
            }
        }
        let converted = NSFontManager.shared.convert(font, toHaveTrait: trait == .bold ? .boldFontMask : .italicFontMask)
        if converted.fontName != font.fontName || NSFontManager.shared.traits(of: converted) != NSFontManager.shared.traits(of: font) {
            return converted
        }
        let described = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait))
        if let next = NSFont(descriptor: described, size: font.pointSize),
           next.fontName != font.fontName {
            return next
        }
        return nil
    }
}

struct MarkdownRun: Equatable {
    enum Kind: Equatable {
        case bold
        case italic
        case code
        case link
    }

    var kind: Kind
    var inner: NSRange
    var markers: [NSRange]
}

enum MarkdownRuns {
    private static let pattern = #"\*\*(.+?)\*\*|__(.+?)__|(?<!\*)\*(?!\*)(.+?)\*(?!\*)|(?<!_)_(?!_)(.+?)_(?!_)|`([^`]+)`|\[([^\]]+)\]\(([^)\s]+)\)"#
    private static let expression = try? NSRegularExpression(pattern: pattern)

    static func inline(in line: String) -> [MarkdownRun] {
        guard let expression else { return [] }
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        return expression.matches(in: line, range: full).compactMap { match in
            if match.range(at: 1).location != NSNotFound { return run(.bold, match: match, inner: 1) }
            if match.range(at: 2).location != NSNotFound { return run(.bold, match: match, inner: 2) }
            if match.range(at: 3).location != NSNotFound { return run(.italic, match: match, inner: 3) }
            if match.range(at: 4).location != NSNotFound { return run(.italic, match: match, inner: 4) }
            if match.range(at: 5).location != NSNotFound { return run(.code, match: match, inner: 5) }
            if match.range(at: 6).location != NSNotFound { return run(.link, match: match, inner: 6) }
            return nil
        }
    }

    private static func run(_ kind: MarkdownRun.Kind, match: NSTextCheckingResult, inner: Int) -> MarkdownRun {
        let innerRange = match.range(at: inner)
        let lead = NSRange(location: match.range.location, length: max(0, innerRange.location - match.range.location))
        let tailStart = innerRange.location + innerRange.length
        let tail = NSRange(location: tailStart, length: max(0, match.range.location + match.range.length - tailStart))
        return MarkdownRun(kind: kind, inner: innerRange, markers: [lead, tail].filter { $0.length > 0 })
    }
}
