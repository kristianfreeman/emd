import Foundation

/// Tags and categories from Post Details. The site stores them at once, not with the draft.
/// Each write sends the whole list for a taxonomy, so writes wait for the post's terms to load, run one at a
/// time, and each starts from what the last one left.
extension AppModel {
    /// Every term in each taxonomy, fresh each time Post Details opens. A failed load is not kept.
    func loadTaxonomyTerms() async {
        guard let client else { return }
        for taxonomy in applicableTaxonomies {
            let terms = try? await client.allTerms(taxonomy: taxonomy.name)
            taxonomyTerms[taxonomy.name] = terms ?? taxonomyTerms[taxonomy.name]
        }
    }

    /// Adds the term with this name, making it if the taxonomy has none by that name.
    func assign(_ label: String, in taxonomy: TaxonomyInfo, to document: EditorDocument) async {
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let client else { return }
        await changeTerms(taxonomy, of: document) { current in
            let term = try await self.existingOrNewTerm(name, in: taxonomy, client: client)
            return current.contains { $0.id == term.id } ? current : current + [term]
        }
    }

    /// Adds a term picked from the site's list, exactly that one.
    func assign(_ term: TermLabel, in taxonomy: TaxonomyInfo, to document: EditorDocument) async {
        await changeTerms(taxonomy, of: document) { current in
            current.contains { $0.id == term.id } ? current : current + [term]
        }
    }

    func unassign(_ term: TermLabel, in taxonomy: TaxonomyInfo, from document: EditorDocument) async {
        await changeTerms(taxonomy, of: document) { current in current.filter { $0.id != term.id } }
    }

    func assigned(_ taxonomy: TaxonomyInfo, in document: EditorDocument) -> [TermLabel] {
        document.termGroups.first { $0.taxonomy == taxonomy.name }?.terms ?? []
    }

    /// Runs after any term change already on its way, against the terms that change left.
    private func changeTerms(
        _ taxonomy: TaxonomyInfo, of document: EditorDocument,
        _ change: @escaping ([TermLabel]) async throws -> [TermLabel]
    ) async {
        let previous = termWrites
        let next = Task { @MainActor in
            await previous?.value
            await self.applyTermChange(taxonomy, of: document, change)
        }
        termWrites = next
        await next.value
    }

    private func applyTermChange(
        _ taxonomy: TaxonomyInfo, of document: EditorDocument, _ change: ([TermLabel]) async throws -> [TermLabel]
    ) async {
        guard document.termsLoaded else {
            notice = "\(taxonomy.label) are still loading from the site. Try again in a moment."
            await refreshTerms(for: document)
            return
        }
        do {
            let wanted = try await change(assigned(taxonomy, in: document))
            await write(wanted.map(\.id), taxonomy: taxonomy, document: document)
        } catch {
            report(error)
        }
    }

    private func existingOrNewTerm(_ name: String, in taxonomy: TaxonomyInfo, client: EmDashClient) async throws
        -> TermLabel
    {
        let known = taxonomyTerms[taxonomy.name]?.first { $0.label.caseInsensitiveCompare(name) == .orderedSame }
        if let known { return known }
        let created = try await client.createTerm(taxonomy: taxonomy.name, label: name)
        taxonomyTerms[taxonomy.name, default: []].append(created)
        return created
    }

    private func write(_ ids: [String], taxonomy: TaxonomyInfo, document: EditorDocument) async {
        guard let client, let collection, let remoteID = document.remoteID else { return }
        do {
            let terms = try await client.setTerms(
                collection: collection.slug, id: remoteID, taxonomy: taxonomy.name, termIDs: ids)
            var groups = document.termGroups.filter { $0.taxonomy != taxonomy.name }
            groups.append(TermGroup(taxonomy: taxonomy.name, label: taxonomy.label, terms: terms))
            document.termGroups = groups.sorted { $0.label < $1.label }
        } catch {
            report(error)
        }
    }
}
