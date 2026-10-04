import Foundation

/// A custom Portable Text block a site plugin declares in the manifest (`portableTextBlocks`), with the
/// Block Kit fields its form is built from. Any EmDash site's blocks work; none are built in.
struct BlockDef: Equatable, Identifiable {
    var type: String
    var label: String
    var icon = ""
    var summary = ""
    var category = "Embeds"
    var fields: [BlockField]

    var id: String { type }
}

/// One Block Kit form field. Its value sits at the top level of the block under `actionID`.
struct BlockField: Equatable, Identifiable {
    enum Kind: Equatable {
        case text
        case number
        case choice
        case toggle
        /// A Block Kit element Emd does not edit. Its value is kept as it is.
        case other
    }

    var kind: Kind
    var actionID: String
    var label: String
    var placeholder = ""
    var help = ""
    var multiline = false
    var options: [Option] = []
    var minimum: Double?
    var maximum: Double?
    var initial: JSONValue?

    var id: String { actionID }

    struct Option: Equatable {
        var label: String
        var value: String
    }

    /// The value a new block starts with: the declared default, or the first sensible one for the kind.
    var startingValue: JSONValue {
        if let initial { return normalized(initial) }
        switch kind {
        case .text: return .string("")
        case .number: return .number(minimum ?? 0)
        case .choice: return .string(options.first?.value ?? "")
        case .toggle: return .bool(false)
        case .other: return .null
        }
    }

    /// Numbers are written as numbers, though a site may hand one back as a numeric string.
    func normalized(_ value: JSONValue) -> JSONValue {
        guard kind == .number, let text = value.string, let number = Double(text) else { return value }
        return .number(number)
    }

    func number(_ value: JSONValue?) -> Double {
        if let number = value?.number { return number }
        return value?.string.flatMap(Double.init) ?? startingValue.number ?? 0
    }

    func clamped(_ number: Double) -> Double {
        let low = minimum.map { max($0, number) } ?? number
        return maximum.map { min($0, low) } ?? low
    }
}

enum PageBlocks {
    /// Every enabled plugin's block definitions, by `_type`. A later plugin does not replace an earlier one.
    static func definitions(fromManifest manifest: JSONValue) -> [String: BlockDef] {
        let plugins = manifest.object?["plugins"]?.object ?? [:]
        let enabled = plugins.keys.sorted().compactMap { plugins[$0]?.object }.filter { $0["enabled"] != .bool(false) }
        let declared = enabled.flatMap { ($0["portableTextBlocks"]?.array ?? []).compactMap(block(from:)) }
        return Dictionary(declared.map { ($0.type, $0) }) { first, _ in first }
    }

    static func block(from value: JSONValue) -> BlockDef? {
        guard let object = value.object, let type = object["type"]?.string, !type.isEmpty else { return nil }
        let declared = (object["fields"]?.array ?? []).compactMap(field(from:))
        return BlockDef(
            type: type, label: object["label"]?.string ?? type, icon: object["icon"]?.string ?? "",
            summary: object["description"]?.string ?? "", category: object["category"]?.string ?? "Embeds",
            fields: declared.isEmpty ? [urlField(placeholder: object["placeholder"]?.string ?? "")] : declared)
    }

    /// A block declared without fields is edited by the admin as one address, stored as `url`.
    private static func urlField(placeholder: String) -> BlockField {
        BlockField(kind: .text, actionID: "url", label: "URL", placeholder: placeholder)
    }

    static func field(from value: JSONValue) -> BlockField? {
        guard let object = value.object, let id = object["action_id"]?.string, !id.isEmpty else { return nil }
        var field = BlockField(
            kind: kind(object["type"]?.string ?? ""), actionID: id, label: object["label"]?.string ?? id)
        field.placeholder = object["placeholder"]?.string ?? ""
        field.help = object["description"]?.string ?? ""
        field.multiline = object["multiline"] == .bool(true)
        field.minimum = object["min"]?.number
        field.maximum = object["max"]?.number
        field.initial = object["initial_value"]
        field.options = (object["options"]?.array ?? []).compactMap(option(from:))
        return field
    }

    private static func kind(_ type: String) -> BlockField.Kind {
        switch type {
        case "text_input": .text
        case "number_input": .number
        case "select", "radio", "combobox": .choice
        case "toggle": .toggle
        default: .other
        }
    }

    private static func option(from value: JSONValue) -> BlockField.Option? {
        guard let object = value.object, let value = object["value"]?.string else { return nil }
        return BlockField.Option(label: object["label"]?.string ?? value, value: value)
    }

    // MARK: Blocks

    /// A new block as the EmDash admin writes one: every field, defaults included, and an empty `id`.
    /// A block without its fields and with an empty `id` opens in the admin as "[Unknown block type]".
    static func newBlock(_ definition: BlockDef) -> [String: JSONValue] {
        var block: [String: JSONValue] = [
            "_type": .string(definition.type), "_key": .string(PortableText.key()), "id": .string(""),
        ]
        for field in definition.fields where field.kind != .other {
            block[field.actionID] = field.startingValue
        }
        return block
    }

    /// `values` written over the block. Fields Emd does not edit, and keys it does not know, stay.
    static func applying(_ values: [String: JSONValue], to block: [String: JSONValue], definition: BlockDef)
        -> [String: JSONValue]
    {
        var updated = block
        for field in definition.fields where field.kind != .other {
            updated[field.actionID] = field.normalized(
                values[field.actionID] ?? block[field.actionID] ?? field.startingValue)
        }
        if updated["id"] == nil { updated["id"] = .string("") }
        return updated
    }

    /// What a block's card says under its label: its fields' values, briefly.
    static func summary(_ block: [String: JSONValue], definition: BlockDef) -> String {
        definition.fields.compactMap { field in
            shown(block[field.actionID], field: field).map { "\(field.label): \($0)" }
        }.joined(separator: " · ")
    }

    private static func shown(_ value: JSONValue?, field: BlockField) -> String? {
        switch field.kind {
        case .text: quoted(value?.string ?? "")
        case .number: counted(field.number(value))
        case .choice: chosen(value?.string ?? "", field: field)
        case .toggle: value == .bool(true) ? "On" : "Off"
        case .other: nil
        }
    }

    private static func quoted(_ text: String) -> String? {
        text.isEmpty ? nil : "“\(text.count > 40 ? String(text.prefix(40)) + "…" : text)”"
    }

    private static func counted(_ number: Double) -> String {
        number.rounded() == number ? String(Int(number)) : String(number)
    }

    private static func chosen(_ raw: String, field: BlockField) -> String? {
        field.options.first { $0.value == raw }?.label ?? (raw.isEmpty ? nil : raw)
    }
}

/// A block on its own line of the body, `<!--ec:block {json} -->`, as Emd keeps anything it does not turn into
/// Markdown. A block a plugin defines draws as a card instead of showing this line.
enum BlockLine {
    static let prefix = "<!--ec:block "
    static let suffix = " -->"

    static func block(_ line: String) -> [String: JSONValue]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(prefix), trimmed.hasSuffix(suffix) else { return nil }
        let json = trimmed.dropFirst(prefix.count).dropLast(suffix.count)
        return (try? JSONDecoding.value(from: Data(json.utf8)))?.object
    }

    static func line(_ block: [String: JSONValue]) -> String {
        PortableText.fence(block)
    }
}
