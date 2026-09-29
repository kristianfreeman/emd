import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            SiteForm(model: model, showsDisconnect: true)
                .formStyle(.grouped)
                .tabItem { Label("Site", systemImage: "globe") }
            writing
                .tabItem { Label("Writing", systemImage: "textformat") }
            library
                .tabItem { Label("Library", systemImage: "books.vertical") }
        }
        .frame(width: 480, height: 320)
    }

    private var writing: some View {
        Form {
            Picker("Appearance", selection: appearance) {
                ForEach(AppearanceChoice.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            Picker("Font", selection: font) {
                ForEach(WriterFont.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            Stepper(value: size, in: 13...24, step: 1) {
                Text("Size, \(Int(model.fontSize))")
            }
            Toggle("Focus", isOn: focus)
            Toggle("Typewriter", isOn: typewriter)
        }
        .formStyle(.grouped)
    }

    private var library: some View {
        Form {
            Picker("Collection", selection: collection) {
                if model.collections.isEmpty {
                    Text("Posts").tag("posts")
                }
                ForEach(model.collections) { item in
                    Text(item.label).tag(item.slug)
                }
            }
            Text(libraryNote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var libraryNote: String {
        let names = model.collections.map(\.label)
        if names.isEmpty {
            return "Connect a site to see its collections."
        }
        if model.collections.contains(where: { $0.slug == "posts" }) {
            return "The list shows this collection. Posts is the default."
        }
        return "This site has no Posts collection. Available: \(names.joined(separator: ", "))."
    }

    private var appearance: Binding<AppearanceChoice> {
        Binding(get: { model.appearance }, set: { model.setAppearance($0) })
    }

    private var font: Binding<WriterFont> {
        Binding(get: { model.fontChoice }, set: { model.setFont($0) })
    }

    private var size: Binding<Double> {
        Binding(get: { model.fontSize }, set: { model.setFontSize($0) })
    }

    private var focus: Binding<Bool> {
        Binding(get: { model.focusMode }, set: { model.setFocus($0) })
    }

    private var typewriter: Binding<Bool> {
        Binding(get: { model.typewriter }, set: { model.setTypewriter($0) })
    }

    private var collection: Binding<String> {
        Binding(
            get: { model.collection?.slug ?? "posts" },
            set: { slug in
                Task { await model.chooseCollection(slug) }
            }
        )
    }
}
