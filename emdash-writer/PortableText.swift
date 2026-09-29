import Foundation

enum PortableText {
    static func markdownData(from data: [String: JSONValue], fields: [FieldDef]) -> [String: JSONValue] {
        var copy = data
        for field in fields where field.type == "portableText" {
            copy[field.slug] = markdownValue(copy[field.slug])
        }
        return copy
    }

    static func portableData(from data: [String: JSONValue], fields: [FieldDef]) -> [String: JSONValue] {
        var copy = data
        for field in fields where field.type == "portableText" {
            copy[field.slug] = portableValue(copy[field.slug])
        }
        return copy
    }

    static func markdownValue(_ value: JSONValue?) -> JSONValue? {
        guard let blocks = value?.array else { return value }
        return .string(toMarkdown(blocks))
    }

    static func portableValue(_ value: JSONValue?) -> JSONValue? {
        guard let markdown = value?.string else { return value }
        return .array(fromMarkdown(markdown))
    }

    static func span(_ text: String, marks: [String]) -> JSONValue {
        .object([
            "_type": .string("span"),
            "_key": .string(key()),
            "text": .string(text),
            "marks": .array(marks.map { .string($0) }),
        ])
    }

    static func key() -> String {
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
