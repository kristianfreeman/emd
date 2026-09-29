import Foundation

extension AppModel {
    var visibleEntries: [ContentSummary] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return (localSummaries() + remoteSummaries())
            .filter { matchesFilter($0) && matches($0, needle: needle) }
            .sorted { $0.sortDate > $1.sortDate }
    }

    private func localSummaries() -> [ContentSummary] {
        drafts.filter { $0.collectionSlug == nil || $0.collectionSlug == collection?.slug }.map { draft in
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

    private func matches(_ entry: ContentSummary, needle: String) -> Bool {
        guard !needle.isEmpty else { return true }
        return entry.title.localizedStandardContains(needle) || entry.slug.localizedStandardContains(needle)
    }

    func remember(_ entry: LoadedEntry) {
        guard let site = siteURL?.host, !entry.id.isEmpty else { return }
        LocalStore.storeEntry(site: site, entry: entry)
    }

    /// Caches the site's copy of a post: the saved text, never text still waiting to be sent.
    func remember(_ document: EditorDocument) {
        guard let remoteID = document.remoteID else { return }
        remember(stored(document, id: remoteID))
    }

    /// Updates one sidebar row in place, without paging through the whole library again.
    func patchRow(_ document: EditorDocument) {
        guard let remoteID = document.remoteID, let index = entries.firstIndex(where: { $0.id == remoteID }) else {
            return
        }
        entries[index].title = document.listTitle
        entries[index].status = document.status
        entries[index].updatedAt = Date()
        entries[index].publishedAt = EditorDocument.date(document.publishedAt)
        entries[index].hasPendingDraft = document.draftRevisionID != nil
    }

    private func stored(_ document: EditorDocument, id: String) -> LoadedEntry {
        let text = document.savedText
        return LoadedEntry(
            id: id,
            rev: document.rev,
            slug: text.slug,
            status: document.status,
            title: text.title,
            body: text.body,
            excerpt: text.excerpt,
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
        document.termGroups = groups.map(\.term)
        // Term writes replace whole lists, so they wait until every list here came from the site.
        document.termsLoaded = !groups.contains { $0.failed }
    }

    private func termGroups(_ fetch: TermFetch) async -> [IndexedTerm] {
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
        let labels = try? await fetch.client.terms(collection: fetch.collection, id: fetch.id, taxonomy: taxonomy.name)
        let term = TermGroup(taxonomy: taxonomy.name, label: taxonomy.label, terms: labels ?? [])
        return IndexedTerm(index: index, term: term, failed: labels == nil)
    }

    private func gatheredTerms(_ group: inout TaskGroup<IndexedTerm>) async -> [IndexedTerm] {
        var collected: [IndexedTerm] = []
        for await item in group {
            collected.append(item)
        }
        return collected.sorted { $0.index < $1.index }
    }
}

private struct IndexedTerm {
    var index: Int
    var term: TermGroup
    var failed = false
}

private struct TermFetch {
    var client: EmDashClient
    var collection: String
    var id: String
}
