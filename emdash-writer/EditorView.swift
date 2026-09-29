import SwiftUI

struct EditorView: View {
    @Bindable var model: AppModel
    var palette: Palette

    var body: some View {
        writing
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.paper)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationSubtitle(subtitle)
            .toolbar {
                EditorToolbar(model: model, palette: palette)
            }
    }

    /// Site, status, and length. A confirmation like "Published" takes the line for a moment.
    private var subtitle: String {
        if !model.flashText.isEmpty { return model.flashText }
        guard let document = model.document, document.loaded else { return model.offline ? "Offline" : "" }
        let state = model.postState(document)
        let parts = [siteName, model.offline ? "Offline" : state.label, state.words]
        return parts.joined(separator: " · ")
    }

    private var siteName: String {
        model.siteTitle.isEmpty ? "Emd" : model.siteTitle
    }

    /// The post title lives in the title bar, where a click renames it.
    private func postTitle(_ document: EditorDocument) -> Binding<String> {
        Binding(
            get: {
                let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return title.isEmpty ? "Untitled" : document.title
            },
            set: { value in
                let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
                // Committing the placeholder unchanged is not a rename.
                if document.title.isEmpty && title == "Untitled" { return }
                document.title = title
            }
        )
    }

    @ViewBuilder
    private var writing: some View {
        if let document = model.document {
            loadedWriting(document)
                .navigationTitle(postTitle(document))
        } else {
            ContentUnavailableView {
                Label("No Post Open", systemImage: "square.and.pencil")
            } description: {
                Text("Choose a post from the list, or start a new one.")
            } actions: {
                Button("New Post") { model.newPost() }
                    .disabled(model.collection == nil)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(siteName)
        }
    }

    @ViewBuilder
    private func loadedWriting(_ document: EditorDocument) -> some View {
        if document.loaded {
            WritingColumn(
                bodyText: Binding(get: { document.body }, set: { document.body = $0 }),
                bodyRevision: document.textRevision,
                fontChoice: model.fontChoice,
                fontSize: CGFloat(model.fontSize),
                palette: palette,
                focusMode: model.focusMode,
                focusDepth: model.focusDepth,
                typewriter: model.typewriter,
                gutter: GutterCopy(document),
                caretKey: model.caretKey(document),
                wantsFocus: model.editorFocusID == document.localID,
                onFocus: { model.editorFocusID = nil },
                onEscape: { model.focusSidebar() },
                onImages: { sources, index in model.insertImages(sources, at: index) },
                onReady: { view in model.attachEditor(view, for: document) },
                site: model.siteURL
            )
            .id(document.localID)
        } else if let error = document.loadError {
            ContentUnavailableView {
                Label("Couldn’t Open This Post", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { Task { await model.retryOpen() } }
                    .disabled(model.client == nil)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(document.title.isEmpty ? "Loading…" : document.title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct EditorToolbar: ToolbarContent {
    var model: AppModel
    var palette: Palette

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if model.busy || model.uploadsInFlight > 0 {
                ProgressView()
                    .controlSize(.small)
                    .help(model.uploadsInFlight > 0 ? "Uploading images" : "Working")
            }
            if !model.notice.isEmpty {
                NoticeButton(model: model, palette: palette)
            }
            if let document = model.document, document.loaded {
                DetailsButton(model: model, document: document)
                Button {
                    model.chooseImages()
                } label: {
                    Label("Insert Image", systemImage: "photo")
                }
                .help("Insert Image… (⇧⌘I). You can also drop or paste images into the text.")
                .disabled(model.client == nil)
                PublishButton(model: model, state: model.postState(document))
            }
        }
    }
}

/// Title, slug, and excerpt in a popover under the toolbar.
private struct DetailsButton: View {
    @Bindable var model: AppModel
    var document: EditorDocument

    var body: some View {
        Button {
            model.showingDetails.toggle()
        } label: {
            Label("Post Details", systemImage: "info.circle")
        }
        .help("Post Details: title, slug, excerpt (⌃⌘I)")
        .popover(isPresented: $model.showingDetails, arrowEdge: .bottom) {
            PostDetails(model: model, document: document, hasExcerpt: model.collection?.excerptField != nil)
        }
    }
}

/// Errors and notes wait behind one button instead of crowding the title bar.
private struct NoticeButton: View {
    var model: AppModel
    var palette: Palette
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            Label("Notice", systemImage: model.offline ? "wifi.slash" : "exclamationmark.triangle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(palette.alert)
        }
        .help(model.notice)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            NoticeDetail(model: model, showing: $showing)
        }
    }
}

private struct NoticeDetail: View {
    var model: AppModel
    @Binding var showing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.notice)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                actions
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    @ViewBuilder
    private var actions: some View {
        if model.conflicted {
            Button("Use Site Version…") {
                showing = false
                model.requestReload()
            }
            Button("Keep My Version") {
                showing = false
                Task { await model.keepMine() }
            }
            .keyboardShortcut(.defaultAction)
        } else {
            Button("Dismiss") {
                model.notice = ""
                showing = false
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

/// Publish or Update when there is something to send, then a menu for the rest.
/// A toolbar draws a Menu as its icon alone, so the words live on a plain button beside it.
private struct PublishButton: View {
    var model: AppModel
    var state: PostState

    var body: some View {
        if state.canPublish {
            Button(state.publishTitle) { Task { await model.publish() } }
                .buttonStyle(.borderedProminent)
                .disabled(model.busy)
                .help(state.isLive ? "Publish unpublished changes (⇧⌘P)" : "Publish this post (⇧⌘P)")
        }
        Menu {
            PostActions(model: model, state: state, includesPublish: false)
        } label: {
            Label("Post Actions", systemImage: "ellipsis")
        }
        .menuIndicator(.hidden)
        .help("Post Actions")
        .disabled(model.busy)
        .popover(isPresented: Bindable(model).showingSchedule, arrowEdge: .bottom) {
            SchedulePicker { date in
                model.showingSchedule = false
                Task { await model.schedule(at: date) }
            }
        }
    }
}

/// The post's actions, shared by the toolbar menu and the Post menu in the menu bar.
struct PostActions: View {
    var model: AppModel
    var state: PostState
    var includesPublish = true

    var body: some View {
        if includesPublish {
            Button(state.publishTitle == "Update" ? "Publish Changes" : "Publish") {
                Task { await model.publish() }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(!state.canPublish || model.busy)
        }
        if state.isScheduled {
            Button("Unschedule") { Task { await model.unschedule() } }
                .disabled(model.busy)
        } else {
            Button("Schedule…") { model.showingSchedule = true }
                .disabled(
                    state.document.status == "published" && !state.hasUnpublishedChanges || state.writesLive
                        || model.busy)
        }
        Button("Unpublish") { Task { await model.unpublish() } }
            .disabled(!state.isLive || model.busy)
        Button("Discard Unpublished Changes…") {
            if let id = state.document.remoteID { model.requestDiscard(id) }
        }
        .disabled(!state.canDiscardChanges || model.busy)
        Divider()
        Button("Preview in Browser") { Task { await model.previewOpen() } }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(model.client == nil || (state.document.remoteID == nil && state.document.words == 0))
        Button("Show in Browser") { model.showOpenInBrowser() }
            .disabled(!model.canShowOpenInBrowser)
        Button("Show in EmDash Admin") {
            if let id = state.document.remoteID { model.showInAdmin(id) }
        }
        .disabled(state.document.remoteID == nil)
    }
}
