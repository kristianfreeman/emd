import SwiftUI

@main
struct EmDashWriterApp: App {
    @State private var model = AppModel()

    init() {
        FontBook.register()
    }

    var body: some Scene {
        WindowGroup {
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

struct WriterCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Post") { model.newPost() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(model.collection == nil)
        }
        CommandGroup(after: .newItem) {
            Button("Save") { Task { await model.save() } }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(model.document == nil || model.busy)
            Divider()
            Button("Move to Trash") { model.confirmTrash = true }
                .disabled(model.document == nil || model.busy)
            Button("Reload") { Task { await model.reloadOpen() } }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!model.isConnected)
        }
        CommandGroup(after: .toolbar) {
            Toggle("Focus", isOn: Bindable(model).focusMode)
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Toggle("Typewriter", isOn: Bindable(model).typewriter)
        }
    }
}

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Palette.resolve(colorScheme)
        Group {
            if model.isConnected || model.warming {
                workspace(palette)
            } else {
                ConnectView(model: model)
                    .frame(minWidth: 480, minHeight: 360)
            }
        }
        .preferredColorScheme(model.appearance.colorScheme)
        .task { await model.restore() }
    }

    private func workspace(_ palette: Palette) -> some View {
        NavigationSplitView {
            LibraryView(model: model)
        } detail: {
            EditorView(model: model, palette: palette)
                .background(palette.paper)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 560)
        .confirmationDialog(
            "Move this post to the trash?",
            isPresented: $model.confirmTrash,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                Task { await model.trash() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
