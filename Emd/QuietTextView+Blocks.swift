import AppKit
import SwiftUI

/// How a card or a divider looks. Drawn by the column in the room its line makes, as a picture is.
struct ObjectFace {
    enum Kind {
        case card
        case divider
    }

    var kind: Kind
    var title: String
    var summary = ""
    var symbol = ""
    var ink: NSColor
    var muted: NSColor

    static let cardHeight: CGFloat = 60
    static let dividerHeight: CGFloat = 26

    func draw(in frame: NSRect, ink placeholder: NSColor, dimmed: Bool) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if dimmed { NSGraphicsContext.current?.cgContext.setAlpha(0.35) }
        switch kind {
        case .card: drawCard(in: frame)
        case .divider: drawDivider(in: frame)
        }
    }

    private func drawCard(in frame: NSRect) {
        let box = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        muted.withAlphaComponent(0.08).setFill()
        box.fill()
        muted.withAlphaComponent(0.3).setStroke()
        box.lineWidth = 1
        box.stroke()
        let icon = NSRect(x: frame.minX + 14, y: frame.midY - 10, width: 20, height: 20)
        drawSymbol(in: icon)
        let textX = icon.maxX + 12
        let width = frame.maxX - 14 - textX
        let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let summaryFont = NSFont.systemFont(ofSize: 12)
        draw(title, font: titleFont, color: ink, in: NSRect(x: textX, y: frame.minY + 12, width: width, height: 18))
        draw(
            summary.isEmpty ? "Double-click to edit" : summary, font: summaryFont, color: muted,
            in: NSRect(x: textX, y: frame.minY + 31, width: width, height: 17))
    }

    private func drawSymbol(in rect: NSRect) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            .applying(.init(paletteColors: [muted]))
        guard
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        else { return }
        let size = image.size
        let target = NSRect(
            x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    /// The region's name in small capitals, then a hairline to the end of the text.
    private func drawDivider(in frame: NSRect) {
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let label = title.uppercased() as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: muted, .kern: 1.2]
        let size = label.size(withAttributes: attributes)
        label.draw(at: NSPoint(x: frame.minX, y: frame.midY - size.height / 2), withAttributes: attributes)
        let rule = NSRect(x: frame.minX + size.width + 10, y: frame.midY.rounded(), width: 0, height: 1)
        muted.withAlphaComponent(0.35).setFill()
        NSRect(x: rule.minX, y: rule.minY, width: max(0, frame.maxX - rule.minX), height: 1).fill()
    }

    private func draw(_ text: String, font: NSFont, color: NSColor, in rect: NSRect) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(
            with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }

    /// EmDash's icon keys, as SF Symbols.
    static func symbol(_ icon: String) -> String {
        let symbols = [
            "list": "list.bullet", "link": "link", "link-external": "arrow.up.right.square", "video": "play.rectangle",
            "code": "chevron.left.forwardslash.chevron.right", "image": "photo", "music": "music.note",
        ]
        return symbols[icon] ?? "square.grid.2x2"
    }
}

/// Blocks a plugin defines draw as cards, and a page's regions start with a divider. Both are objects, as
/// pictures are (see `QuietTextView+ImageObject`): one caret stop, Delete removes a card, and a double-click
/// on a card opens its form. A divider cannot be deleted, so saving always has each region's text.
extension QuietTextView {
    /// Styles `context.line` as a card or a divider when it is one. Other lines leave on the first check.
    func styleObjectLine(_ context: LineContext, text: String, style: inout LineStyle) -> Bool {
        guard text.hasPrefix("<!--") else { return false }
        let content = strippedNewline(context.line, ns: context.ns)
        guard let face = objectFace(context.ns.substring(with: content)) else { return false }
        let padding = (textContainer?.lineFragmentPadding ?? 0) * 2
        let height = face.kind == .card ? ObjectFace.cardHeight : ObjectFace.dividerHeight
        let size = NSSize(width: max(0, (textContainer?.size.width ?? 0) - padding), height: height)
        let preview = InlinePreview(face: face, size: size, dimmed: focusMode && !context.editing)
        let open = revealedImage == content.location
        style.storage.addAttribute(.inlineImage, value: preview, range: content)
        style.storage.addAttribute(
            .paragraphStyle, value: imageParagraph(size, editing: open, style), range: context.line)
        foldSource(content, editing: open, style: &style)
        return true
    }

    func objectFace(_ line: String) -> ObjectFace? {
        if let slug = Regions.slug(line) { return dividerFace(slug) }
        guard let block = BlockLine.block(line), let type = block["_type"]?.string, let definition = blockDefs[type]
        else { return nil }
        return ObjectFace(
            kind: .card, title: definition.label, summary: PageBlocks.summary(block, definition: definition),
            symbol: ObjectFace.symbol(definition.icon), ink: syntaxInk, muted: mutedColor)
    }

    /// A marker for a field this entry does not have stays a line of text, so nothing hides it.
    private func dividerFace(_ slug: String) -> ObjectFace? {
        regionLabels[slug].map { ObjectFace(kind: .divider, title: $0, ink: syntaxInk, muted: mutedColor) }
    }

    func isDivider(_ range: NSRange) -> Bool {
        Regions.slug((string as NSString).substring(with: range)) != nil
    }

    // MARK: Cards

    /// The block on a card's line, with its definition, when the line is a card.
    func card(_ range: NSRange) -> (block: [String: JSONValue], definition: BlockDef)? {
        guard let block = BlockLine.block((string as NSString).substring(with: range)),
            let definition = blockDefs[block["_type"]?.string ?? ""]
        else { return nil }
        return (block, definition)
    }

    func showBlockDetails(_ range: NSRange) {
        guard window != nil, let found = card(range) else { return }
        let form = BlockDetails(
            definition: found.definition, block: found.block,
            apply: { [weak self] block in
                self?.closePopover()
                self?.replaceRange(
                    range, with: BlockLine.line(block), select: NSRange(location: range.location, length: 0))
            },
            remove: { [weak self] in
                self?.closePopover()
                self?.setSelectedRange(NSRange(location: range.location, length: 0))
                self?.deleteBackward(nil)
            })
        guard let column = superview, let root = window?.contentView,
            let placed = previews(in: bounds).first(where: { $0.range == range })
        else { return present(form, at: firstRect(for: range)) }
        // The column draws the card; the form points at that frame, measured in the window's own view.
        let top = column.convert(NSPoint(x: 0, y: placed.top), from: self).y
        let card = column.convert(placed.preview.frame(top: top, text: frame), to: root)
        present(form, at: card, in: root)
    }

    /// Post › Insert Section: a new block with every field at its default, as a paragraph of its own at the
    /// caret, and its form open.
    func insertBlock(_ definition: BlockDef) {
        let line = BlockLine.line(PageBlocks.newBlock(definition))
        let ns = string as NSString
        let caret = selectedRange()
        let paragraph = ns.paragraphRange(for: caret)
        let empty = ns.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let at = empty ? paragraph.location : NSMaxRange(paragraph)
        let lead = at == 0 || empty ? "" : (ns.substring(with: paragraph).hasSuffix("\n") ? "\n" : "\n\n")
        // One blank line after the block: the text after it may already start with a line break.
        let trail = at >= ns.length ? "" : (ns.character(at: at) == 0x0A ? "\n" : "\n\n")
        let text = lead + line + trail
        let start = at + (lead as NSString).length
        replaceRange(
            NSRange(location: at, length: empty ? paragraph.length : 0), with: text,
            select: NSRange(location: start, length: 0))
        restyle(around: NSRange(location: start, length: (line as NSString).length))
        DispatchQueue.main.async { [weak self] in
            self?.showBlockDetails(NSRange(location: start, length: (line as NSString).length))
        }
    }

    // MARK: Dividers stay

    /// An edit that would change or remove a region's divider line is refused. Checked on the lines the edit
    /// touches and the line after, so joining the next line onto a divider is caught too.
    func breaksDivider(_ range: NSRange, with replacement: String?) -> Bool {
        guard !regionLabels.isEmpty else { return false }
        let ns = string as NSString
        let reach = NSRange(location: range.location, length: min(range.length + 1, ns.length - range.location))
        let local = ns.lineRange(for: reach)
        let before = ns.substring(with: local)
        guard before.contains("<!--emd:region ") else { return false }
        let inner = NSRange(location: range.location - local.location, length: range.length)
        let after = (before as NSString).replacingCharacters(in: inner, with: replacement ?? "")
        return Self.dividers(in: before) != Self.dividers(in: after)
    }

    private static func dividers(in text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { Regions.slug(String($0)) }
    }

    override func shouldChangeText(in range: NSRange, replacementString: String?) -> Bool {
        guard !breaksDivider(range, with: replacementString) else {
            NSSound.beep()
            return false
        }
        return super.shouldChangeText(in: range, replacementString: replacementString)
    }
}

/// A card's form, generated from the block's Block Kit fields.
struct BlockDetails: View {
    let definition: BlockDef
    let block: [String: JSONValue]
    let apply: ([String: JSONValue]) -> Void
    let remove: () -> Void
    @State private var values: [String: JSONValue]

    init(
        definition: BlockDef, block: [String: JSONValue], apply: @escaping ([String: JSONValue]) -> Void,
        remove: @escaping () -> Void
    ) {
        self.definition = definition
        self.block = block
        self.apply = apply
        self.remove = remove
        let current = definition.fields.map { ($0.actionID, $0.normalized(block[$0.actionID] ?? $0.startingValue)) }
        _values = State(initialValue: Dictionary(current) { first, _ in first })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(definition.label).font(.headline)
                if !definition.summary.isEmpty {
                    Text(definition.summary).font(.callout).foregroundStyle(.secondary)
                }
            }
            Form {
                ForEach(definition.fields) { field in
                    BlockFieldRow(field: field, value: binding(field))
                }
            }
            .onSubmit(done)
            HStack {
                Button("Remove", role: .destructive, action: remove)
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private func binding(_ field: BlockField) -> Binding<JSONValue> {
        Binding(get: { values[field.actionID] ?? field.startingValue }, set: { values[field.actionID] = $0 })
    }

    private func done() {
        apply(PageBlocks.applying(values, to: block, definition: definition))
    }
}

private struct BlockFieldRow: View {
    let field: BlockField
    @Binding var value: JSONValue

    var body: some View {
        switch field.kind {
        case .text:
            TextField(
                field.label, text: text, prompt: Text(field.placeholder),
                axis: field.multiline ? .vertical : .horizontal)
        case .number:
            LabeledContent(field.label) {
                HStack {
                    TextField(field.label, value: number, format: .number)
                        .labelsHidden()
                        .frame(width: 70)
                    Stepper(
                        field.label, value: number, in: (field.minimum ?? -.infinity)...(field.maximum ?? .infinity)
                    )
                    .labelsHidden()
                }
            }
        case .choice:
            Picker(field.label, selection: text) {
                ForEach(field.options, id: \.value) { Text($0.label).tag($0.value) }
            }
        case .toggle:
            Toggle(field.label, isOn: toggle)
        case .other:
            LabeledContent(field.label) {
                Text("Edit in the EmDash admin").foregroundStyle(.secondary)
            }
        }
    }

    private var text: Binding<String> {
        Binding(get: { value.string ?? "" }, set: { value = .string($0) })
    }

    private var number: Binding<Double> {
        Binding(get: { field.number(value) }, set: { value = .number(field.clamped($0)) })
    }

    private var toggle: Binding<Bool> {
        Binding(get: { value == .bool(true) }, set: { value = .bool($0) })
    }
}
