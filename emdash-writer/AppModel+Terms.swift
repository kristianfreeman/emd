import Foundation

/// Tags and categories from Post Details. The site stores them at once, not with the draft.
extension AppModel {
    func loadTaxonomyTerms() async {
        guard let client else { return }
        for taxonomy in applicableTaxonomies where taxonomyTerms[taxonomy.name] == nil {
            taxonomyTerms[taxonomy.name] = (try? await client.allTerms(taxonomy: taxonomy.name)) ?? []
        }
    }

    /// Adds the term with this label, making it first if the taxonomy has none by that name.
    func assign(_ label: String, in taxonomy: TaxonomyInfo, to document: EditorDocument) async {
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let client else { return }
        do {
            let term = try await existingOrNewTerm(name, in: taxonomy, client: client)
            let current = assigned(taxonomy, in: document)
            guard !current.contains(where: { $0.id == term.id }) else { return }
            await write(current.map(\.id) + [term.id], taxonomy: taxonomy, document: document)
        } catch {
            report(error)
        }
    }

    func unassign(_ term: TermLabel, in taxonomy: TaxonomyInfo, from document: EditorDocument) async {
        let remaining = assigned(taxonomy, in: document).filter { $0.id != term.id }
        await write(remaining.map(\.id), taxonomy: taxonomy, document: document)
    }

    func assigned(_ taxonomy: TaxonomyInfo, in document: EditorDocument) -> [TermLabel] {
        document.termGroups.first { $0.taxonomy == taxonomy.name }?.terms ?? []
    }

    private func existingOrNewTerm(_ name: String, in taxonomy: TaxonomyInfo, client: EmDashClient) async throws
        -> TermLabel
    {
        if let known = taxonomyTerms[taxonomy.name]?.first(where: {
            $0.label.caseInsensitiveCompare(name) == .orderedSame
        }) {
            return known
        }
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
