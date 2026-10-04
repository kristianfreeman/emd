import AppKit

struct TextInk {
    var color: NSColor
    var muted: NSColor
    var paper: NSColor
}

struct TextLook {
    var font: NSFont
    var ink: TextInk
    var lineHeight: CGFloat
    var paragraphSpacing: CGFloat
}

final class QuietTextView: NSTextView, NSLayoutManagerDelegate {
    var placeholder = ""
    var mutedColor: NSColor = .secondaryLabelColor
    var focusMode = false
    var focusDepth = FocusDepth.muted
    var typewriter = false
    var accent: NSColor = .controlAccentColor
    var syntaxInk: NSColor = .labelColor
    /// The body font from `configure`. `font` reports whatever the caret sits in, so a heading would scale itself.
    var configuredFont: NSFont?
    var baseFont: NSFont? { configuredFont ?? font }
    var hiddenCharacters = IndexSet()
    var bulletCharacters = IndexSet()
    var styling = false
    var generatingGlyphs = false
    var appliedStyle = ""
    static let headingExpression = try? NSRegularExpression(pattern: #"^(#{1,6})[ \t]+"#)
    static let headingScales = [1.34, 1.22, 1.12, 1.06, 1.03, 1.0]
    var lastCaretLine: NSRange?
    var onEscape: (() -> Void)?
    /// Images dropped or pasted, and the character index where they go.
    var onImages: (([ImageSource], Int) -> Void)?
    /// Relative image URLs in the text, like `/_emdash/api/media/file/…`, resolve against this.
    var siteURL: URL?
    /// The image line whose Markdown is open for editing, by the location of its first character.
    var revealedImage: Int?
    /// How wide a picture may be. The column sets it wider than the text, and a change restyles.
    var imageWidthLimit: CGFloat = 0 {
        didSet {
            if abs(imageWidthLimit - oldValue) > 0.5 { noteColumnWidthChanged() }
        }
    }
    /// How wide a full-width picture may be: the window, less its margins.
    var imageFullWidth: CGFloat = 0

    /// TextKit 1. `NSTextView()` on current macOS is TextKit 2 and leaves `layoutManager` nil.
    static func editor() -> QuietTextView {
        GlyphHook.install(on: QuietTextView.self)
        let storage = NSTextStorage()
        let layout = FocusLayoutManager()
        // Lay out only what an edit touches and what is on screen. Contiguous layout re-laid every line below a
        // line that wrapped: 130ms for one key at the top of 120,000 characters.
        layout.allowsNonContiguousLayout = true
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 5
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        layout.addTextContainer(container)
        let view = QuietTextView(frame: .zero, textContainer: container)
        view.layoutManager?.delegate = view
        storage.delegate = view
        view.watchInlineImages()
        return view
    }

    override func didChangeText() {
        super.didChangeText()
        superview?.needsLayout = true
    }

    func configure(_ look: TextLook) {
        let stamp = styleStamp(look)
        guard stamp != appliedStyle else { return }
        appliedStyle = stamp
        let style = paragraphStyle(look)
        apply(look, style: style)
        applyEditingDefaults()
        typingAttributes = typedAttributes(look.font, color: look.ink.color, style: style)
        selectedTextAttributes = selectionAttributes(look.ink.color)
    }

    func styleStamp(_ look: TextLook) -> String {
        let font = look.font
        let ink = look.ink
        let metrics = "\(font.fontName)|\(font.pointSize)|\(look.lineHeight)|\(look.paragraphSpacing)"
        return "\(metrics)|\(ink.color)|\(ink.paper)"
    }

    func paragraphStyle(_ look: TextLook) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = look.lineHeight
        style.paragraphSpacing = look.paragraphSpacing
        return style
    }

    func apply(_ look: TextLook, style: NSMutableParagraphStyle) {
        defaultParagraphStyle = style
        font = look.font
        configuredFont = look.font
        textColor = look.ink.color
        syntaxInk = look.ink.color
        mutedColor = look.ink.muted
        backgroundColor = look.ink.paper
        insertionPointColor = look.ink.color
    }

    func typedAttributes(_ font: NSFont, color: NSColor, style: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
    }

    override func cancelOperation(_ sender: Any?) {
        guard let onEscape else { return super.cancelOperation(sender) }
        onEscape()
    }

    override func paste(_ sender: Any?) {
        guard !pasteImagesIfAny(), !pasteLinkOverSelection() else { return }
        leaveSelectedPicture()
        pasteAsPlainText(sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard textStorage?.length == 0, !placeholder.isEmpty, let font = baseFont else { return }
        let padding = textContainer?.lineFragmentPadding ?? 0
        let point = NSPoint(x: textContainerInset.width + padding, y: textContainerInset.height)
        NSAttributedString(
            string: placeholder,
            attributes: [
                .font: font,
                .foregroundColor: mutedColor,
            ]
        ).draw(at: point)
    }

    func deliverGlyphs(
        _ props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        source: GlyphSource,
        manager: NSLayoutManager
    ) -> UInt {
        guard let patch = hiddenPatch(props, source: source) else { return 0 }
        applyGlyphs(patch, source: source, manager: manager)
        return UInt(source.range.length)
    }

    private func hiddenPatch(
        _ props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        source: GlyphSource
    ) -> GlyphPatch? {
        let count = source.range.length
        guard count > 0, !generatingGlyphs, touchesPatchedCharacters(source) else { return nil }
        var properties = Array(UnsafeBufferPointer(start: props, count: count))
        var glyphs = Array(UnsafeBufferPointer(start: source.glyphs, count: count))
        let hid = markNulls(&properties, glyphs: &glyphs, indexes: source.indexes, count: count)
        guard swapBullets(&glyphs, source: source) || hid else { return nil }
        return GlyphPatch(properties: properties, glyphs: glyphs)
    }

    /// Most glyph runs hold no hidden marker and no bullet. Checking the run's character span once lets those
    /// go by untouched, instead of copying every glyph to look at each one: on a long post, TextKit hands over
    /// runs like that on most keystrokes.
    private func touchesPatchedCharacters(_ source: GlyphSource) -> Bool {
        let first = Int(source.indexes[0])
        let last = Int(source.indexes[source.range.length - 1])
        let span = min(first, last)..<(max(first, last) + 1)
        return hiddenCharacters.intersects(integersIn: span) || bulletCharacters.intersects(integersIn: span)
    }

    func markNulls(
        _ properties: inout [NSLayoutManager.GlyphProperty],
        glyphs: inout [CGGlyph],
        indexes: UnsafePointer<UInt>,
        count: Int
    ) -> Bool {
        var hide = false
        for index in 0..<count where hiddenCharacters.contains(Int(indexes[index])) {
            properties[index].insert(.null)
            glyphs[index] = 0
            hide = true
        }
        return hide
    }

    private func applyGlyphs(_ patch: GlyphPatch, source: GlyphSource, manager: NSLayoutManager) {
        generatingGlyphs = true
        writePatch(patch, source: source, manager: manager)
        generatingGlyphs = false
    }

    private func writePatch(_ patch: GlyphPatch, source: GlyphSource, manager: NSLayoutManager) {
        let count = source.range.length
        guard count == patch.glyphs.count, count == patch.properties.count else { return }
        let glyphs = UnsafeMutablePointer<CGGlyph>.allocate(capacity: count)
        let props = UnsafeMutablePointer<NSLayoutManager.GlyphProperty>.allocate(capacity: count)
        copyGlyphs(patch.glyphs, into: glyphs)
        copyProperties(patch.properties, into: props)
        defer {
            glyphs.deinitialize(count: count)
            props.deinitialize(count: count)
            glyphs.deallocate()
            props.deallocate()
        }
        let characters = UnsafeRawPointer(source.indexes).assumingMemoryBound(to: Int.self)
        manager.setGlyphs(
            glyphs,
            properties: props,
            characterIndexes: characters,
            font: source.font,
            forGlyphRange: source.range
        )
    }

    func copyGlyphs(_ values: [CGGlyph], into pointer: UnsafeMutablePointer<CGGlyph>) {
        for index in values.indices {
            pointer.advanced(by: index).initialize(to: values[index])
        }
    }

    func copyProperties(
        _ values: [NSLayoutManager.GlyphProperty],
        into pointer: UnsafeMutablePointer<NSLayoutManager.GlyphProperty>
    ) {
        for index in values.indices {
            pointer.advanced(by: index).initialize(to: values[index])
        }
    }
}

extension QuietTextView {
    func applyEditingDefaults() {
        isRichText = true
        usesFontPanel = false
        importsGraphics = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isEditable = true
        isSelectable = true
        allowsUndo = true
        drawsBackground = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = true
        isGrammarCheckingEnabled = false
        smartInsertDeleteEnabled = false
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        focusRingType = .none
        layoutManager?.delegate = self
        textContainerInset = NSSize(width: 8, height: 2)
        textContainer?.lineFragmentPadding = 5
        textContainer?.widthTracksTextView = false
        textContainer?.heightTracksTextView = false
        isHorizontallyResizable = false
        isVerticallyResizable = false
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        minSize = NSSize(width: 0, height: 0)
    }

    func selectionAttributes(_ color: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .backgroundColor: accent.withAlphaComponent(0.28),
            .foregroundColor: color,
        ]
    }
}

private struct GlyphPatch {
    var properties: [NSLayoutManager.GlyphProperty]
    var glyphs: [CGGlyph]
}

struct GlyphSource {
    var glyphs: UnsafePointer<CGGlyph>
    var indexes: UnsafePointer<UInt>
    var font: NSFont
    var range: NSRange
}

private enum GlyphHook {
    static func install(on type: AnyClass) {
        let selector = glyphSelector
        guard class_getInstanceMethod(type, selector) == nil else { return }
        let description = protocol_getMethodDescription(NSLayoutManagerDelegate.self, selector, false, true)
        guard let types = description.types else { return }
        class_addMethod(type, selector, unsafeBitCast(implementation, to: IMP.self), types)
    }

    private static let glyphSelector = NSSelectorFromString(
        "layoutManager:shouldGenerateGlyphs:properties:characterIndexes:font:forGlyphRange:"
    )

    private static let implementation:
        @convention(c) (
            AnyObject,
            Selector,
            NSLayoutManager,
            UnsafePointer<CGGlyph>,
            UnsafePointer<NSLayoutManager.GlyphProperty>,
            UnsafePointer<UInt>,
            NSFont,
            NSRange
        ) -> UInt = { object, _, manager, glyphs, props, indexes, font, range in
            guard let view = object as? QuietTextView else { return 0 }
            let source = GlyphSource(glyphs: glyphs, indexes: indexes, font: font, range: range)
            return view.deliverGlyphs(props, source: source, manager: manager)
        }
}
