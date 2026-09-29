import SwiftUI

struct PropertiesText: View {
    var document: EditorDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headline)
            if document.remoteID != nil {
                ForEach(document.termGroups) { group in
                    if !group.value.isEmpty {
                        Text(group.value)
                    }
                }
            }
            Text(wordLine)
            if !document.slug.isEmpty {
                Text(document.slug)
            }
            if !document.excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(document.excerpt)
                    .lineLimit(4)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headline: String {
        switch document.status {
        case "published":
            return document.publishedLabel
        case "scheduled":
            return "Scheduled"
        default:
            return "Draft"
        }
    }

    private var wordLine: String {
        let words = WriterText.wordCount(title: document.title, body: document.body)
        if words == 0 { return "Empty" }
        let minutes = max(1, Int((Double(words) / 220.0).rounded(.up)))
        return words < 40 ? "\(words) words" : "\(words) words · \(minutes) min"
    }
}
