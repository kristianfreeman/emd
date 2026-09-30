import AppKit

/// Lists read as lists: `-`, `*`, and `+` draw as bullets, numbers stay muted, wrapped lines hang under the
/// item's text, and nesting indents by level. Return continues a list and Tab nests an item. The text stays
/// Markdown; a bullet is a different glyph for the same character.
extension QuietTextView {
    static let listItem = /^([ \t]*)([-*+]|\d+[.)])([ \t]+)(.*)$/

    func styleListLine(_ line: NSRange, text: String, style: inout LineStyle) {
        let content = strippedNewline(line, ns: string as NSString)
        let body = (string as NSString).substring(with: content)
        guard let item = body.wholeMatch(of: Self.listItem) else { return }
        let indent = (item.output.1 as Substring).utf16.count
        let marker = (item.output.2 as Substring).utf16.count
        let gap = (item.output.3 as Substring).utf16.count
        let isBullet = !(item.output.2.first?.isNumber ?? false)
        style.hidden.insert(integersIn: content.location..<(content.location + indent))
        let markerRange = NSRange(location: content.location + indent, length: marker)
        if isBullet { style.bullets.insert(markerRange.location) }
        style.storage.addAttribute(.foregroundColor, value: mutedColor, range: markerRange)
        let level = CGFloat(item.output.1.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2)
        let lead = markerWidth(isBullet ? "•" : String(item.output.2), gap: gap, font: style.base)
        style.storage.addAttribute(.paragraphStyle, value: listParagraph(style, level: level, lead: lead), range: line)
    }

    private func markerWidth(_ marker: String, gap: Int, font: NSFont) -> CGFloat {
        let text = marker + String(repeating: " ", count: max(1, gap))
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private func listParagraph(_ style: LineStyle, level: CGFloat, lead: CGFloat) -> NSParagraphStyle {
        let paragraph = (style.paragraph.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        let step = style.base.pointSize * 1.5
        paragraph.firstLineHeadIndent = level * step
        paragraph.headIndent = level * step + lead
        return paragraph
    }

    // MARK: Keys

    /// Return at the end of an item starts the next one; on an empty item it ends the list.
    func continueList() -> Bool {
        let caret = selectedRange()
        guard caret.length == 0 else { return false }
        let ns = string as NSString
        let line = strippedNewline(ns.lineRange(for: caret), ns: ns)
        guard let item = ns.substring(with: line).wholeMatch(of: Self.listItem) else { return false }
        guard !item.output.4.isEmpty else {
            insertText("", replacementRange: line)
            return true
        }
        let marker = nextMarker(String(item.output.2))
        insertText("\n" + item.output.1 + marker + item.output.3, replacementRange: caret)
        return true
    }

    private func nextMarker(_ marker: String) -> String {
        guard let number = Int(marker.dropLast()) else { return marker }
        return "\(number + 1)\(marker.last ?? ".")"
    }

    override func insertTab(_ sender: Any?) {
        guard shiftListItem(by: 2) else { return super.insertTab(sender) }
    }

    override func insertBacktab(_ sender: Any?) {
        guard shiftListItem(by: -2) else { return super.insertBacktab(sender) }
    }

    /// Adds or removes two spaces at the start of the caret's list item.
    private func shiftListItem(by spaces: Int) -> Bool {
        let ns = string as NSString
        let line = ns.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        guard ns.substring(with: strippedNewline(line, ns: ns)).wholeMatch(of: Self.listItem) != nil else {
            return false
        }
        if spaces > 0 {
            insertText("  ", replacementRange: NSRange(location: line.location, length: 0))
            return true
        }
        let leading = ns.substring(with: line).prefix { $0 == " " }.count
        insertText("", replacementRange: NSRange(location: line.location, length: min(leading, -spaces)))
        return true
    }

    /// Draws each list marker in `bulletCharacters` as `•`, in the same font.
    func swapBullets(_ glyphs: inout [CGGlyph], source: GlyphSource) -> Bool {
        guard !bulletCharacters.isEmpty else { return false }
        var character: UniChar = 0x2022
        var bullet: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(source.font, &character, &bullet, 1), bullet != 0 else { return false }
        var swapped = false
        for index in glyphs.indices where bulletCharacters.contains(Int(source.indexes[index])) {
            glyphs[index] = bullet
            swapped = true
        }
        return swapped
    }

    // MARK: Spelling

    /// Pictures, link targets, Markdown markers, and inline code are not prose.
    func allowsSpelling(in range: NSRange) -> Bool {
        guard let storage = textStorage, range.length > 0, NSMaxRange(range) <= storage.length else { return true }
        return !touchesPicture(range, storage: storage) && !touchesMarkup(range)
    }

    private func touchesMarkup(_ range: NSRange) -> Bool {
        let ns = string as NSString
        let line = ns.lineRange(for: range)
        return MarkdownRuns.inline(in: ns.substring(with: line)).contains { run in
            let pieces = run.kind == .code ? run.markers + [run.inner] : run.markers
            return pieces.contains { NSIntersectionRange(offset($0, by: line.location), range).length > 0 }
        }
    }

    private func touchesPicture(_ range: NSRange, storage: NSTextStorage) -> Bool {
        var found = false
        storage.enumerateAttribute(.inlineImage, in: range) { value, _, stop in
            found = value != nil
            stop.pointee = ObjCBool(found)
        }
        return found
    }
}
