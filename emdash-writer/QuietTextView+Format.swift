import AppKit
import SwiftUI

/// Format › Bold, Italic, Code, Link…, and the picture popover. Every change is one undoable edit of the Markdown.
extension QuietTextView {
    // MARK: Markers

    /// Wraps the selection in `marker`, or unwraps it when the marker is already around it.
    /// With nothing selected, it puts the caret between a pair.
    func toggleMarker(_ marker: String) {
        let ns = string as NSString
        let selection = selectedRange()
        let width = (marker as NSString).length
        if isWrapped(selection, by: marker, in: ns) {
            let outer = NSRange(location: selection.location - width, length: selection.length + width * 2)
            replaceRange(
                outer, with: ns.substring(with: selection),
                select: NSRange(location: outer.location, length: selection.length))
            return
        }
        let inner = ns.substring(with: selection)
        let caret = NSRange(location: selection.location + width, length: selection.length)
        replaceRange(selection, with: marker + inner + marker, select: caret)
    }

    private func isWrapped(_ range: NSRange, by marker: String, in ns: NSString) -> Bool {
        let width = (marker as NSString).length
        guard range.location >= width, NSMaxRange(range) + width <= ns.length else { return false }
        return ns.substring(with: NSRange(location: range.location - width, length: width)) == marker
            && ns.substring(with: NSRange(location: NSMaxRange(range), length: width)) == marker
    }

    /// One undoable replacement, then a selection inside the result.
    func replaceRange(_ range: NSRange, with text: String, select: NSRange) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        setSelectedRange(select)
    }

    // MARK: Links

    /// The whole `[label](address)` around the selection, with its label and address.
    func linkAround(_ selection: NSRange) -> FoundLink? {
        let ns = string as NSString
        let line = ns.lineRange(for: selection)
        let runs = MarkdownRuns.inline(in: ns.substring(with: line)).filter { $0.kind == .link }
        let hit = runs.first { run in
            let whole = run.markers.reduce(run.inner) { NSUnionRange($0, $1) }
            let absolute = NSRange(location: whole.location + line.location, length: whole.length)
            return NSLocationInRange(selection.location, absolute) || NSMaxRange(absolute) == selection.location
        }
        return hit.map { link($0, line: line.location, ns: ns) }
    }

    private func link(_ run: MarkdownRun, line: Int, ns: NSString) -> FoundLink {
        let whole = run.markers.reduce(run.inner) { NSUnionRange($0, $1) }
        let label = ns.substring(with: NSRange(location: run.inner.location + line, length: run.inner.length))
        let tail =
            run.markers.last.map { ns.substring(with: NSRange(location: $0.location + line, length: $0.length)) } ?? ""
        let address = String(tail.dropFirst(2).dropLast())
        return FoundLink(
            whole: NSRange(location: whole.location + line, length: whole.length), label: label, address: address)
    }

    /// ⌘K: edits the link under the caret, or links the selection. A copied URL fills the address.
    func editLink() {
        let selection = selectedRange()
        let words = (string as NSString).substring(with: selection)
        // A link is one run of words: not across paragraphs, and not half over another link.
        guard !words.contains(where: { "\n[]".contains($0) }) else { return NSSound.beep() }
        let found = linkAround(selection)
        let clipboard = NSPasteboard.general.string(forType: .string).flatMap { $0.hasPrefix("http") ? $0 : nil }
        let editor = LinkEditor(
            address: found?.address ?? clipboard ?? "", existing: found != nil,
            apply: { [weak self] address in self?.applyLink(address, to: found, selection: selection) },
            remove: { [weak self] in self?.unlink(found) })
        present(editor, at: firstRect(for: found?.whole ?? selection))
    }

    /// Links the selection, or rewrites the address of the link under it. With nothing selected the label is
    /// `link`, selected, so the next keystrokes replace it.
    func applyLink(_ address: String, to found: FoundLink?, selection: NSRange) {
        closePopover()
        let clean = address.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ")", with: "%29")
        let range = found?.whole ?? selection
        let typed = (string as NSString).substring(with: selection)
        let label = found?.label ?? (typed.isEmpty ? "link" : typed)
        let text = "[\(label)](\(clean))"
        let after = NSRange(location: range.location + (text as NSString).length, length: 0)
        let placeholder = NSRange(location: range.location + 1, length: (label as NSString).length)
        replaceRange(range, with: text, select: found == nil && typed.isEmpty ? placeholder : after)
    }

    func unlink(_ found: FoundLink?) {
        closePopover()
        guard let found else { return }
        replaceRange(
            found.whole, with: found.label,
            select: NSRange(location: found.whole.location, length: (found.label as NSString).length))
    }

    /// Pasting a single web address over selected words links them, as most writing apps do.
    /// Returns false when the paste should go ahead as text.
    func pasteLinkOverSelection(_ pasteboard: NSPasteboard = .general) -> Bool {
        let selection = selectedRange()
        guard selection.length > 0, let address = Self.webAddress(pasteboard.string(forType: .string)) else {
            return false
        }
        let words = (string as NSString).substring(with: selection)
        guard !words.contains(where: { "\n[]".contains($0) }), linkAround(selection) == nil else { return false }
        let text = "[\(words)](\(address))"
        replaceRange(
            selection, with: text, select: NSRange(location: selection.location + (text as NSString).length, length: 0))
        return true
    }

    static func webAddress(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.contains(where: \.isWhitespace),
            let url = URL(string: trimmed), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil
        else { return nil }
        return trimmed.replacingOccurrences(of: ")", with: "%29")
    }

    // MARK: Pictures

    func showImageDetails(_ range: NSRange) {
        guard let image = ImageLine((string as NSString).substring(with: range)) else { return }
        let details = ImageDetails(
            image,
            apply: { [weak self] edited in
                self?.closePopover()
                self?.replaceRange(range, with: edited.markdown, select: NSRange(location: range.location, length: 0))
            },
            editMarkdown: { [weak self] in
                self?.closePopover()
                self?.revealImage(range)
            },
            remove: { [weak self] in
                self?.closePopover()
                self?.setSelectedRange(NSRange(location: range.location, length: 0))
                self?.deleteBackward(nil)
            })
        present(details, at: pictureRect(range))
    }

    private func pictureRect(_ range: NSRange) -> NSRect {
        guard let placed = previews(in: bounds).first(where: { $0.range == range }) else {
            return firstRect(for: range)
        }
        let size = placed.preview.size
        return NSRect(x: bounds.midX - size.width / 2, y: placed.top, width: size.width, height: size.height)
    }

    // MARK: Popovers

    private static var popover: NSPopover?

    private func present<Content: View>(_ content: Content, at rect: NSRect) {
        closePopover()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: content)
        popover.show(relativeTo: rect, of: self, preferredEdge: .maxY)
        Self.popover = popover
    }

    private func closePopover() {
        Self.popover?.close()
        Self.popover = nil
    }

    /// The first line of `range` in this view's coordinates.
    private func firstRect(for range: NSRange) -> NSRect {
        guard let window else { return .zero }
        let screen = firstRect(forCharacterRange: range, actualRange: nil)
        return convert(window.convertFromScreen(screen), from: nil)
    }
}

/// A `[label](address)` in the text, and where all of it is.
struct FoundLink {
    var whole: NSRange
    var label: String
    var address: String
}

extension String {
    fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}
