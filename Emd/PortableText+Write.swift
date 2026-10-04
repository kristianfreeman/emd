import Foundation

extension PortableText {
    static func toMarkdown(_ blocks: [JSONValue]) -> String {
        var lines: [String] = []
        var previousWasList = false
        for (index, value) in blocks.enumerated() {
            previousWasList = appendBlock(value, index: index, wasList: previousWasList, lines: &lines)
        }
        return renumbered(lines).joined(separator: "\n") + "\n"
    }

    /// Numbered items count up within a list, by level. Portable Text keeps no numbers, so reading ignores them.
    static func renumbered(_ lines: [String]) -> [String] {
        var counters: [Int: Int] = [:]
        var inFence = false
        return lines.map { line in
            if line.hasPrefix("```") { inFence.toggle() }
            guard !inFence, let item = line.wholeMatch(of: numberedItem) else {
                counters = inFence || line.wholeMatch(of: bulletItem) != nil ? counters : [:]
                return line
            }
            let level = item.output.1.count
            counters = counters.filter { $0.key <= level }
            counters[level, default: 0] += 1
            return "\(item.output.1)\(counters[level] ?? 1). \(item.output.2)"
        }
    }

    private static let numberedItem = /^( *)\d+\. (.*)$/
    private static let bulletItem = /^ *[-*+] .*$/

    private static func appendBlock(
        _ value: JSONValue,
        index: Int,
        wasList: Bool,
        lines: inout [String]
    ) -> Bool {
        guard let block = value.object else { return wasList }
        return appended(block, index: index, wasList: wasList, lines: &lines)
    }

    private static func appended(
        _ block: [String: JSONValue],
        index: Int,
        wasList: Bool,
        lines: inout [String]
    ) -> Bool {
        let type = block["_type"]?.string ?? ""
        if type == "block" {
            return appendText(block, index: index, wasList: wasList, lines: &lines)
        }
        if type == "code" {
            return appendCode(block, index: index, lines: &lines)
        }
        if type == "image" {
            return appendImage(block, index: index, lines: &lines)
        }
        if let notes = Footnotes.lines(block) {
            separate(&lines, index: index, when: true)
            lines += notes
            return false
        }
        return appendOpaque(block, index: index, lines: &lines)
    }

    private static func appendText(
        _ block: [String: JSONValue],
        index: Int,
        wasList: Bool,
        lines: inout [String]
    ) -> Bool {
        guard let line = faithfulLine(block, render: { renderBlock(block, escaping: $0) }) else {
            return appendOpaque(block, index: index, lines: &lines)
        }
        let isList = block["listItem"]?.string != nil
        separate(&lines, index: index, when: blankBeforeText(isList: isList, wasList: wasList))
        lines.append(line)
        return isList
    }

    private static func blankBeforeText(isList: Bool, wasList: Bool) -> Bool {
        !isList || !wasList
    }

    private static func appendCode(_ block: [String: JSONValue], index: Int, lines: inout [String]) -> Bool {
        guard let code = block["code"]?.string, isPlainCode(block) else {
            return appendOpaque(block, index: index, lines: &lines)
        }
        separate(&lines, index: index, when: true)
        lines.append("```\(block["language"]?.string ?? "")")
        lines.append(code)
        lines.append("```")
        return false
    }

    private static func appendImage(
        _ block: [String: JSONValue],
        index: Int,
        lines: inout [String]
    ) -> Bool {
        guard let line = imageLine(block) else {
            return appendOpaque(block, index: index, lines: &lines)
        }
        separate(&lines, index: index, when: true)
        lines.append(line)
        return false
    }

    /// A picture line, when it reads back as this exact block. Placeholders and providers stay fenced.
    private static func imageLine(_ block: [String: JSONValue]) -> String? {
        guard let image = ImageLine(block: block) else { return nil }
        let line = image.markdown
        return roundTrips(block, as: line) ? line : nil
    }

    private static func appendOpaque(_ block: [String: JSONValue], index: Int, lines: inout [String]) -> Bool {
        separate(&lines, index: index, when: true)
        lines.append(fence(block))
        return false
    }

    private static func separate(_ lines: inout [String], index: Int, when needed: Bool) {
        guard index > 0, needed else { return }
        lines.append("")
    }

    private static func isPlainCode(_ block: [String: JSONValue]) -> Bool {
        let allowed: Set<String> = ["_type", "_key", "code", "language"]
        return block.keys.allSatisfy(allowed.contains)
    }

    static func fence(_ block: [String: JSONValue]) -> String {
        let data = (try? JSONValue.object(block).data()) ?? Data("{}".utf8)
        let json = String(decoding: data, as: UTF8.self)
        return "<!--ec:block \(json) -->"
    }

    private static func renderBlock(_ block: [String: JSONValue], escaping: Bool) -> String {
        let spans = block["children"]?.array ?? []
        let text = renderSpans(spans, markDefs: block["markDefs"]?.array ?? [], escaping: escaping)
        if let line = listLine(block, text: text) { return line }
        if let line = headingLine(block, text: text) { return line }
        if block["style"]?.string == "blockquote" { return "> \(text)" }
        return text
    }

    private static func listLine(_ block: [String: JSONValue], text: String) -> String? {
        guard let listItem = block["listItem"]?.string else { return nil }
        let level = Int(block["level"]?.number ?? 1)
        let indent = String(repeating: "  ", count: max(0, level - 1))
        let marker = listItem == "number" ? "1." : "-"
        return "\(indent)\(marker) \(text)"
    }

    private static func headingLine(_ block: [String: JSONValue], text: String) -> String? {
        guard let style = block["style"]?.string, style.hasPrefix("h"), let level = Int(style.dropFirst()) else {
            return nil
        }
        guard (1...6).contains(level) else { return nil }
        return String(repeating: "#", count: level) + " " + text
    }

    private static func renderSpans(_ spans: [JSONValue], markDefs: [JSONValue], escaping: Bool) -> String {
        var result = ""
        for value in spans {
            result += renderedSpan(value, markDefs: markDefs, escaping: escaping)
        }
        return result
    }

    private static func renderedSpan(_ value: JSONValue, markDefs: [JSONValue], escaping: Bool) -> String {
        guard let span = value.object, span["_type"]?.string == "span" else { return "" }
        var marks = span["marks"]?.array?.compactMap(\.string) ?? []
        let text = span["text"]?.string ?? ""
        if let reference = footnoteMark(marks, text: text, markDefs: markDefs) {
            marks.removeAll { $0 == reference || $0 == "superscript" }
            return marks.reduce("[^\(text)]") { text, mark in apply(mark: mark, to: text, markDefs: markDefs) }
        }
        // Code keeps its characters as written; the parser does not look inside backticks.
        let body = escaping && !marks.contains("code") ? escaped(text) : text
        return marks.reduce(body) { text, mark in
            apply(mark: mark, to: text, markDefs: markDefs)
        }
    }

    /// The link mark that makes a superscript label a footnote reference: it points at `#fn-<label>`.
    private static func footnoteMark(_ marks: [String], text: String, markDefs: [JSONValue]) -> String? {
        guard marks.contains("superscript"), !marks.contains("code") else { return nil }
        return marks.first { mark in
            markDefs.compactMap(\.object).contains {
                $0["_key"]?.string == mark && $0["_type"]?.string == "link"
                    && $0["href"]?.string == Footnotes.anchor(text) && $0.count == 3
            }
        }
    }

    private static func apply(mark: String, to text: String, markDefs: [JSONValue]) -> String {
        guard let definition = markDefs.compactMap(\.object).first(where: { $0["_key"]?.string == mark }) else {
            return decoration(mark, text)
        }
        return linked(definition, text: text)
    }

    private static func linked(_ definition: [String: JSONValue], text: String) -> String {
        guard definition["_type"]?.string == "link" else { return text }
        return "[\(text)](\(definition["href"]?.string ?? ""))"
    }

    private static func decoration(_ mark: String, _ text: String) -> String {
        if mark == "strong" { return "**\(text)**" }
        if mark == "em" { return "_\(text)_" }
        if mark == "code" { return "`\(text)`" }
        return struck(mark, text)
    }

    private static func struck(_ mark: String, _ text: String) -> String {
        guard mark == "strike-through" || mark == "strikethrough" else { return text }
        return "~~\(text)~~"
    }
}
