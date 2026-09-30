import AppKit

/// Images dropped or pasted onto the page. The view says where they landed; the model uploads them.
extension QuietTextView {
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes + [.fileURL, .png, .tiff]
    }

    override func dragOperation(for dragInfo: NSDraggingInfo, type: NSPasteboard.PasteboardType) -> NSDragOperation {
        guard onImages != nil, !ImageSource.from(dragInfo.draggingPasteboard).isEmpty else {
            return super.dragOperation(for: dragInfo, type: type)
        }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let sources = ImageSource.from(sender.draggingPasteboard)
        guard let onImages, !sources.isEmpty else { return super.performDragOperation(sender) }
        let point = convert(sender.draggingLocation, from: nil)
        onImages(sources, characterIndexForInsertion(at: point))
        return true
    }

    /// Pasting an image uploads it. Anything else pastes as plain text.
    func pasteImagesIfAny() -> Bool {
        let sources = ImageSource.from(.general)
        guard let onImages, !sources.isEmpty else { return false }
        onImages(sources, selectedRange().location)
        return true
    }

    /// Inserts `lines` as their own paragraphs at `index`, as one undoable edit.
    func insertParagraphs(_ lines: [String], at index: Int) {
        let ns = string as NSString
        let location = min(max(0, index), ns.length)
        let lead = location > 0 && ns.character(at: location - 1) != 0x0A ? "\n\n" : ""
        let trail = location < ns.length && ns.character(at: location) != 0x0A ? "\n\n" : ""
        let text = lead + lines.joined(separator: "\n\n") + trail
        replace(NSRange(location: location, length: 0), with: text)
    }

    /// Swaps one exact piece of text for another, as an edit the writer can undo.
    @discardableResult
    func replaceText(_ old: String, with new: String) -> Bool {
        let range = (string as NSString).range(of: old)
        guard range.location != NSNotFound else { return false }
        replace(range, with: new)
        return true
    }

    private func replace(_ range: NSRange, with text: String) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
    }
}
