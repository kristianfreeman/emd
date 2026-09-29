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

    static let uploadingScheme = "uploading:"
    static let mediaPrefix = "/_emdash/api/media/file/"

    /// The library id inside a site media URL. The stored file is named for it: `01HXK….jpg`.
    static func mediaID(_ url: String) -> String? {
        guard url.hasPrefix(mediaPrefix) else { return nil }
        let file = url.dropFirst(mediaPrefix.count)
        guard !file.isEmpty, !file.contains("/") else { return nil }
        return String(file.prefix { $0 != "." })
    }

    static func imageLine(media: UploadedMedia, alt: String) -> String {
        let size = media.width.flatMap { width in media.height.map { " =\(width)x\($0)" } } ?? ""
        return "![\(alt)](\(media.url)\(size))"
    }

    static func key() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }
}

enum WriterText {
    /// A UTF-16 scan. Splitting a long post into Characters took milliseconds.
    static func wordCount(title: String, body: String) -> Int {
        words(in: title) + words(in: body)
    }

    private static func words(in text: String) -> Int {
        var count = 0
        var inWord = false
        for unit in text.utf16 {
            let space = unit == 0x20 || unit == 0x0A || unit == 0x09 || unit == 0x0D || unit == 0xA0 || unit == 0x2028
            count += !space && !inWord ? 1 : 0
            inWord = !space
        }
        return count
    }

    static func editorBody(_ markdown: String) -> String {
        var text = markdown
        while text.hasSuffix("\n") {
            text.removeLast()
        }
        return text
    }
}
