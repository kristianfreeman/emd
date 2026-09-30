import Foundation

/// A picture line: `![alt](url =1200x800 "A caption"){wide}`. Size, caption, and alignment are optional.
/// It is the one grammar for pictures: reading from EmDash, writing back, and drawing in the editor.
struct ImageLine: Equatable {
    var alt = ""
    var url: String
    var width: Int?
    var height: Int?
    var caption = ""
    /// EmDash's `alignment`: left, center, right, wide, or full. Empty is the site's default.
    var alignment = ""

    static let alignments = ["left", "center", "right", "wide", "full"]

    private static let pattern =
        /^!\[([^\]\n]*)\]\(([^)\s]+)(?:\s+=(\d+)x(\d+))?(?:\s+"((?:[^"\\\n]|\\.)*)")?\)(?:\{(left|center|right|wide|full)\})?$/

    init(url: String, alt: String = "", width: Int? = nil, height: Int? = nil) {
        self.url = url
        self.alt = alt
        self.width = width
        self.height = height
    }

    init?(_ line: String) {
        guard let match = line.wholeMatch(of: Self.pattern) else { return nil }
        alt = String(match.output.1)
        url = String(match.output.2)
        width = match.output.3.flatMap { Int($0) }
        height = match.output.4.flatMap { Int($0) }
        caption = match.output.5.map { Self.unescaped(String($0)) } ?? ""
        alignment = match.output.6.map(String.init) ?? ""
    }

    var markdown: String {
        var line = "![\(alt)](\(url)"
        if let width, let height { line += " =\(width)x\(height)" }
        if !caption.isEmpty { line += " \"\(Self.escaped(caption))\"" }
        line += ")"
        return alignment.isEmpty ? line : line + "{\(alignment)}"
    }

    // MARK: Portable Text

    /// The image block, without a `_key`. A site media URL carries its library id as `asset._ref`.
    var block: [String: JSONValue] {
        var asset: [String: JSONValue] = ["url": .string(url)]
        if let id = PortableText.mediaID(url) { asset["_ref"] = .string(id) }
        var object: [String: JSONValue] = ["_type": .string("image"), "asset": .object(asset)]
        if !alt.isEmpty { object["alt"] = .string(alt) }
        if let width, let height {
            object["width"] = .number(Double(width))
            object["height"] = .number(Double(height))
        }
        if !caption.isEmpty { object["caption"] = .string(caption) }
        if !alignment.isEmpty { object["alignment"] = .string(alignment) }
        return object
    }

    /// The line for an image block, when every part of the block fits one. Anything else stays fenced.
    init?(block: [String: JSONValue]) {
        let allowed: Set<String> = ["_type", "_key", "alt", "asset", "width", "height", "caption", "alignment"]
        guard Set(block.keys).isSubset(of: allowed), let url = Self.plainURL(block["asset"]) else { return nil }
        guard let size = Self.plainSize(block) else { return nil }
        self.url = url
        (width, height) = size
        guard let alt = Self.plainText(block["alt"], forbidding: "]"),
            let caption = Self.plainText(block["caption"], forbidding: nil),
            let alignment = Self.plainText(block["alignment"], forbidding: nil),
            alignment.isEmpty || Self.alignments.contains(alignment)
        else { return nil }
        self.alt = alt
        self.caption = caption
        self.alignment = alignment
    }

    private static func plainURL(_ asset: JSONValue?) -> String? {
        guard let object = asset?.object, Set(object.keys).isSubset(of: ["url", "_ref"]) else { return nil }
        guard let url = object["url"]?.string, !url.isEmpty, !url.contains(where: { ")\n ".contains($0) }) else {
            return nil
        }
        return url
    }

    private static func plainSize(_ block: [String: JSONValue]) -> (Int?, Int?)? {
        let width = block["width"]?.number
        let height = block["height"]?.number
        if width == nil && height == nil { return (nil, nil) }
        guard let width, let height, width == width.rounded(), height == height.rounded() else { return nil }
        return (Int(width), Int(height))
    }

    /// Missing is empty. A value must be a single line of text without `forbidden`.
    private static func plainText(_ value: JSONValue?, forbidding forbidden: Character?) -> String? {
        guard let value else { return "" }
        guard let text = value.string, !text.contains("\n") else { return nil }
        if let forbidden, text.contains(forbidden) { return nil }
        return text
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func unescaped(_ text: String) -> String {
        var result = ""
        var escaping = false
        for character in text {
            result += escaping || character != "\\" ? String(character) : ""
            escaping = !escaping && character == "\\"
        }
        return result
    }
}
