import Foundation

extension AppModel {
    var visibleEntries: [ContentSummary] {
        (localSummaries() + remoteSummaries()).filter { shows($0) }.sorted { $0.sortDate > $1.sortDate }
    }

    private func localSummaries() -> [ContentSummary] {
        drafts.map { draft in
            ContentSummary(
                id: draft.id,
                slug: draft.slug,
                status: draft.status,
                title: draft.listTitle,
                updatedAt: draft.updatedAt ?? draft.openedAt,
                publishedAt: nil,
                hasPendingDraft: false
            )
        }
    }

    private func remoteSummaries() -> [ContentSummary] {
        entries.map { entry in
            guard let document, document.remoteID == entry.id else { return entry }
            return reflecting(entry, document: document)
        }
    }

    private func reflecting(_ entry: ContentSummary, document: EditorDocument) -> ContentSummary {
        var copy = entry
        copy.title = document.listTitle
        copy.slug = document.slug
        copy.status = document.status
        copy.hasPendingDraft = document.draftRevisionID != nil
        return copy
    }

    private func shows(_ entry: ContentSummary) -> Bool {
        guard matchesFilter(entry) else { return false }
        return matchesQuery(entry)
    }

    private func matchesFilter(_ entry: ContentSummary) -> Bool {
        switch filter {
        case .all:
            return true
        case .drafts:
            return isDraftLike(entry)
        case .live:
            return entry.status == "published"
        }
    }

    private func isDraftLike(_ entry: ContentSummary) -> Bool {
        entry.status == "draft" || entry.status == "scheduled" || entry.hasPendingDraft
    }

    private func matchesQuery(_ entry: ContentSummary) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return entry.title.lowercased().contains(needle) || entry.slug.lowercased().contains(needle)
    }

    func remember(_ entry: LoadedEntry) {
        guard let site = siteURL?.host, !entry.id.isEmpty else { return }
        LocalStore.storeEntry(site: site, entry: entry)
    }

    func rememberOpen() {
        guard let document, let remoteID = document.remoteID else { return }
        remember(stored(document, id: remoteID))
    }

    private func stored(_ document: EditorDocument, id: String) -> LoadedEntry {
        LoadedEntry(
            id: id,
            rev: document.rev,
            slug: document.slug,
            status: document.status,
            title: document.title,
            body: document.body,
            excerpt: document.excerpt,
            updatedAt: nil,
            publishedAt: document.publishedAt,
            scheduledAt: document.scheduledAt,
            draftRevisionID: document.draftRevisionID
        )
    }

    func refreshTerms(for document: EditorDocument) async {
        guard let client, let collection, let remoteID = document.remoteID else {
            document.termGroups = []
            return
        }
        let fetch = TermFetch(client: client, collection: collection.slug, id: remoteID)
        let groups = await termGroups(fetch)
        guard document.remoteID == remoteID else { return }
        document.termGroups = groups
    }

    private func termGroups(_ fetch: TermFetch) async -> [TermGroup] {
        let applicable = taxonomies.filter { $0.collections.isEmpty || $0.collections.contains(fetch.collection) }
        return await withTaskGroup(of: IndexedTerm.self) { group in
            self.enqueueTerms(applicable, fetch: fetch, group: &group)
            return await self.gatheredTerms(&group)
        }
    }

    private func enqueueTerms(
        _ applicable: [TaxonomyInfo],
        fetch: TermFetch,
        group: inout TaskGroup<IndexedTerm>
    ) {
        for (index, taxonomy) in applicable.enumerated() {
            group.addTask { await Self.term(index, taxonomy: taxonomy, fetch: fetch) }
        }
    }

    private static func term(_ index: Int, taxonomy: TaxonomyInfo, fetch: TermFetch) async -> IndexedTerm {
        let labels =
            (try? await fetch.client.terms(collection: fetch.collection, id: fetch.id, taxonomy: taxonomy.name)) ?? []
        let term = TermGroup(label: taxonomy.label, value: labels.map(\.label).joined(separator: ", "))
        return IndexedTerm(index: index, term: term)
    }

    private func gatheredTerms(_ group: inout TaskGroup<IndexedTerm>) async -> [TermGroup] {
        var collected: [IndexedTerm] = []
        for await item in group {
            collected.append(item)
        }
        return collected.sorted { $0.index < $1.index }.map(\.term)
    }
}

private struct IndexedTerm {
    var index: Int
    var term: TermGroup
}

private struct TermFetch {
    var client: EmDashClient
    var collection: String
    var id: String
}
