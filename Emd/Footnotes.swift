import Foundation

/// Markdown footnotes, `[^1]` in the text and `[^1]: The note.` on a line of its own.
///
/// Portable Text has no footnote, and a mark EmDash does not know breaks its admin editor, so a note is written
/// with what every EmDash site already draws: a reference is a superscript label linked to `#fn-1`, and a run of
/// notes is one `htmlBlock`, a rule and a paragraph per note with that id. Each paragraph keeps its Markdown in
/// `data-markdown`, so the block reads back as the lines that made it.
enum Footnotes {
    static let definitionPattern = /^\[\^([\p{L}\p{N}_-]+)\]:[ \t]?(.*)$/
    static let referencePrefix = "#fn-"

    static func anchor(_ label: String) -> String {
        referencePrefix + label
    }

    /// The label and text of a note line.
    static func definition(_ line: String) -> (label: String, text: String)? {
        guard let match = line.wholeMatch(of: definitionPattern) else { return nil }
        return (String(match.output.1), String(match.output.2))
    }

    /// Note lines from `index`, with blank lines between them, and the index after the last.
    static func run(_ lines: [String], from index: Int) -> (notes: [(label: String, text: String)], next: Int) {
        let span = lines[index...].prefix { isBlank($0) || definition($0) != nil }
        let last = span.lastIndex { definition($0) != nil } ?? index - 1
        return (span.compactMap(definition), last + 1)
    }

    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func block(_ notes: [(label: String, text: String)]) -> [String: JSONValue] {
        [
            "_type": .string("htmlBlock"),
            "_key": .string(PortableText.key()),
            "html": .string(html(notes)),
        ]
    }

    static func html(_ notes: [(label: String, text: String)]) -> String {
        let paragraphs = notes.map { note in
            "<p class=\"footnote\" id=\"fn-\(note.label)\" data-markdown=\"\(escaped(note.text))\">"
                + "<sup>\(escaped(note.label))</sup> \(inlineHTML(note.text))</p>"
        }
        return "<section class=\"footnotes\"><hr>" + paragraphs.joined() + "</section>"
    }

    /// The note lines a footnotes block was written from, when writing them again gives the same block.
    static func lines(_ block: [String: JSONValue]) -> [String]? {
        guard block["_type"]?.string == "htmlBlock", let html = block["html"]?.string,
            Set(block.keys).isSubset(of: ["_type", "_key", "html"]), html.hasPrefix("<section class=\"footnotes\">")
        else { return nil }
        let notes = html.matches(of: notePattern).map { (String($0.output.1), unescaped(String($0.output.2))) }
        guard !notes.isEmpty, Self.html(notes) == html else { return nil }
        return notes.map { "[^\($0.0)]: \($0.1)" }
    }

    private static let notePattern = /<p class="footnote" id="fn-([^"]*)" data-markdown="([^"]*)">/

    // MARK: HTML

    /// A note's Markdown as HTML: the same inline parse a paragraph gets, then a tag per mark.
    static func inlineHTML(_ markdown: String) -> String {
        let inline = PortableText.parseInline(markdown)
        let links = Dictionary(
            inline.markDefs.compactMap(\.object).compactMap { def -> (String, String)? in
                guard let key = def["_key"]?.string, let href = def["href"]?.string else { return nil }
                return (key, href)
            }
        ) { first, _ in first }
        return inline.spans.compactMap(\.object).map { span in
            let text = escaped(span["text"]?.string ?? "")
            let marks = span["marks"]?.array?.compactMap(\.string) ?? []
            return marks.reversed().reduce(text) { inner, mark in tagged(inner, mark: mark, links: links) }
        }.joined()
    }

    private static func tagged(_ inner: String, mark: String, links: [String: String]) -> String {
        if let href = links[mark] { return "<a href=\"\(escaped(href))\">\(inner)</a>" }
        let tags = ["strong": "strong", "em": "em", "code": "code", "strike-through": "s", "superscript": "sup"]
        guard let tag = tags[mark] else { return inner }
        return "<\(tag)>\(inner)</\(tag)>"
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func unescaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
