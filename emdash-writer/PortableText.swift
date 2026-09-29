import Foundation

enum PortableText {
    static func markdownData(from data: [String: JSONValue], fields: [FieldDef]) -> [String: JSONValue] {
        var copy = data
        for field in fields where field.type == "portableText" {
            if let blocks = copy[field.slug]?.array {
                copy[field.slug] = .string(toMarkdown(blocks))
            }
        }
        return copy
    }

    static func portableData(from data: [String: JSONValue], fields: [FieldDef]) -> [String: JSONValue] {
        var copy = data
        for field in fields where field.type == "portableText" {
            if let markdown = copy[field.slug]?.string {
                copy[field.slug] = .array(fromMarkdown(markdown))
            }
        }
        return copy
    }

    static func toMarkdown(_ blocks: [JSONValue]) -> String {
        var lines: [String] = []
        var previousWasList = false
        for (index, value) in blocks.enumerated() {
            guard let block = value.object else {
                continue
            }
            let type = block["_type"]?.string ?? ""
            if type == "block" {
                let isList = block["listItem"]?.string != nil
                if index > 0 && (!isList || !previousWasList) {
                    lines.append("")
                }
                lines.append(renderBlock(block))
                previousWasList = isList
            } else if type == "code", let code = block["code"]?.string, isPlainCode(block) {
                if index > 0 { lines.append("") }
                let language = block["language"]?.string ?? ""
                lines.append("```\(language)")
                lines.append(code)
                lines.append("```")
                previousWasList = false
            } else {
                if index > 0 { lines.append("") }
                lines.append(fence(block))
                previousWasList = false
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func fromMarkdown(_ markdown: String) -> [JSONValue] {
        var blocks: [JSONValue] = []
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if let fenced = opaque(line) {
                blocks.append(.object(fenced))
                index += 1
                continue
            }
            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count && !lines[index].hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                var object: [String: JSONValue] = [
                    "_type": .string("code"),
                    "_key": .string(key()),
                    "code": .string(code.joined(separator: "\n")),
                ]
                if !language.isEmpty {
                    object["language"] = .string(language)
                }
                blocks.append(.object(object))
                if index < lines.count { index += 1 }
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }
            if let match = line.wholeMatch(of: headingPattern) {
                blocks.append(block(String(match.output.2), style: "h\(match.output.1.count)"))
                index += 1
                continue
            }
            if line.hasPrefix("> ") {
                blocks.append(block(String(line.dropFirst(2)), style: "blockquote"))
                index += 1
                continue
            }
            if let match = line.wholeMatch(of: bulletPattern) {
                let level = max(1, match.output.1.count / 2 + 1)
                blocks.append(listBlock(String(match.output.2), listItem: "bullet", level: level))
                index += 1
                continue
            }
            if let match = line.wholeMatch(of: numberPattern) {
                let level = max(1, match.output.1.count / 2 + 1)
                blocks.append(listBlock(String(match.output.2), listItem: "number", level: level))
                index += 1
                continue
            }
            blocks.append(block(line, style: "normal"))
            index += 1
        }
        return blocks
    }

    private static let headingPattern = /^(#{1,6})\s+(.+)$/
    private static let bulletPattern = /^(\s*)[-*+]\s+(.+)$/
    private static let numberPattern = /^(\s*)\d+\.\s+(.+)$/
    private static let fencePattern = /^<!--ec:block (.+) -->$/

    private static func isPlainCode(_ block: [String: JSONValue]) -> Bool {
        let allowed: Set<String> = ["_type", "_key", "code", "language"]
        return block.keys.allSatisfy(allowed.contains)
    }

    private static func fence(_ block: [String: JSONValue]) -> String {
        let data = (try? JSONValue.object(block).data()) ?? Data("{}".utf8)
        let json = String(decoding: data, as: UTF8.self)
        return "<!--ec:block \(json) -->"
    }

    private static func opaque(_ line: String) -> [String: JSONValue]? {
        guard let match = line.wholeMatch(of: fencePattern) else { return nil }
        guard let data = String(match.output.1).data(using: .utf8),
              let value = try? JSONDecoding.value(from: data),
              let object = value.object
        else { return nil }
        return object
    }

    private static func renderBlock(_ block: [String: JSONValue]) -> String {
        let text = renderSpans(block["children"]?.array ?? [], markDefs: block["markDefs"]?.array ?? [])
        if let listItem = block["listItem"]?.string {
            let level = Int(block["level"]?.number ?? 1)
            let indent = String(repeating: "  ", count: max(0, level - 1))
            let marker = listItem == "number" ? "1." : "-"
            return "\(indent)\(marker) \(text)"
        }
        if let style = block["style"]?.string, style.hasPrefix("h"), let level = Int(style.dropFirst()), (1...6).contains(level) {
            return String(repeating: "#", count: level) + " " + text
        }
        if block["style"]?.string == "blockquote" {
            return "> \(text)"
        }
        return text
    }

    private static func renderSpans(_ spans: [JSONValue], markDefs: [JSONValue]) -> String {
        var result = ""
        for value in spans {
            guard let span = value.object, span["_type"]?.string == "span" else { continue }
            var text = span["text"]?.string ?? ""
            let marks = span["marks"]?.array?.compactMap(\.string) ?? []
            for mark in marks {
                if let definition = markDefs.compactMap(\.object).first(where: { $0["_key"]?.string == mark }) {
                    if definition["_type"]?.string == "link" {
                        text = "[\(text)](\(definition["href"]?.string ?? ""))"
                    }
                } else {
                    switch mark {
                    case "strong":
                        text = "**\(text)**"
                    case "em":
                        text = "_\(text)_"
                    case "code":
                        text = "`\(text)`"
                    case "strike-through", "strikethrough":
                        text = "~~\(text)~~"
                    default:
                        break
                    }
                }
            }
            result += text
        }
        return result
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

    private static func listBlock(_ text: String, listItem: String, level: Int) -> JSONValue {
        let inline = parseInline(text)
        return .object([
            "_type": .string("block"),
            "_key": .string(key()),
            "style": .string("normal"),
            "listItem": .string(listItem),
            "level": .number(Double(level)),
            "markDefs": .array(inline.markDefs),
            "children": .array(inline.spans),
        ])
    }

    private static func parseInline(_ text: String) -> (spans: [JSONValue], markDefs: [JSONValue]) {
        guard let regex = try? NSRegularExpression(
            pattern: #"(\*\*(.+?)\*\*)|(_(.+?)_)|(`(.+?)`)|(\[(.+?)\]\((.+?)\))|(~~(.+?)~~)"#
        ) else {
            return ([span(text, marks: [])], [])
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty {
            return ([span(text, marks: [])], [])
        }
        var spans: [JSONValue] = []
        var markDefs: [JSONValue] = []
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                spans.append(span(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), marks: []))
            }
            if match.range(at: 2).location != NSNotFound {
                spans.append(span(ns.substring(with: match.range(at: 2)), marks: ["strong"]))
            } else if match.range(at: 4).location != NSNotFound {
                spans.append(span(ns.substring(with: match.range(at: 4)), marks: ["em"]))
            } else if match.range(at: 6).location != NSNotFound {
                spans.append(span(ns.substring(with: match.range(at: 6)), marks: ["code"]))
            } else if match.range(at: 8).location != NSNotFound && match.range(at: 9).location != NSNotFound {
                let mark = key()
                markDefs.append(.object([
                    "_key": .string(mark),
                    "_type": .string("link"),
                    "href": .string(ns.substring(with: match.range(at: 9))),
                ]))
                spans.append(span(ns.substring(with: match.range(at: 8)), marks: [mark]))
            } else if match.range(at: 11).location != NSNotFound {
                spans.append(span(ns.substring(with: match.range(at: 11)), marks: ["strike-through"]))
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            spans.append(span(ns.substring(from: cursor), marks: []))
        }
        if spans.isEmpty {
            spans.append(span(text, marks: []))
        }
        return (spans, markDefs)
    }

    private static func span(_ text: String, marks: [String]) -> JSONValue {
        .object([
            "_type": .string("span"),
            "_key": .string(key()),
            "text": .string(text),
            "marks": .array(marks.map { .string($0) }),
        ])
    }

    private static func key() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }
}

enum WriterText {
    static func wordCount(title: String, body: String) -> Int {
        let source = title + "\n" + body
        return source.split { $0.isWhitespace || $0.isNewline }.count
    }

    static func editorBody(_ markdown: String) -> String {
        var text = markdown
        while text.hasSuffix("\n") {
            text.removeLast()
        }
        return text
    }
}
