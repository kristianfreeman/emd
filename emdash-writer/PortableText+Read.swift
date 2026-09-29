import Foundation

extension PortableText {
    static func fromMarkdown(_ markdown: String) -> [JSONValue] {
        var blocks: [JSONValue] = []
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < lines.count {
            index = consume(lines, at: index, blocks: &blocks)
        }
        return blocks
    }

    private static let headingPattern = /^(#{1,6})\s+(.+)$/
    private static let bulletPattern = /^(\s*)[-*+]\s+(.+)$/
    private static let numberPattern = /^(\s*)\d+\.\s+(.+)$/
    private static let fencePattern = /^<!--ec:block (.+) -->$/
    /// `![alt](url)`, or `![alt](url =1200x800)` when the size is known.
    private static let imagePattern = /^!\[([^\]]*)\]\(([^)\s]+)(?:\s+=(\d+)x(\d+))?\)$/

    private static func consume(_ lines: [String], at index: Int, blocks: inout [JSONValue]) -> Int {
        if let next = consumeSpecial(lines, at: index, blocks: &blocks) { return next }
        return consumeProse(lines[index], at: index, blocks: &blocks)
    }

    private static func consumeSpecial(_ lines: [String], at index: Int, blocks: inout [JSONValue]) -> Int? {
        let line = lines[index]
        if let fenced = opaque(line) {
            blocks.append(.object(fenced))
            return index + 1
        }
        if line.hasPrefix("```") {
            return consumeFence(lines, at: index, blocks: &blocks)
        }
        if isUploading(line) {
            return index + 1
        }
        if let image = imageBlock(line) {
            blocks.append(image)
            return index + 1
        }
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            return index + 1
        }
        return nil
    }

    private static func consumeFence(_ lines: [String], at index: Int, blocks: inout [JSONValue]) -> Int {
        let language = String(lines[index].dropFirst(3)).trimmingCharacters(in: .whitespaces)
        var code: [String] = []
        let closed = readFenceBody(lines, from: index + 1, code: &code)
        blocks.append(.object(codeBlock(code, language: language)))
        return afterFence(closed, count: lines.count)
    }

    private static func readFenceBody(_ lines: [String], from index: Int, code: inout [String]) -> Int {
        var cursor = index
        while cursor < lines.count && !lines[cursor].hasPrefix("```") {
            code.append(lines[cursor])
            cursor += 1
        }
        return cursor
    }

    private static func codeBlock(_ code: [String], language: String) -> [String: JSONValue] {
        var object: [String: JSONValue] = [
            "_type": .string("code"),
            "_key": .string(key()),
            "code": .string(code.joined(separator: "\n")),
        ]
        guard !language.isEmpty else { return object }
        object["language"] = .string(language)
        return object
    }

    private static func afterFence(_ index: Int, count: Int) -> Int {
        guard index < count else { return index }
        return index + 1
    }

    private static func consumeProse(_ line: String, at index: Int, blocks: inout [JSONValue]) -> Int {
        if let match = line.wholeMatch(of: headingPattern) {
            blocks.append(block(String(match.output.2), style: "h\(match.output.1.count)"))
            return index + 1
        }
        if line.hasPrefix("> ") {
            blocks.append(block(String(line.dropFirst(2)), style: "blockquote"))
            return index + 1
        }
        if let match = line.wholeMatch(of: bulletPattern) {
            blocks.append(listItem(String(match.output.2), kind: "bullet", indent: match.output.1.count))
            return index + 1
        }
        if let match = line.wholeMatch(of: numberPattern) {
            blocks.append(listItem(String(match.output.2), kind: "number", indent: match.output.1.count))
            return index + 1
        }
        blocks.append(block(line, style: "normal"))
        return index + 1
    }

    /// An image still uploading has no file on the site yet. It never leaves this Mac.
    private static func isUploading(_ line: String) -> Bool {
        line.hasPrefix("![") && line.contains("](\(uploadingScheme)")
    }

    private static func imageBlock(_ line: String) -> JSONValue? {
        guard let match = line.wholeMatch(of: imagePattern) else { return nil }
        let url = String(match.output.2)
        var asset: [String: JSONValue] = ["url": .string(url)]
        if let id = mediaID(url) { asset["_ref"] = .string(id) }
        var object: [String: JSONValue] = ["_type": .string("image"), "_key": .string(key()), "asset": .object(asset)]
        if !match.output.1.isEmpty { object["alt"] = .string(String(match.output.1)) }
        if let width = match.output.3.flatMap({ Double($0) }), let height = match.output.4.flatMap({ Double($0) }) {
            object["width"] = .number(width)
            object["height"] = .number(height)
        }
        return .object(object)
    }

    private static func opaque(_ line: String) -> [String: JSONValue]? {
        guard let match = line.wholeMatch(of: fencePattern) else { return nil }
        return decodedFence(String(match.output.1))
    }

    private static func decodedFence(_ json: String) -> [String: JSONValue]? {
        guard let data = json.data(using: .utf8),
            let value = try? JSONDecoding.value(from: data),
            let object = value.object
        else { return nil }
        return object
    }

    private static func block(_ text: String, style: String) -> JSONValue {
        let inline = parseInline(text)
        return .object([
            "_type": .string("block"),
            "_key": .string(key()),
            "style": .string(style),
            "markDefs": .array(inline.markDefs),
            "children": .array(inline.spans),
        ])
    }

    private static func listItem(_ text: String, kind: String, indent: Int) -> JSONValue {
        let inline = parseInline(text)
        return .object([
            "_type": .string("block"),
            "_key": .string(key()),
            "style": .string("normal"),
            "listItem": .string(kind),
            "level": .number(Double(max(1, indent / 2 + 1))),
            "markDefs": .array(inline.markDefs),
            "children": .array(inline.spans),
        ])
    }
}
