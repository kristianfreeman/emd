import Foundation

/// Inline Markdown inside one block: marks nest, and a backslash makes the next character literal.
extension PortableText {
    typealias Inline = (spans: [JSONValue], markDefs: [JSONValue])

    /// `**` and `__` are strong, `*` and `_` are em. An underscore inside a word is just an underscore.
    private static let inlineExpression = try? NSRegularExpression(
        pattern: #"(\*\*(.+?)\*\*)|(__(.+?)__)|(\*(.+?)\*)|((?<![\p{L}\p{N}])_(.+?)_(?![\p{L}\p{N}]))"#
            + #"|(`(.+?)`)|(\[(.+?)\]\((.+?)\))|(~~(.+?)~~)"#
    )

    /// A capture group holding inner text, the mark it carries, and whether marks can nest inside it.
    private struct MarkGroup {
        var group: Int
        var mark: String
        var nests = true
    }

    private static let markGroups = [
        MarkGroup(group: 2, mark: "strong"), MarkGroup(group: 4, mark: "strong"),
        MarkGroup(group: 6, mark: "em"), MarkGroup(group: 8, mark: "em"),
        MarkGroup(group: 10, mark: "code", nests: false), MarkGroup(group: 15, mark: "strike-through"),
    ]

    static let escapable: [Character] = ["\\", "*", "_", "`", "[", "]", "~"]

    static func parseInline(_ text: String) -> Inline {
        var defs: [JSONValue] = []
        let spans = parse(shield(text), marks: [], defs: &defs).map(unshielded)
        guard !spans.isEmpty else { return ([span(unshield(text), marks: [])], defs) }
        return (spans, defs.map(unshieldedDef))
    }

    private static func parse(_ text: String, marks: [String], defs: inout [JSONValue]) -> [JSONValue] {
        guard let inlineExpression else { return [span(text, marks: marks)] }
        let ns = text as NSString
        var spans: [JSONValue] = []
        var cursor = 0
        for match in inlineExpression.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            spans += gap(ns, NSRange(location: cursor, length: match.range.location - cursor), marks: marks)
            spans += marked(match, ns: ns, marks: marks, defs: &defs)
            cursor = NSMaxRange(match.range)
        }
        spans += gap(ns, NSRange(location: cursor, length: ns.length - cursor), marks: marks)
        return spans
    }

    private static func gap(_ ns: NSString, _ range: NSRange, marks: [String]) -> [JSONValue] {
        guard range.length > 0 else { return [] }
        return [span(ns.substring(with: range), marks: marks)]
    }

    private static func marked(
        _ match: NSTextCheckingResult,
        ns: NSString,
        marks: [String],
        defs: inout [JSONValue]
    ) -> [JSONValue] {
        if let link = linked(match, ns: ns, marks: marks, defs: &defs) { return link }
        guard let found = markGroups.first(where: { match.range(at: $0.group).location != NSNotFound }) else {
            return [span(ns.substring(with: match.range), marks: marks)]
        }
        let inner = ns.substring(with: match.range(at: found.group))
        guard found.nests else { return [span(inner, marks: marks + [found.mark])] }
        return parse(inner, marks: marks + [found.mark], defs: &defs)
    }

    private static func linked(
        _ match: NSTextCheckingResult,
        ns: NSString,
        marks: [String],
        defs: inout [JSONValue]
    ) -> [JSONValue]? {
        let label = match.range(at: 12)
        let href = match.range(at: 13)
        guard label.location != NSNotFound, href.location != NSNotFound else { return nil }
        let mark = key()
        defs.append(
            .object(["_key": .string(mark), "_type": .string("link"), "href": .string(ns.substring(with: href))]))
        return parse(ns.substring(with: label), marks: marks + [mark], defs: &defs)
    }

    // MARK: Escapes

    /// `\*` becomes a private-use character the inline pattern cannot see, and comes back as `*`.
    static func shield(_ text: String) -> String {
        var result = ""
        var escaping = false
        for character in text {
            result += shielded(character, escaping: escaping)
            escaping = !escaping && character == "\\"
        }
        return escaping ? result + "\\" : result
    }

    private static func shielded(_ character: Character, escaping: Bool) -> String {
        guard escaping else { return character == "\\" ? "" : String(character) }
        guard let index = escapable.firstIndex(of: character) else { return "\\" + String(character) }
        return String(Character(placeholder(index)))
    }

    static func unshield(_ text: String) -> String {
        String(
            text.map { character -> Character in
                guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else {
                    return character
                }
                let index = Int(scalar.value) - 0xE000
                return escapable.indices.contains(index) ? escapable[index] : character
            })
    }

    static func escaped(_ text: String) -> String {
        text.map { escapable.contains($0) ? "\\\($0)" : String($0) }.joined()
    }

    private static func placeholder(_ index: Int) -> Unicode.Scalar {
        Unicode.Scalar(0xE000 + index) ?? "?"
    }

    private static func unshielded(_ value: JSONValue) -> JSONValue {
        guard var object = value.object, let text = object["text"]?.string else { return value }
        object["text"] = .string(unshield(text))
        return .object(object)
    }

    private static func unshieldedDef(_ value: JSONValue) -> JSONValue {
        guard var object = value.object, let href = object["href"]?.string else { return value }
        object["href"] = .string(unshield(href))
        return .object(object)
    }
}
