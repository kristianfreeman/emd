import SwiftUI

/// Help › Emd Help: the keys, and the Markdown Emd reads and writes back to EmDash.
struct HelpView: View {
    private let keys: [(String, String)] = [
        ("⌘N", "New post"),
        ("⌘S", "Save now (Emd also saves as you pause)"),
        ("⇧⌘P", "Publish, or publish changes"),
        ("⌥⌘P", "Preview the latest draft in the browser"),
        ("⇧⌘I", "Insert image (or drop or paste one into the text)"),
        ("⌃⌘I", "Post details: title, slug, excerpt"),
        ("⌥⌘F", "Search posts"),
        ("⌘F", "Find in this post"),
        ("⌘B  ⌘I  ⌘K", "Bold, italic, link"),
        ("⇧⌘F", "Focus"),
        ("⇧⌘T", "Typewriter"),
        ("⌘+  ⌘−  ⌘0", "Text size"),
        ("⌘R", "Reload from site"),
        ("Return / Tab", "From the list, start writing in the open post"),
        ("Esc", "From the post, back to the list"),
    ]

    private let markdown: [(String, String)] = [
        ("# Heading", "Headings, # to ######"),
        ("**bold**  __bold__", "Strong"),
        ("*italic*  _italic_", "Emphasis"),
        ("`code`", "Inline code"),
        ("[text](https://…)", "Link"),
        ("~~struck~~", "Strikethrough"),
        ("- item  1. item", "Lists; Tab nests, Return continues"),
        ("> quote", "Quote"),
        ("```swift", "Code block, closed by ```"),
        ("![alt](url =1200x800 \"caption\"){wide}", "Picture; double-click it for alt text, caption, alignment"),
        ("\\*", "A backslash keeps a marker literal"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section("Keys", rows: keys)
                section("Markdown", rows: markdown)
                Text(
                    "Blocks Emd does not edit, like embeds or pictures with captions, stay as `<!--ec:block … -->` lines, "
                        + "so saving never changes them."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(width: 520, height: 560)
    }

    private func section(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                ForEach(rows, id: \.0) { row in
                    GridRow {
                        Text(row.0)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                        Text(row.1)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct HelpCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Emd Help") { openWindow(id: "help") }
            .keyboardShortcut("?", modifiers: .command)
    }
}
