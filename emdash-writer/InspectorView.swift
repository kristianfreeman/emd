import SwiftUI

struct GutterCopy: Equatable {
    var headline = ""
    var terms: [TermGroup] = []
    var words = ""
    var slug = ""
    var excerpt = ""

    static let empty = GutterCopy()

    init() {}

    @MainActor init(_ document: EditorDocument) {
        headline = gutterHeadline(document)
        terms = document.termGroups.filter { !$0.value.isEmpty }
        words = gutterWords(document)
        slug = document.slug
        excerpt = document.excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct PropertiesText: View {
    var copy: GutterCopy

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(copy.headline)
            ForEach(copy.terms) { term in
                Text(term.value)
            }
            Text(copy.words)
            if !copy.slug.isEmpty {
                Text(copy.slug)
            }
            if !copy.excerpt.isEmpty {
                Text(copy.excerpt)
                    .lineLimit(4)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.leading)
        .frame(width: 200, alignment: .topLeading)
        .padding(.trailing, 8)
        .fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor private func gutterHeadline(_ document: EditorDocument) -> String {
    switch document.status {
    case "published":
        return document.publishedLabel
    case "scheduled":
        return "Scheduled"
    default:
        return "Draft"
    }
}

@MainActor private func gutterWords(_ document: EditorDocument) -> String {
    let words = WriterText.wordCount(title: document.title, body: document.body)
    guard words > 0 else { return "Empty" }
    let minutes = max(1, Int((Double(words) / 220.0).rounded(.up)))
    return words < 40 ? "\(words) words" : "\(words) words · \(minutes) min"
}
