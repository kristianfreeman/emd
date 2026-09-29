import SwiftUI

/// Title, slug, and excerpt: the parts of a post that are not its text. They save like any edit.
struct PostDetails: View {
    @Bindable var document: EditorDocument
    var hasExcerpt: Bool

    var body: some View {
        Form {
            TextField("Title", text: $document.title, prompt: Text("Untitled"))
            LabeledContent("Slug") {
                HStack(spacing: 6) {
                    TextField("Slug", text: slug, prompt: Text(Slug.from(document.title).nonEmpty ?? "post-slug"))
                        .labelsHidden()
                    Button("From Title") { document.slug = Slug.from(document.title) }
                        .controlSize(.small)
                        .disabled(Slug.from(document.title).isEmpty)
                }
            }
            if document.status == "published" && !document.slug.isEmpty {
                Text("This post is published. A new slug gives it a new address.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if hasExcerpt {
                LabeledContent("Excerpt") {
                    TextEditor(text: $document.excerpt)
                        .font(.body)
                        .frame(minHeight: 80, maxHeight: 140)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Typing in the slug keeps it a slug.
    private var slug: Binding<String> {
        Binding(get: { document.slug }, set: { document.slug = Slug.cleaned($0) })
    }
}

enum Slug {
    /// `Hello, World!` → `hello-world`. Letters and digits from any script stay; everything else becomes a dash.
    static func from(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        let dashed = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }.joined()
        return dashed.split(separator: "-").joined(separator: "-")
    }

    /// While typing: lowercase, dashes for anything else, and no doubled dashes. A trailing dash may stay.
    static func cleaned(_ typed: String) -> String {
        let lowered = typed.lowercased().unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? String($0) : "-"
        }.joined()
        var result = ""
        for character in lowered where !(character == "-" && (result.isEmpty || result.hasSuffix("-"))) {
            result.append(character)
        }
        return result
    }
}

extension String {
    fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}
