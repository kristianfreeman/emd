import AppKit

/// What an image line shows above itself: the picture at `size`, in the space before the line.
final class InlinePreview: NSObject {
    let url: URL
    let size: NSSize
    let dimmed: Bool
    var caption = ""
    var alignment = ""

    static let captionHeight: CGFloat = 26

    init(url: URL, size: NSSize, dimmed: Bool) {
        self.url = url
        self.size = size
        self.dimmed = dimmed
    }

    /// Height the line makes room for: the picture, its gaps, and a caption when there is one.
    var room: CGFloat {
        size.height + QuietTextView.imageGap * 2 + (caption.isEmpty ? 0 : Self.captionHeight)
    }

    /// Where the picture sits across the column: centered, or against the text's left or right edge.
    func frame(top: CGFloat, text: NSRect) -> NSRect {
        let x: CGFloat
        switch alignment {
        case "left": x = text.minX + 5
        case "right": x = text.maxX - 5 - size.width
        default: x = text.midX - size.width / 2
        }
        return NSRect(x: x.rounded(), y: top, width: size.width, height: size.height)
    }

    func drawCaption(under frame: NSRect, color: NSColor, font: NSFont) {
        guard !caption.isEmpty else { return }
        let style = NSMutableParagraphStyle()
        style.alignment = alignment == "left" ? .left : alignment == "right" ? .right : .center
        style.lineBreakMode = .byTruncatingTail
        let box = NSRect(x: frame.minX, y: frame.maxY + 6, width: frame.width, height: Self.captionHeight - 6)
        (caption as NSString).draw(
            in: box, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }

    func draw(in frame: NSRect, placeholder: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).addClip()
        guard let image = InlineImages.shared.image(url) else {
            placeholder.withAlphaComponent(0.12).setFill()
            frame.fill()
            return
        }
        image.draw(
            in: frame, from: .zero, operation: .sourceOver, fraction: dimmed ? 0.3 : 1,
            respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }
}

/// A picture on the page: what to draw, the top of it in the text view, and the Markdown it stands for.
struct PlacedPreview {
    var preview: InlinePreview
    var top: CGFloat
    var range: NSRange
}

extension NSAttributedString.Key {
    static let inlineImage = NSAttributedString.Key("emd.inlineImage")
}

/// An image line shows its picture, with its Markdown folded away. The picture acts as one object (see
/// `QuietTextView+ImageObject`); a double-click opens the source under it until the caret leaves the line.
/// The picture's room is added to the top of the line's first fragment as it lays out, which holds for the
/// first and last lines of a post too, where paragraph spacing does not. The column draws the picture,
/// centered and wider than the text, from `previews(in:)`.
extension QuietTextView {
    static let imageGap: CGFloat = 10

    /// Styles `context.line` as a picture when it is one whose size is known. The size comes from the
    /// `=WxH` suffix, or from the image once it has loaded; until then the line reads as text.
    func styleImageLine(_ context: LineContext, text: String, style: inout LineStyle) -> Bool {
        let content = strippedNewline(context.line, ns: context.ns)
        guard let picture = pictureLine(context.ns.substring(with: content)) else { return false }
        InlineImages.shared.request(picture.url)
        let declared = picture.image.width.flatMap { width in
            picture.image.height.map { NSSize(width: width, height: $0) }
        }
        let size = previewSize(
            declared ?? InlineImages.shared.pixelSize(picture.url), alignment: picture.image.alignment)
        guard size.height > 0 else { return false }
        let preview = InlinePreview(url: picture.url, size: size, dimmed: focusMode && !context.editing)
        preview.caption = picture.image.caption
        preview.alignment = picture.image.alignment
        let open = revealedImage == content.location
        style.storage.addAttribute(.inlineImage, value: preview, range: content)
        style.storage.addAttribute(
            .paragraphStyle, value: imageParagraph(size, editing: open, style), range: context.line)
        foldSource(content, editing: open, style: &style)
        return true
    }

    private func foldSource(_ content: NSRange, editing: Bool, style: inout LineStyle) {
        guard !editing else {
            style.storage.addAttribute(.foregroundColor, value: mutedColor, range: content)
            return
        }
        // Clear and a point tall rather than hidden: a line of hidden glyphs folds into the line before it,
        // and the picture needs a line of its own to sit on.
        style.storage.addAttributes(
            [.font: NSFont.systemFont(ofSize: 1), .foregroundColor: NSColor.clear], range: content)
        style.storage.removeAttribute(.focusBlur, range: content)
    }

    /// Folded, the source line is one point tall. The picture's room is added to the line in layout.
    private func imageParagraph(_ size: NSSize, editing: Bool, _ style: LineStyle) -> NSParagraphStyle {
        let paragraph = copiedParagraph(style.paragraph)
        guard !editing else { return paragraph }
        paragraph.lineHeightMultiple = 0
        paragraph.minimumLineHeight = 1
        paragraph.maximumLineHeight = 1
        return paragraph
    }

    private func copiedParagraph(_ paragraph: NSParagraphStyle) -> NSMutableParagraphStyle {
        (paragraph.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
    }

    private func pictureLine(_ text: String) -> (image: ImageLine, url: URL)? {
        guard let image = ImageLine(text), let url = resolved(image.url) else { return nil }
        return (image, url)
    }

    /// Site media URLs are relative to the site.
    private func resolved(_ text: String) -> URL? {
        if let url = URL(string: text), url.scheme != nil { return url }
        guard text.hasPrefix("/"), let siteURL else { return nil }
        return URL(string: text, relativeTo: siteURL)?.absoluteURL
    }

    /// Pixels are drawn at 2x, up to the width the column allows pictures, which is wider than the text.
    /// Pixels draw at 2x. The width allowed follows EmDash's alignment: half the text for left and right,
    /// the text for center, past the text for wide and the default, the window for full.
    private func previewSize(_ pixels: NSSize?, alignment: String) -> NSSize {
        guard let pixels, pixels.width > 0, pixels.height > 0 else { return .zero }
        let text = (textContainer?.size.width ?? 0) - (textContainer?.lineFragmentPadding ?? 0) * 2
        let limit = widthLimit(alignment, text: text)
        guard limit > 40 else { return .zero }
        let width = min(limit, pixels.width / 2).rounded()
        return NSSize(width: width, height: (width * pixels.height / pixels.width).rounded())
    }

    private func widthLimit(_ alignment: String, text: CGFloat) -> CGFloat {
        switch alignment {
        case "left", "right": text / 2
        case "center": text
        case "full": max(imageFullWidth, text)
        default: max(imageWidthLimit, text)
        }
    }

    // MARK: Drawing

    /// Pictures whose space meets `rect`, with the top of each in this view's coordinates.
    func previews(in rect: NSRect) -> [PlacedPreview] {
        guard let layout = layoutManager, let container = textContainer, let storage = textStorage else { return [] }
        let origin = textContainerOrigin
        let glyphs = layout.glyphRange(forBoundingRect: rect.offsetBy(dx: -origin.x, dy: -origin.y), in: container)
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var found: [PlacedPreview] = []
        storage.enumerateAttribute(.inlineImage, in: characters) { value, range, _ in
            guard let preview = value as? InlinePreview else { return }
            let line = layout.lineFragmentRect(
                forGlyphAt: layout.glyphIndexForCharacter(at: range.location), effectiveRange: nil)
            found.append(PlacedPreview(preview: preview, top: origin.y + line.minY + Self.imageGap, range: range))
        }
        return found
    }

    /// Makes room above an image line's first fragment, and keeps the source text at the bottom of it.
    // swiftlint:disable:next function_parameter_count
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer,
        forGlyphRange glyphRange: NSRange
    ) -> Bool {
        guard
            let preview = previewStarting(
                layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil))
        else { return false }
        let room = preview.room
        lineFragmentRect.pointee.size.height += room
        lineFragmentUsedRect.pointee.size.height += room
        baselineOffset.pointee += room
        return true
    }

    private func previewStarting(_ characters: NSRange) -> InlinePreview? {
        guard characters.length > 0, let storage = textStorage, characters.location < storage.length else { return nil }
        var effective = NSRange()
        let value = storage.attribute(.inlineImage, at: characters.location, effectiveRange: &effective)
        guard effective.location == characters.location else { return nil }
        return value as? InlinePreview
    }

    /// The column paints pictures behind the text, so it redraws whenever the text lays out again.
    func layoutManager(_ layoutManager: NSLayoutManager, didCompleteLayoutFor container: NSTextContainer?, atEnd: Bool)
    {
        superview?.needsDisplay = true
    }

    // MARK: Loading and resizing

    func watchInlineImages() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(inlineImageSettled(_:)), name: .inlineImageSettled, object: nil)
    }

    @objc private func inlineImageSettled(_ notification: Notification) {
        guard let url = notification.object as? URL, string.contains(url.lastPathComponent) else { return }
        restyle()
    }

    /// Pictures are sized to the column, so a new column width restyles a post that has any.
    func noteColumnWidthChanged() {
        guard string.contains("![") else { return }
        restyle()
    }
}
