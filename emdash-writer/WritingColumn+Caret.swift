import AppKit

/// Where the caret goes when a post opens, and when the editor takes the keyboard.
extension WritingColumn.Coordinator {
    /// The column is in a window. Wait one turn so layout has sized the text before placing the caret.
    func windowReady() {
        DispatchQueue.main.async { [weak self] in
            self?.restoreSpot()
        }
    }

    func restoreSpot() {
        guard let column, !restored else { return }
        let spot = CaretMemory.spot(for: parent.caretKey)
        let body = column.bodyView
        let length = (body.string as NSString).length
        column.layoutSubtreeIfNeeded()
        body.setSelectedRange(NSRange(location: min(spot?.caret ?? 0, length), length: 0))
        restored = true
        // Typewriter already centered the caret line when the selection moved.
        if !body.typewriter { scroll(to: spot?.scroll ?? 0) }
        focusIfWanted()
    }

    func rememberSpot() {
        guard restored, let column, let scroll else { return }
        let spot = CaretSpot(
            caret: column.bodyView.selectedRange().location,
            scroll: scroll.contentView.bounds.origin.y,
            seen: Date().timeIntervalSince1970
        )
        CaretMemory.remember(spot, for: parent.caretKey)
    }

    func focusIfWanted() {
        guard parent.wantsFocus, let body = column?.bodyView, let window = body.window else { return }
        if window.firstResponder !== body {
            window.makeFirstResponder(body)
        }
        let done = parent.onFocus
        DispatchQueue.main.async(execute: done)
    }

    func centerCaret(_ view: NSTextView) {
        guard let scroll, let column else { return }
        guard let layout = view.layoutManager, let container = view.textContainer else { return }
        let glyphRange = layout.glyphRange(forCharacterRange: view.selectedRange(), actualCharacterRange: nil)
        let caret = layout.boundingRect(forGlyphRange: glyphRange, in: container)
        column.layoutSubtreeIfNeeded()
        let inColumn = view.convert(caret, to: column)
        self.scroll(to: inColumn.midY - scroll.contentView.bounds.height * 0.42)
    }

    private func scroll(to y: CGFloat) {
        guard let scroll, let column else { return }
        let limit = max(0, column.bounds.height - scroll.contentView.bounds.height)
        var origin = scroll.contentView.bounds.origin
        origin.y = min(max(0, y), limit)
        scroll.contentView.setBoundsOrigin(origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}
