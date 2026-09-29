import Foundation

/// A text block becomes Markdown only when that Markdown reads back as the same block.
/// Anything else stays on the `ec:block` fence, so a save never changes what it did not touch.
extension PortableText {
    static func faithfulLine(_ block: [String: JSONValue], render: (Bool) -> String) -> String? {
        let plain = render(false)
        if roundTrips(block, as: plain) { return plain }
        let escaped = render(true)
        return roundTrips(block, as: escaped) ? escaped : nil
    }

    static func roundTrips(_ block: [String: JSONValue], as line: String) -> Bool {
        let parsed = fromMarkdown(line)
        guard parsed.count == 1, let object = parsed[0].object else { return false }
        return normalized(object) == normalized(block)
    }

    /// Keys are random, and defaults may be left out. Neither is a difference.
    static func normalized(_ block: [String: JSONValue]) -> JSONValue {
        var copy = block
        copy["_key"] = nil
        copy["style"] = copy["style"] ?? .string("normal")
        if copy["listItem"] != nil, copy["level"] == nil {
            copy["level"] = .number(1)
        }
        let defs = copy["markDefs"]?.array ?? []
        let names = definitionNames(defs)
        copy["markDefs"] = .array(defs.map { renamedDefinition($0, names: names) })
        copy["children"] = .array(
            mergedSpans((copy["children"]?.array ?? []).map { normalizedChild($0, names: names) }))
        return .object(copy)
    }

    private static func definitionNames(_ defs: [JSONValue]) -> [String: String] {
        let pairs = defs.enumerated().compactMap { index, def in
            def.object?["_key"]?.string.map { ($0, "def\(index)") }
        }
        return Dictionary(pairs) { first, _ in first }
    }

    private static func renamedDefinition(_ def: JSONValue, names: [String: String]) -> JSONValue {
        guard var object = def.object, let key = object["_key"]?.string else { return def }
        object["_key"] = .string(names[key] ?? key)
        return .object(object)
    }

    private static func normalizedChild(_ child: JSONValue, names: [String: String]) -> JSONValue {
        guard var object = child.object, object["_type"]?.string == "span" else { return child }
        object["_key"] = nil
        let marks = (object["marks"]?.array ?? []).compactMap(\.string).map { names[$0] ?? $0 }.sorted()
        object["marks"] = .array(marks.map { .string($0) })
        return .object(object)
    }

    /// Two plain spans in a row with the same marks read the same as one.
    private static func mergedSpans(_ children: [JSONValue]) -> [JSONValue] {
        children.filter { !isEmptySpan($0) }.reduce(into: []) { merged, child in
            appendMerging(child, to: &merged)
        }
    }

    private static func appendMerging(_ child: JSONValue, to merged: inout [JSONValue]) {
        guard let last = merged.last, let joined = joined(last, child) else {
            merged.append(child)
            return
        }
        merged[merged.count - 1] = joined
    }

    private static func isEmptySpan(_ child: JSONValue) -> Bool {
        guard let object = child.object, isPlainSpan(object) else { return false }
        return object["text"]?.string?.isEmpty == true
    }

    private static func joined(_ first: JSONValue, _ second: JSONValue) -> JSONValue? {
        guard var left = first.object, let right = second.object, isPlainSpan(left), isPlainSpan(right) else {
            return nil
        }
        guard left["marks"] == right["marks"] else { return nil }
        left["text"] = .string((left["text"]?.string ?? "") + (right["text"]?.string ?? ""))
        return .object(left)
    }

    private static func isPlainSpan(_ object: [String: JSONValue]) -> Bool {
        object["_type"]?.string == "span" && Set(object.keys).isSubset(of: ["_type", "text", "marks"])
    }
}
