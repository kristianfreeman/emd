import SwiftUI

struct LibraryView: View {
    @Bindable var model: AppModel
    @State private var selection: String?

    var body: some View {
        List(selection: $selection) {
            if model.loadingLibrary && model.entries.isEmpty {
                Text("Loading")
                    .foregroundStyle(.secondary)
            } else if model.visibleEntries.isEmpty {
                Text(model.query.isEmpty ? "No posts" : "Nothing matches")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.visibleEntries) { entry in
                LibraryRow(entry: entry)
                    .tag(entry.id)
                    .onHover { inside in
                        if inside { model.prefetch(entry.id) }
                    }
            }
        }
        .listStyle(.sidebar)
        .contentMargins(.top, 12, for: .scrollContent)
        .searchable(text: $model.query, placement: .sidebar, prompt: "Find")
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                LibraryToolbar(model: model)
            }
        }
        .onChange(of: selection) { _, id in
            guard let id else { return }
            if id == model.document?.id || id == model.document?.localID || id == model.document?.remoteID {
                return
            }
            Task { await model.open(id) }
        }
        .onChange(of: model.document?.id) { _, id in
            guard let id, selection != id, selection != model.document?.localID else { return }
            selection = id
        }
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
            return "Draft"
        }
    }

    private var published: String {
        if entry.hasPendingDraft { return "Draft waiting" }
        guard let date = entry.publishedAt else { return "Published" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct LibraryToolbar: View {
    @Bindable var model: AppModel

    var body: some View {
        CollectionMenu(model: model)
        FilterMenu(model: model)
        NewPostButton(model: model)
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
            Image(systemName: "square.stack")
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
            Image(systemName: "line.3.horizontal.decrease")
        }
        .menuIndicator(.hidden)
        .help("Show")
    }
}

private struct NewPostButton: View {
    @Bindable var model: AppModel

    var body: some View {
        Button(action: { model.newPost() }) {
            Image(systemName: "plus")
        }
        .help("New Post")
        .disabled(model.collection == nil)
    }
}
