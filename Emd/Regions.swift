import Foundation

/// An entry with more than one Portable Text field, like a page's `aside` and `main`, is written as one text:
/// each region starts with a marker line, `<!--emd:region main-->`, that the editor draws as a labeled divider
/// and will not delete. Saving splits the text at the markers, so each field gets its own Portable Text.
enum Regions {
    static let pattern = /^<!--emd:region ([A-Za-z0-9_-]+)-->$/

    static func marker(_ slug: String) -> String {
        "<!--emd:region \(slug)-->"
    }

    /// The field a marker line starts, or nil for any other line.
    static func slug(_ line: String) -> String? {
        guard line.hasPrefix("<!--emd:region "), let match = line.wholeMatch(of: pattern) else { return nil }
        return String(match.output.1)
    }

    /// The regions, in field order, each under its marker.
    static func joined(_ texts: [(slug: String, markdown: String)]) -> String {
        texts.map { region in
            let body = WriterText.editorBody(region.markdown)
            return body.isEmpty ? marker(region.slug) : "\(marker(region.slug))\n\n\(body)"
        }.joined(separator: "\n\n")
    }

    /// Each region's Markdown, by field. Text before the first marker belongs to the first region; a region
    /// whose marker is missing comes back empty, so saving never drops a field's text into another.
    static func split(_ text: String, slugs: [String]) -> [String: String] {
        var current = slugs.first ?? ""
        let owned = text.split(separator: "\n", omittingEmptySubsequences: false).compactMap {
            part -> (String, String)? in
            let line = String(part)
            let starts = slug(line).flatMap { slugs.contains($0) ? $0 : nil }
            current = starts ?? current
            return starts == nil ? (current, line) : nil
        }
        let regions = Dictionary(grouping: owned, by: \.0).mapValues { $0.map(\.1) }
        return Dictionary(uniqueKeysWithValues: slugs.map { ($0, trimmed(regions[$0] ?? [])) })
    }

    private static func trimmed(_ lines: [String]) -> String {
        let text = lines.joined(separator: "\n")
        return WriterText.editorBody(text.drop { $0 == "\n" }.description)
    }
}

extension CollectionDef {
    /// The Portable Text fields an entry is written in, when it has more than one. A post has one body field,
    /// and an empty list here.
    var regionFields: [FieldDef] {
        let fields = self.fields.filter { $0.type == "portableText" }.sorted { $0.sortOrder < $1.sortOrder }
        return fields.count > 1 ? fields : []
    }
}
