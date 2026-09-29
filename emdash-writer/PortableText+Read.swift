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
    private static let imagePattern = /^!\[([^\]]*)\]\(([^)]+)\)$/

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

    private static func imageBlock(_ line: String) -> JSONValue? {
        guard let match = line.wholeMatch(of: imagePattern) else { return nil }
        return .object([
            "_type": .string("image"),
            "_key": .string(key()),
            "alt": .string(String(match.output.1)),
            "asset": .object(["url": .string(String(match.output.2))]),
        ])
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

    private static func parseInline(_ text: String) -> (spans: [JSONValue], markDefs: [JSONValue]) {
        guard let regex = inlinePattern() else { return ([span(text, marks: [])], []) }
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        guard !matches.isEmpty else { return ([span(text, marks: [])], []) }
        return filled(walk(matches, in: text as NSString), fallback: text)
    }

    private static func inlinePattern() -> NSRegularExpression? {
        try? NSRegularExpression(
            pattern: #"(\*\*(.+?)\*\*)|(_(.+?)_)|(`(.+?)`)|(\[(.+?)\]\((.+?)\))|(~~(.+?)~~)"#
        )
    }

    private struct InlineBuild {
        var spans: [JSONValue] = []
        var markDefs: [JSONValue] = []
        var cursor = 0
    }

    private static func walk(_ matches: [NSTextCheckingResult], in ns: NSString) -> InlineBuild {
        var build = InlineBuild()
        for match in matches {
            appendMatch(match, ns: ns, build: &build)
        }
        return build
    }

    private static func appendMatch(_ match: NSTextCheckingResult, ns: NSString, build: inout InlineBuild) {
        appendGap(ns, from: build.cursor, to: match.range.location, spans: &build.spans)
        appendMarked(Capture(match: match, ns: ns), build: &build)
        build.cursor = match.range.location + match.range.length
    }

    private static func appendGap(_ ns: NSString, from cursor: Int, to location: Int, spans: inout [JSONValue]) {
        guard location > cursor else { return }
        spans.append(span(ns.substring(with: NSRange(location: cursor, length: location - cursor)), marks: []))
    }

    private struct Capture {
        var match: NSTextCheckingResult
        var ns: NSString
    }

    private static func appendMarked(_ capture: Capture, build: inout InlineBuild) {
        if appendCapture(capture, group: 2, mark: "strong", spans: &build.spans) { return }
        if appendCapture(capture, group: 4, mark: "em", spans: &build.spans) { return }
        if appendCapture(capture, group: 6, mark: "code", spans: &build.spans) { return }
        if appendLink(capture, build: &build) { return }
        _ = appendCapture(capture, group: 11, mark: "strike-through", spans: &build.spans)
    }

    private static func appendCapture(_ capture: Capture, group: Int, mark: String, spans: inout [JSONValue]) -> Bool {
        guard capture.match.range(at: group).location != NSNotFound else { return false }
        spans.append(span(capture.ns.substring(with: capture.match.range(at: group)), marks: [mark]))
        return true
    }

    private static func appendLink(_ capture: Capture, build: inout InlineBuild) -> Bool {
        let label = capture.match.range(at: 8)
        let href = capture.match.range(at: 9)
        guard label.location != NSNotFound, href.location != NSNotFound else { return false }
        let mark = key()
        build.markDefs.append(linkDef(mark, href: capture.ns.substring(with: href)))
        build.spans.append(span(capture.ns.substring(with: label), marks: [mark]))
        return true
    }

    private static func linkDef(_ mark: String, href: String) -> JSONValue {
        .object([
            "_key": .string(mark),
            "_type": .string("link"),
            "href": .string(href),
        ])
    }

    private static func filled(_ walked: InlineBuild, fallback: String) -> (spans: [JSONValue], markDefs: [JSONValue]) {
        var spans = walked.spans
        let ns = fallback as NSString
        if walked.cursor < ns.length {
            spans.append(span(ns.substring(from: walked.cursor), marks: []))
        }
        if spans.isEmpty {
            spans.append(span(fallback, marks: []))
        }
        return (spans, walked.markDefs)
    }
}
