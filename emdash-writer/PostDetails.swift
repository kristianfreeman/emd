import SwiftUI

/// Title, slug, and excerpt: the parts of a post that are not its text. They save like any edit.
struct PostDetails: View {
    var model: AppModel
    @Bindable var document: EditorDocument
    var hasExcerpt: Bool

    var body: some View {
        Form {
            TextField("Title", text: $document.title, prompt: Text("Untitled"))
            slugRow
            if hasExcerpt { excerptRow }
            ForEach(model.applicableTaxonomies) { taxonomy in
                TermsSection(model: model, taxonomy: taxonomy, document: document)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .task { await model.loadTaxonomyTerms() }
    }

    @ViewBuilder
    private var slugRow: some View {
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
    }

    private var excerptRow: some View {
        LabeledContent("Excerpt") {
            TextEditor(text: $document.excerpt)
                .font(.body)
                .frame(minHeight: 80, maxHeight: 140)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    /// Typing in the slug keeps it a slug.
    private var slug: Binding<String> {
        Binding(get: { document.slug }, set: { document.slug = Slug.cleaned($0) })
    }
}

/// One taxonomy's terms on this post: chips to remove, a field to add or make one, a menu of the rest.
private struct TermsSection: View {
    var model: AppModel
    var taxonomy: TaxonomyInfo
    var document: EditorDocument
    @State private var typed = ""
    @State private var working = false

    var body: some View {
        Section {
            if document.remoteID == nil {
                Text("Save the post once to add \(taxonomy.label.lowercased()).")
                    .foregroundStyle(.secondary)
            } else if !document.termsLoaded {
                Text("Loading \(taxonomy.label.lowercased())…")
                    .foregroundStyle(.secondary)
                    .task { await model.refreshTerms(for: document) }
            } else {
                chips
                adder
            }
        } header: {
            Text(taxonomy.label)
        } footer: {
            Text("\(taxonomy.label) save to the site right away, outside the draft.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var assigned: [TermLabel] { model.assigned(taxonomy, in: document) }

    @ViewBuilder
    private var chips: some View {
        if !assigned.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(assigned) { term in chip(term) }
                }
            }
        }
    }

    private func chip(_ term: TermLabel) -> some View {
        HStack(spacing: 4) {
            Text(term.label)
            Button {
                run { await model.unassign(term, in: taxonomy, from: document) }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(term.label)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
    }

    private var adder: some View {
        HStack(spacing: 6) {
            TextField("Add", text: $typed, prompt: Text("Add \(taxonomy.labelSingularOrLabel.lowercased())"))
                .labelsHidden()
                .onSubmit(add)
            Menu {
                ForEach(available) { term in
                    Button(term.label) { run { await model.assign(term, in: taxonomy, to: document) } }
                }
            } label: {
                Image(systemName: "list.bullet")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(available.isEmpty)
            .help("Choose from existing \(taxonomy.label.lowercased())")
            if working { ProgressView().controlSize(.small) }
        }
        .disabled(working)
    }

    private var available: [TermLabel] {
        let taken = Set(assigned.map(\.id))
        return (model.taxonomyTerms[taxonomy.name] ?? []).filter { !taken.contains($0.id) }
    }

    private func add() {
        let label = typed
        typed = ""
        run { await model.assign(label, in: taxonomy, to: document) }
    }

    private func run(_ work: @escaping () async -> Void) {
        working = true
        Task {
            await work()
            working = false
        }
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

/// When to publish. The site rejects a time that has passed; the picker starts an hour out.
struct SchedulePicker: View {
    let schedule: (Date) -> Void
    @State private var date = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("Publish on", selection: $date, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .labelsHidden()
            HStack {
                Text(date.formatted(date: .complete, time: .shortened))
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Spacer()
                Button("Schedule") { schedule(date) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(date <= .now)
            }
        }
        .padding(14)
        .frame(width: 340)
    }
}
