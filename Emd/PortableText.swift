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
        ImageLine(url: media.url, alt: alt, width: media.width, height: media.height).markdown
    }

    static func key() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }
}

enum WriterText {
    static func wordCount(title: String, body: String) -> Int {
        words(in: title) + readableWords(in: body)
    }

    /// Words a reader sees: no pictures, code, fenced blocks, link targets, or list and heading markers.
    static func readableWords(in markdown: String) -> Int {
        var count = 0
        var inCode = false
        markdown.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let fence = trimmed.hasPrefix("```")
            inCode = inCode != fence
            guard !fence, !inCode, !trimmed.hasPrefix("!["), !trimmed.hasPrefix("<!--") else { return }
            count += words(in: prose(line))
        }
        return count
    }

    private static let linkTarget = try? NSRegularExpression(pattern: #"\]\([^)\s]*\)"#)
    private static let lineMarker = try? NSRegularExpression(pattern: #"^\s*(?:[-*+]|\d+[.)]|#{1,6}|>)\s+"#)
    private static let footnoteLabel = try? NSRegularExpression(pattern: #"\[\^[\p{L}\p{N}_-]+\]:?"#)

    private static func prose(_ line: String) -> String {
        [lineMarker, linkTarget, footnoteLabel].compactMap { $0 }.reduce(line) { text, expression in
            let range = NSRange(location: 0, length: (text as NSString).length)
            return expression.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
        }
    }

    /// A UTF-16 scan: a word is a run without spaces that holds a letter or a digit, so `**`, `-`, and `—`
    /// alone are not words. Splitting a long post into Characters took milliseconds.
    static func words(in text: String) -> Int {
        var count = 0
        var counted = false
        for unit in text.utf16 {
            let space = unit == 0x20 || unit == 0x0A || unit == 0x09 || unit == 0x0D || unit == 0xA0 || unit == 0x2028
            let wordy = !space && isWordy(unit)
            count += wordy && !counted ? 1 : 0
            counted = !space && (counted || wordy)
        }
        return count
    }

    private static func isWordy(_ unit: UInt16) -> Bool {
        if unit < 0x80 {
            return (0x30...0x39).contains(unit) || (0x41...0x5A).contains(unit) || (0x61...0x7A).contains(unit)
        }
        guard let scalar = Unicode.Scalar(unit) else { return true }
        return CharacterSet.alphanumerics.contains(scalar)
    }

    static func editorBody(_ markdown: String) -> String {
        var text = markdown
        while text.hasSuffix("\n") {
            text.removeLast()
        }
        return text
    }
}
