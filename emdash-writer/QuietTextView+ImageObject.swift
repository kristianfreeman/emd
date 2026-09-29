import AppKit

/// A picture is one object in the text. The caret stops on it once, as a selection ring, and the next
/// move goes past it. A selection that touches it takes all of it. Delete removes it; Return or typing
/// starts a paragraph after it. A double-click opens its details; its Markdown folds again once the caret leaves.
extension QuietTextView {
    /// The folded Markdown of the picture at or just before `index`.
    func imageContent(around index: Int) -> NSRange? {
        [index, index - 1].lazy.compactMap(imageAttribute(at:)).first { $0.location != revealedImage }
    }

    private func imageAttribute(at index: Int) -> NSRange? {
        guard let storage = textStorage, index >= 0, index < storage.length else { return nil }
        var range = NSRange()
        return storage.attribute(.inlineImage, at: index, effectiveRange: &range) == nil ? nil : range
    }

    func isImageObjectSelected(_ range: NSRange) -> Bool {
        let selection = selectedRange()
        return selection.length == 0 && selection.location == range.location && range.location != revealedImage
    }

    /// The selected picture, when the caret is resting on one.
    private var selectedImage: NSRange? {
        let selection = selectedRange()
        guard selection.length == 0, let image = imageContent(around: selection.location) else { return nil }
        return image.location == selection.location ? image : nil
    }

    override var shouldDrawInsertionPoint: Bool {
        selectedImage == nil && super.shouldDrawInsertionPoint
    }

    override func setSelectedRanges(
        _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool
    ) {
        let old = selectedRange()
        let adjusted = ranges.map { NSValue(range: snapped($0.rangeValue, from: old)) }
        super.setSelectedRanges(adjusted, affinity: affinity, stillSelecting: stillSelectingFlag)
        foldRevealedImageIfLeft()
        hideCaretOnImage()
        superview?.needsDisplay = true
    }

    /// On macOS 14 and later the caret is its own indicator view, which ignores `shouldDrawInsertionPoint`,
    /// so a selected picture clears the caret's color instead. The ring is the only mark.
    private func hideCaretOnImage() {
        let color = selectedImage == nil ? syntaxInk : .clear
        guard insertionPointColor != color else { return }
        insertionPointColor = color
    }

    private func snapped(_ range: NSRange, from old: NSRange) -> NSRange {
        guard range.length == 0 else { return widened(range) }
        if let block = pictureBlock(around: range.location) {
            return NSRange(location: snappedToPicture(range.location, block: block, from: old), length: 0)
        }
        return NSRange(location: snappedPastLinkMarkup(range.location, from: old), length: 0)
    }

    private func widened(_ range: NSRange) -> NSRange {
        [range.location, NSMaxRange(range)].compactMap(imageContent(around:)).reduce(range) { NSUnionRange($0, $1) }
    }

    // MARK: Keys on a selected picture

    override func deleteBackward(_ sender: Any?) {
        guard let image = selectedImage else {
            caretPastLinkMarkup(forward: false)
            return super.deleteBackward(sender)
        }
        removeImage(image)
    }

    override func deleteForward(_ sender: Any?) {
        guard let image = selectedImage else {
            caretPastLinkMarkup(forward: true)
            return super.deleteForward(sender)
        }
        removeImage(image)
    }

    /// On a picture, Return starts a paragraph after it. In a list, it starts the next item.
    override func insertNewline(_ sender: Any?) {
        if let image = selectedImage { return startParagraph(after: image, with: "") }
        guard !continueList() else { return }
        super.insertNewline(sender)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard replacementRange.location == NSNotFound, let image = selectedImage else {
            return super.insertText(string, replacementRange: replacementRange)
        }
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        startParagraph(after: image, with: text)
    }

    /// Takes the picture's line and the blank line that set it apart.
    private func removeImage(_ image: NSRange) {
        let ns = string as NSString
        var range = image
        while NSMaxRange(range) < ns.length, ns.character(at: NSMaxRange(range)) == 0x0A,
            range.length < image.length + 2
        {
            range.length += 1
        }
        replaceAndPlaceCaret(range, with: "", caret: image.location)
    }

    private func startParagraph(after image: NSRange, with text: String) {
        let end = NSMaxRange(image)
        replaceAndPlaceCaret(
            NSRange(location: end, length: 0), with: "\n\n" + text, caret: end + 2 + (text as NSString).length)
    }

    private func replaceAndPlaceCaret(_ range: NSRange, with text: String, caret: Int) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        super.setSelectedRanges(
            [NSValue(range: NSRange(location: caret, length: 0))], affinity: .downstream, stillSelecting: false)
    }

    // MARK: Opening the Markdown

    /// A double-click on a picture opens its details. Edit Markdown there opens the line itself.
    override func mouseDown(with event: NSEvent) {
        let index = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        guard event.clickCount == 2, let image = imageContent(around: index) else {
            return super.mouseDown(with: event)
        }
        super.setSelectedRanges(
            [NSValue(range: NSRange(location: image.location, length: 0))], affinity: .downstream, stillSelecting: false
        )
        showImageDetails(image)
    }

    func revealImage(_ image: NSRange) {
        revealedImage = image.location
        restyle(around: image)
        super.setSelectedRanges(
            [NSValue(range: NSRange(location: NSMaxRange(image), length: 0))], affinity: .downstream,
            stillSelecting: false)
    }

    private func foldRevealedImageIfLeft() {
        guard let revealed = revealedImage else { return }
        let ns = string as NSString
        guard revealed < ns.length else {
            revealedImage = nil
            return
        }
        let line = ns.lineRange(for: NSRange(location: revealed, length: 0))
        let caret = selectedRange()
        guard caret.location < line.location || caret.location > NSMaxRange(line) - 1 || caret.length > 0 else {
            return
        }
        revealedImage = nil
        restyle(around: line)
    }
}
