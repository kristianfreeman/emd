import SwiftUI

struct LibraryView: View {
    @Bindable var model: AppModel
    var columns: NavigationSplitViewVisibility
    @State private var selection: String?
    @State private var renamingID: String?
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool
    @FocusState private var listFocused: Bool
    @State private var searching = false

    var body: some View {
        let visible = model.visibleEntries
        List(selection: $selection) {
            Section(model.collection?.label ?? "Posts") {
                ForEach(visible) { entry in
                    row(entry)
                        .tag(entry.id)
                        .contextMenu { RowMenu(model: model, entry: entry, rename: { startRename(entry) }) }
                        .onHover { inside in
                            if inside { model.prefetch(entry.id) }
                        }
                }
            }
        }
        .overlay { LibraryEmpty(model: model, isEmpty: visible.isEmpty) }
        .listStyle(.sidebar)
        .onDeleteCommand {
            guard let selection, renamingID == nil else { return }
            model.requestTrash(selection)
        }
        .focused($listFocused)
        .onKeyPress(keys: [.return, .tab]) { _ in startWriting() }
        .onChange(of: model.sidebarFocusToken) { listFocused = true }
        .contentMargins(.top, 12, for: .scrollContent)
        .onChange(of: model.searchToken) { searching = true }
        .searchable(
            text: $model.query, isPresented: $searching, placement: .sidebar,
            prompt: "Search \(model.collection?.label ?? "Posts")"
        )
        .navigationSplitViewColumnWidth(min: 220, ideal: 290, max: 420)
        .toolbar {
            if columns != .detailOnly {
                SidebarSpacer()
                ToolbarItemGroup(placement: .primaryAction) {
                    CollectionMenu(model: model)
                    FilterMenu(model: model)
                    NewPostButton(model: model)
                }
            }
        }
        .onChange(of: selection) { _, id in
            guard let id else { return }
            if id == model.document?.id || id == model.document?.localID || id == model.document?.remoteID {
                return
            }
            model.openFromList(id)
        }
        .onChange(of: model.document?.id) { _, id in
            guard let id, selection != id, selection != model.document?.localID else { return }
            selection = id
        }
    }

    @ViewBuilder
    private func row(_ entry: ContentSummary) -> some View {
        if renamingID == entry.id {
            TextField("Title", text: $renameText)
                .focused($renameFocused)
                .onSubmit(finishRename)
                .onExitCommand { renamingID = nil }
                .onAppear { renameFocused = true }
                .onChange(of: renameFocused) { _, focused in
                    if !focused && renamingID != nil { finishRename() }
                }
        } else {
            LibraryRow(entry: entry)
        }
    }

    /// Return or Tab on the list moves into the open post. Arrowing through the list only opens posts.
    private func startWriting() -> KeyPress.Result {
        guard renamingID == nil, model.document != nil else { return .ignored }
        model.focusEditor()
        return .handled
    }

    private func startRename(_ entry: ContentSummary) {
        renamingID = entry.id
        renameText = entry.title
        renameFocused = true
    }

    private func finishRename() {
        let id = renamingID
        let title = renameText
        renamingID = nil
        guard let id else { return }
        Task { await model.rename(id, to: title) }
    }

}

private struct LibraryRow: View {
    var entry: ContentSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.title)
                .lineLimit(1)
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var status: String {
        switch entry.status {
        case "published":
            return published
        case "scheduled":
            return "Scheduled"
        default:
            return draft
        }
    }

    private var published: String {
        if entry.hasPendingDraft { return "Unpublished changes" }
        guard let date = entry.publishedAt else { return "Published" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private var draft: String {
        guard let date = entry.updatedAt else { return "Draft" }
        return "Draft · \(date.formatted(.relative(presentation: .named)))"
    }
}

/// Loading, empty, and no-match states sit over the list instead of pretending to be rows.
private struct LibraryEmpty: View {
    var model: AppModel
    var isEmpty: Bool

    var body: some View {
        if isEmpty {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.loadingLibrary && model.entries.isEmpty {
            ProgressView("Loading…")
                .controlSize(.small)
        } else if !model.query.isEmpty {
            ContentUnavailableView.search(text: model.query)
        } else if model.filter != .all {
            ContentUnavailableView("No \(model.filter.label) Posts", systemImage: "line.3.horizontal.decrease.circle")
        } else {
            ContentUnavailableView {
                Label("No Posts Yet", systemImage: "doc.text")
            } actions: {
                Button("New Post") { model.newPost() }
                    .disabled(model.collection == nil)
            }
        }
    }
}

private struct SidebarSpacer: ToolbarContent {
    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarSpacer(.flexible, placement: .primaryAction)
        }
    }
}

private struct CollectionMenu: View {
    @Bindable var model: AppModel

    var body: some View {
        Menu {
            Picker("Collection", selection: collectionChoice) {
                ForEach(model.collections) { collection in
                    Text(collection.label).tag(collection.slug)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label("Collection", systemImage: "square.stack")
                .labelStyle(.iconOnly)
        }
        .menuIndicator(.hidden)
        .help("Collection")
        .disabled(model.collections.isEmpty)
    }

    private var collectionChoice: Binding<String> {
        Binding(
            get: { model.collection?.slug ?? "posts" },
            set: { slug in
                Task { await model.chooseCollection(slug) }
            }
        )
    }
}

private struct FilterMenu: View {
    @Bindable var model: AppModel

    var body: some View {
        Menu {
            Picker("Show", selection: $model.filter) {
                ForEach(LibraryFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label(
                "Filter",
                systemImage: model.filter == .all
                    ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
            )
            .labelStyle(.iconOnly)
        }
        .menuIndicator(.hidden)
        .help(model.filter == .all ? "Filter Posts" : "Showing \(model.filter.label)")
    }
}

private struct RowMenu: View {
    @Bindable var model: AppModel
    var entry: ContentSummary
    var rename: () -> Void

    var body: some View {
        Button("Rename", action: rename)
        statusItems
        linkItems
        Divider()
        Button("Move to Trash…", role: .destructive) { model.requestTrash(entry.id) }
            .disabled(model.busy)
    }

    @ViewBuilder
    private var statusItems: some View {
        if showsPublish {
            Button(entry.hasPendingDraft ? "Publish Changes" : "Publish") { Task { await model.publishRow(entry.id) } }
                .disabled(model.busy)
        }
        if showsDiscard {
            Button("Discard Unpublished Changes…") { model.requestDiscard(entry.id) }
                .disabled(model.busy)
        }
        if showsUnpublish {
            Button("Unpublish") { Task { await model.unpublishRow(entry.id) } }
                .disabled(model.busy)
        }
    }

    @ViewBuilder
    private var linkItems: some View {
        if showsBrowser {
            Button("Show in Browser") { model.showInBrowser(entry) }
        }
        if showsAdmin {
            Button("Show in EmDash Admin") { model.showInAdmin(entry.id) }
        }
    }

    private var showsPublish: Bool {
        if entry.hasPendingDraft { return true }
        return entry.status != "published" && entry.status != "scheduled"
    }

    private var showsDiscard: Bool {
        entry.hasPendingDraft && (entry.status == "published" || entry.status == "scheduled")
    }

    private var showsUnpublish: Bool {
        entry.status == "published" || entry.status == "scheduled"
    }

    private var showsBrowser: Bool {
        guard let site = model.siteURL, let collection = model.collection else { return false }
        return RowLink.browser(site: site, collection: collection.slug, entry: entry) != nil
    }

    private var showsAdmin: Bool {
        guard let site = model.siteURL, let collection = model.collection else { return false }
        return RowLink.admin(site: site, collection: collection.slug, id: entry.id) != nil
    }
}

private struct NewPostButton: View {
    @Bindable var model: AppModel

    var body: some View {
        Button(action: { model.newPost() }) {
            Label("New Post", systemImage: "square.and.pencil")
                .labelStyle(.iconOnly)
        }
        .help("New Post")
        .disabled(model.collection == nil)
    }
}
