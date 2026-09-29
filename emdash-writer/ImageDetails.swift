import AppKit
import SwiftUI

/// The popover a double-click on a picture opens: alt text, caption, and alignment, as EmDash stores them.
struct ImageDetails: View {
    let original: ImageLine
    let apply: (ImageLine) -> Void
    let editMarkdown: () -> Void
    let remove: () -> Void
    @State private var alt: String
    @State private var caption: String
    @State private var alignment: String
    @FocusState private var altFocused: Bool

    init(
        _ image: ImageLine, apply: @escaping (ImageLine) -> Void, editMarkdown: @escaping () -> Void,
        remove: @escaping () -> Void
    ) {
        original = image
        self.apply = apply
        self.editMarkdown = editMarkdown
        self.remove = remove
        _alt = State(initialValue: image.alt)
        _caption = State(initialValue: image.caption)
        _alignment = State(initialValue: image.alignment)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Form {
                TextField("Alt text", text: $alt, prompt: Text("Describe the picture"))
                    .focused($altFocused)
                TextField("Caption", text: $caption, prompt: Text("None"))
                Picker("Alignment", selection: $alignment) {
                    Text("Default").tag("")
                    ForEach(ImageLine.alignments, id: \.self) { Text($0.capitalized).tag($0) }
                }
            }
            .onSubmit(done)
            HStack {
                Button("Remove", role: .destructive, action: remove)
                Button("Edit Markdown", action: editMarkdown)
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380)
        .onAppear { altFocused = true }
    }

    private func done() {
        var image = original
        image.alt = alt.replacingOccurrences(of: "]", with: ")").replacingOccurrences(of: "\n", with: " ")
        image.caption = caption.replacingOccurrences(of: "\n", with: " ")
        image.alignment = alignment
        apply(image)
    }
}

/// ⌘K: a link's address, for the selection or for the link under the caret.
struct LinkEditor: View {
    let existing: Bool
    let apply: (String) -> Void
    let remove: () -> Void
    @State private var address: String
    @FocusState private var focused: Bool

    init(address: String, existing: Bool, apply: @escaping (String) -> Void, remove: @escaping () -> Void) {
        self.existing = existing
        self.apply = apply
        self.remove = remove
        _address = State(initialValue: address)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Address", text: $address, prompt: Text("https://…"))
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit {
                    guard !address.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    apply(address)
                }
            HStack {
                if existing {
                    Button("Remove Link", role: .destructive, action: remove)
                }
                Spacer()
                Button(existing ? "Update" : "Add Link") { apply(address) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { focused = true }
    }
}
