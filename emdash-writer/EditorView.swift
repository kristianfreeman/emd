import SwiftUI

struct EditorView: View {
    @Bindable var model: AppModel
    var palette: Palette
    @State private var gutterShown = false
    @State private var pointerInGutter = false
    @State private var hideGutter: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            writing
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.document != nil {
                gutter
            }
        }
        .background(palette.paper)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(model.siteTitle.isEmpty ? "Em Dash Writer" : model.siteTitle)
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
        .onChange(of: model.document?.body) { _, _ in
            model.scheduleAutosave()
            revealGutter()
        }
        .onChange(of: model.document?.title) { _, _ in
            model.scheduleAutosave()
            revealGutter()
        }
        .onChange(of: model.document?.excerpt) { _, _ in model.scheduleAutosave() }
        .onChange(of: model.document?.slug) { _, _ in model.scheduleAutosave() }
        .onChange(of: model.document?.localID) { _, _ in
            gutterShown = false
        }
    }

    private func revealGutter() {
        guard model.document?.loaded == true else { return }
        gutterShown = true
        scheduleGutterHide()
    }

    private func scheduleGutterHide() {
        hideGutter?.cancel()
        hideGutter = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, !pointerInGutter else { return }
            gutterShown = false
        }
    }

    private var gutter: some View {
        Group {
            if let document = model.document, document.loaded {
                PropertiesText(document: document)
            } else {
                Color.clear
            }
        }
        .padding(.top, 76)
        .padding(.leading, 16)
        .padding(.trailing, 28)
        .frame(width: 244, alignment: .topLeading)
        .opacity(gutterShown ? 0.9 : 0)
        .animation(.easeOut(duration: 0.45), value: gutterShown)
        .onHover { inside in
            pointerInGutter = inside
            if inside {
                gutterShown = true
                hideGutter?.cancel()
            } else {
                scheduleGutterHide()
            }
        }
    }

    @ViewBuilder
    private var writing: some View {
        if let document = model.document {
            if document.loaded {
                WritingColumn(
                    title: Binding(get: { document.title }, set: { document.title = $0 }),
                    bodyText: Binding(get: { document.body }, set: { document.body = $0 }),
                    fontChoice: model.fontChoice,
                    fontSize: CGFloat(model.fontSize),
                    palette: palette,
                    focusMode: model.focusMode,
                    typewriter: model.typewriter
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
        } else {
            Text("Choose a post, or start a new one.")
                .foregroundStyle(.secondary)
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
            mark(systemName: "pencil", active: isDraft, help: "Draft") {
                guard !isDraft else { return }
                setLive(false)
            }
            if document.status == "scheduled" {
                Image(systemName: "clock")
                    .symbolVariant(.fill)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 22, height: 22)
                    .help(scheduledHelp)
                    .accessibilityLabel(scheduledHelp)
            }
            mark(systemName: "paperplane", active: document.status == "published", help: publishedHelp) {
                guard document.status != "published" else { return }
                setLive(true)
            }
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
        .buttonStyle(.plain)
        .disabled(busy)
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
