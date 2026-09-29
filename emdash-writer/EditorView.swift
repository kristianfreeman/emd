import SwiftUI

struct EditorView: View {
    @Bindable var model: AppModel
    var palette: Palette

    var body: some View {
        writing
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.paper)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(heading)
            .navigationSubtitle(model.notice)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if let document = model.document, document.loaded {
                        StatusMarks(document: document, busy: model.busy) { live in
                            Task { await model.setLive(live) }
                        } discard: {
                            Task { await model.discardDraft() }
                        }
                    }
                }
            }
            .onChange(of: model.document?.body) { _, _ in model.scheduleAutosave() }
            .onChange(of: model.document?.title) { _, _ in model.scheduleAutosave() }
            .onChange(of: model.document?.excerpt) { _, _ in model.scheduleAutosave() }
            .onChange(of: model.document?.slug) { _, _ in model.scheduleAutosave() }
    }

    private var heading: String {
        let site = model.siteTitle.isEmpty ? "Em Dash Writer" : model.siteTitle
        guard let document = model.document else { return site }
        let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = title.isEmpty ? "Untitled" : title
        return "\(site) › \(name)"
    }

    @ViewBuilder
    private var writing: some View {
        if let document = model.document {
            loadedWriting(document)
        } else {
            Text("Choose a post, or start a new one.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func loadedWriting(_ document: EditorDocument) -> some View {
        if document.loaded {
            WritingColumn(
                title: Binding(get: { document.title }, set: { document.title = $0 }),
                bodyText: Binding(get: { document.body }, set: { document.body = $0 }),
                fontChoice: model.fontChoice,
                fontSize: CGFloat(model.fontSize),
                palette: palette,
                focusMode: model.focusMode,
                typewriter: model.typewriter,
                gutter: GutterCopy(document)
            )
            .id(document.localID)
        } else {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(document.title.isEmpty ? "Loading" : document.title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct StatusMarks: View {
    var document: EditorDocument
    var busy: Bool
    var setLive: (Bool) -> Void
    var discard: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            draftMark
            scheduledMark
            publishedMark
            waitingMark
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private var draftMark: some View {
        mark(systemName: "pencil", active: isDraft, help: "Draft") {
            guard !isDraft else { return }
            setLive(false)
        }
    }

    @ViewBuilder
    private var scheduledMark: some View {
        if document.status == "scheduled" {
            Image(systemName: "clock")
                .symbolVariant(.fill)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 22, height: 22)
                .help(scheduledHelp)
                .accessibilityLabel(scheduledHelp)
        }
    }

    private var publishedMark: some View {
        mark(systemName: "paperplane", active: document.status == "published", help: publishedHelp) {
            guard document.status != "published" else { return }
            setLive(true)
        }
    }

    @ViewBuilder
    private var waitingMark: some View {
        if document.draftRevisionID != nil {
            Menu {
                Button("Discard waiting draft", role: .destructive, action: discard)
            } label: {
                Image(systemName: "pencil.and.outline")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 22, height: 22)
            }
            .menuIndicator(.hidden)
            .help("Draft waiting")
            .accessibilityLabel("Draft waiting")
        }
    }

    private var isDraft: Bool {
        document.status != "published" && document.status != "scheduled"
    }

    private var publishedHelp: String {
        if document.draftRevisionID != nil { return "Published, draft waiting" }
        return document.status == "published" ? "Published" : "Publish"
    }

    private var scheduledHelp: String {
        guard let scheduledAt = document.scheduledAt, let date = EditorDocument.date(scheduledAt) else {
            return "Scheduled"
        }
        return "Scheduled \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private func mark(systemName: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .symbolVariant(active ? .fill : .none)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(width: 22, height: 22)
        }
        .help(help)
        .accessibilityLabel(help)
    }
}
