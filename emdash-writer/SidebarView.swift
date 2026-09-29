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
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .lineLimit(1)
                    Text(rowStatus(entry))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

                Button(action: { model.newPost() }) {
                    Image(systemName: "plus")
                }
                .help("New Post")
                .disabled(model.collection == nil)
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

    private var collectionChoice: Binding<String> {
        Binding(
            get: { model.collection?.slug ?? "posts" },
            set: { slug in
                Task { await model.chooseCollection(slug) }
            }
        )
    }

    private func rowStatus(_ entry: ContentSummary) -> String {
        switch entry.status {
        case "published":
            if entry.hasPendingDraft { return "Draft waiting" }
            if let published = entry.publishedAt {
                return published.formatted(date: .abbreviated, time: .omitted)
            }
            return "Published"
        case "scheduled":
            return "Scheduled"
        default:
            return "Draft"
        }
    }
}
