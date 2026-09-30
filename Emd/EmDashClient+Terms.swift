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

extension EmDashClient {
    /// A signed link that shows the post's latest draft on the site, good for an hour. `path` is where the
    /// site shows the post; without one the site uses its default, `/{collection}/{id}`, which a site that
    /// routes by slug may redirect, dropping the preview token.
    func previewURL(collection: String, id: String, path: String? = nil) async throws -> URL {
        let body: JSONValue = path.map { .object(["pathPattern": .string($0)]) } ?? .object([:])
        let data = try await send(
            "POST", "/content/\(Self.path(collection))/\(Self.path(id))/preview-url", body: body)
        guard let text = data.object?["url"]?.string, let url = Self.resolved(text, site: site) else {
            throw APIError(status: 500, code: "BAD_RESPONSE", message: "The site did not return a preview link.")
        }
        return url
    }

    /// The site answers with a path; an absolute URL is used as it is.
    static func resolved(_ text: String, site: URL) -> URL? {
        guard let url = URL(string: text) else { return nil }
        return url.scheme == nil ? URL(string: text, relativeTo: site)?.absoluteURL : url
    }
}
