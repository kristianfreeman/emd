import SwiftUI

@main
struct EmDashWriterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private var model: AppModel { delegate.model }

    init() {
        FontBook.register()
    }

    var body: some Scene {
        Window("Emd", id: "main") {
            RootView(model: model)
        }
        .defaultSize(width: 1180, height: 800)
        .commands {
            WriterCommands(model: model)
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

/// Quitting waits for unsent text: a journal write first, then a few seconds for a real save.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
            ProbeServer.shared.start(model: model)
        #endif
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.hasUnsentText else { return .terminateNow }
        Task { @MainActor in
            await model.flushBeforeQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

struct WriterCommands: Commands {
    var model: AppModel

    var body: some Commands {
        SidebarCommands()
        CommandGroup(replacing: .newItem) {
            Button("New Post") { model.newPost() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(model.collection == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { Task { await model.save() } }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(model.document == nil || model.busy)
            Button(model.offline ? "Reconnect" : "Reload from Site") {
                if model.offline {
                    Task { await model.restore() }
                } else {
                    model.requestReload()
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!model.isConnected && !model.offline)
        }
        CommandGroup(after: .textEditing) {
            Button("Search Posts") { model.searchToken += 1 }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(!model.isConnected && !model.warming && !model.offline)
        }
        CommandGroup(after: .toolbar) {
            Divider()
            Toggle("Focus", isOn: Bindable(model).focusMode)
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Toggle("Typewriter", isOn: Bindable(model).typewriter)
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            TextSizeCommands(model: model)
            Divider()
        }
        CommandMenu("Post") {
            PostMenu(model: model)
        }
    }
}

private struct TextSizeCommands: View {
    var model: AppModel

    var body: some View {
        Button("Bigger") { model.setFontSize(model.fontSize + 1) }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(model.fontSize >= 24)
        Button("Smaller") { model.setFontSize(model.fontSize - 1) }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(model.fontSize <= 13)
        Button("Actual Size") { model.setFontSize(15) }
            .keyboardShortcut("0", modifiers: .command)
    }
}

private struct PostMenu: View {
    var model: AppModel

    var body: some View {
        if let document = model.document, document.loaded {
            PostActions(model: model, state: PostState(document))
        } else {
            Button("Publish") {}
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(true)
        }
        Divider()
        Button("Insert Image…") { model.chooseImages() }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(model.document?.loaded != true || model.client == nil)
        Divider()
        Button("Move to Trash…") {
            if let id = model.document?.id { model.requestTrash(id) }
        }
        .disabled(model.document == nil || model.busy)
    }
}

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var columns = NavigationSplitViewVisibility.automatic

    var body: some View {
        let palette = Palette.resolve(colorScheme)
        Group {
            if model.isConnected || model.warming || model.offline {
                workspace(palette)
            } else {
                ConnectView(model: model)
                    .frame(minWidth: 480, minHeight: 360)
            }
        }
        .preferredColorScheme(model.appearance.colorScheme)
        .task {
            model.reopenLast()
            await model.restore()
        }
    }

    private func workspace(_ palette: Palette) -> some View {
        NavigationSplitView(columnVisibility: $columns) {
            LibraryView(model: model, columns: columns)
        } detail: {
            EditorView(model: model, palette: palette)
                .background(palette.paper)
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: model.searchToken) {
            if columns == .detailOnly { columns = .all }
        }
        .frame(minWidth: 720, minHeight: 480)
        .modifier(PostDialogs(model: model))
    }
}

/// Confirmations for the things that cannot be taken back.
private struct PostDialogs: ViewModifier {
    @Bindable var model: AppModel

    func body(content: Content) -> some View {
        content
            .confirmationDialog(trashTitle, isPresented: $model.confirmTrash, titleVisibility: .visible) {
                Button("Move to Trash", role: .destructive) { Task { await model.trash() } }
                Button("Cancel", role: .cancel) { model.trashID = nil }
            } message: {
                Text(trashMessage)
            }
            .confirmationDialog(
                "Discard unpublished changes?", isPresented: $model.confirmDiscard, titleVisibility: .visible
            ) {
                Button("Discard Changes", role: .destructive) {
                    guard let id = model.discardID else { return }
                    Task { await model.discardRow(id) }
                }
            } message: {
                Text("The published version stays live. The changes made since are deleted from the site.")
            }
            .confirmationDialog(
                "Replace your edits with the site’s version?", isPresented: $model.confirmReload,
                titleVisibility: .visible
            ) {
                Button("Replace Edits", role: .destructive) { Task { await model.reloadOpen() } }
            } message: {
                Text("Edits that have not been saved to the site will be lost.")
            }
    }

    private var trashTitle: String {
        "Move “\(model.title(for: model.trashID ?? model.document?.id ?? ""))” to the trash?"
    }

    private var trashMessage: String {
        let id = model.trashID ?? model.document?.id ?? ""
        if id.hasPrefix("local-") { return "This post was never saved to the site, so it will be deleted." }
        return "You can restore it from the trash in the EmDash admin."
    }
}
