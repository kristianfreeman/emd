import AppKit

/// Where the caret may stop. A picture and the blank lines around it are one block with no caret positions
/// inside: landing anywhere in it selects the picture. A link's hidden Markdown is stepped over, so every
/// arrow press moves the caret somewhere you can see.
extension QuietTextView {
    /// The picture's folded line, and the block around it: the blank line before and after, when there is one.
    struct PictureBlock {
        var content: NSRange
        var first: Int
        var last: Int
    }

    func pictureBlock(around location: Int) -> PictureBlock? {
        [location, location + 1, location - 2].lazy
            .compactMap(imageContent(around:))
            .map { PictureBlock(content: $0, first: self.blockStart($0), last: self.blockEnd($0)) }
            .first { location >= $0.first && location <= $0.last }
    }

    private func blockStart(_ content: NSRange) -> Int {
        let ns = string as NSString
        let blankBefore =
            content.location >= 2 && ns.character(at: content.location - 1) == 0x0A
            && ns.character(at: content.location - 2) == 0x0A
        return blankBefore ? content.location - 1 : content.location
    }

    private func blockEnd(_ content: NSRange) -> Int {
        let ns = string as NSString
        let end = NSMaxRange(content)
        let blankAfter = end + 1 < ns.length && ns.character(at: end) == 0x0A && ns.character(at: end + 1) == 0x0A
        return blankAfter ? end + 1 : end
    }

    /// A caret in a picture's block selects the picture. From a selected picture, one step leaves the block:
    /// forward to the start of what follows, back to the end of what came before.
    func snappedToPicture(_ location: Int, block: PictureBlock, from old: NSRange) -> Int {
        let start = block.content.location
        guard location != start else { return start }
        let selected = old.length == 0 && old.location == start
        let length = textStorage?.length ?? 0
        if selected && location > start { return min(block.last + 1, length) }
        if selected && location < start { return max(block.first - 1, 0) }
        return start
    }

    // MARK: Links

    /// The hidden `[` or `](address)` of a link at or just before `location`.
    func linkMarkup(around location: Int) -> NSRange? {
        let run = hiddenCharacters.rangeView.first { $0.contains(location) || $0.contains(location - 1) }
        guard let run else { return nil }
        let range = NSRange(location: run.lowerBound, length: run.count)
        let text = (string as NSString).substring(with: range)
        return text == "[" || text.hasPrefix("](") ? range : nil
    }

    /// The two sides of hidden link Markdown look like one place. A step from either side goes one visible
    /// character further, instead of a press that seems to do nothing.
    func snappedPastLinkMarkup(_ location: Int, from old: NSRange) -> Int {
        guard old.length == 0, let markup = linkMarkup(around: location) else { return location }
        let length = textStorage?.length ?? 0
        if old.location == markup.location && location > markup.location {
            return min(NSMaxRange(markup) + 1, length)
        }
        if old.location == NSMaxRange(markup) && location < NSMaxRange(markup) {
            return max(markup.location - 1, 0)
        }
        return location
    }

    /// The text view's own arrows cannot cross characters drawn as nothing, so beside a link's hidden
    /// Markdown the step is made here: to one visible character past it.
    override func moveRight(_ sender: Any?) {
        guard let target = stepOverLinkMarkup(forward: true) else { return super.moveRight(sender) }
        place(target)
    }

    override func moveLeft(_ sender: Any?) {
        guard let target = stepOverLinkMarkup(forward: false) else { return super.moveLeft(sender) }
        place(target)
    }

    /// Word moves too: from the end of a link's label, on to the end of the next word; and never into
    /// the hidden address on the way back.
    override func moveWordRight(_ sender: Any?) {
        let start = selectedRange().location
        super.moveWordRight(sender)
        guard linkMarkup(around: start)?.location == start else { return }
        super.moveWordRight(sender)
    }

    override func moveWordLeft(_ sender: Any?) {
        super.moveWordLeft(sender)
        let caret = selectedRange().location
        guard let markup = linkMarkup(around: caret), caret > markup.location, caret <= NSMaxRange(markup) else {
            return
        }
        place(markup.location)
        super.moveWordLeft(sender)
    }

    private func stepOverLinkMarkup(forward: Bool) -> Int? {
        let caret = selectedRange()
        guard caret.length == 0, let markup = linkMarkup(around: caret.location) else { return nil }
        let length = textStorage?.length ?? 0
        if forward && caret.location == markup.location { return min(NSMaxRange(markup) + 1, length) }
        if !forward && caret.location == NSMaxRange(markup) { return max(markup.location - 1, 0) }
        return nil
    }

    private func place(_ location: Int) {
        super.setSelectedRanges(
            [NSValue(range: NSRange(location: location, length: 0))], affinity: .downstream, stillSelecting: false)
    }

    /// Deleting next to hidden link Markdown deletes the visible character beyond it, not the Markdown.
    func caretPastLinkMarkup(forward: Bool) {
        let caret = selectedRange()
        guard caret.length == 0, let markup = linkMarkup(around: caret.location) else { return }
        let edge = forward ? markup.location : NSMaxRange(markup)
        guard caret.location == edge else { return }
        let target = forward ? NSMaxRange(markup) : markup.location
        super.setSelectedRanges(
            [NSValue(range: NSRange(location: target, length: 0))], affinity: .downstream, stillSelecting: false)
    }
}
