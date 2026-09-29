import Foundation

/// Tags and categories. Assignments save to the site at once; they are not part of a post's draft.
extension EmDashClient {
    /// Every term in a taxonomy, children included, in the site's order.
    func allTerms(taxonomy: String) async throws -> [TermLabel] {
        let data = try await send("GET", "/taxonomies/\(Self.path(taxonomy))/terms")
        return Self.flattened(data.object?["terms"]?.array ?? [])
    }

    /// Replaces the post's terms in `taxonomy` and returns what the site now has.
    func setTerms(collection: String, id: String, taxonomy: String, termIDs: [String]) async throws -> [TermLabel] {
        let body: JSONValue = .object(["termIds": .array(termIDs.map(JSONValue.string))])
        let data = try await send(
            "POST", "/content/\(Self.path(collection))/\(Self.path(id))/terms/\(Self.path(taxonomy))", body: body)
        return data.object?["terms"]?.array?.compactMap(Self.term(from:)) ?? []
    }

    /// A new term; the site picks a unique slug from the label.
    func createTerm(taxonomy: String, label: String) async throws -> TermLabel {
        let data = try await send(
            "POST", "/taxonomies/\(Self.path(taxonomy))/terms", body: .object(["label": .string(label)]))
        guard let term = data.object?["term"].flatMap(Self.term(from:)) else {
            throw APIError(status: 500, code: "BAD_RESPONSE", message: "The site did not return the new term.")
        }
        return term
    }

    static func flattened(_ values: [JSONValue]) -> [TermLabel] {
        values.flatMap { value -> [TermLabel] in
            let own = term(from: value).map { [$0] } ?? []
            return own + flattened(value.object?["children"]?.array ?? [])
        }
    }
}
