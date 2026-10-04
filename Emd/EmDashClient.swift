import Foundation

struct EmDashClient {
    var site: URL
    var token: String
    var session: URLSession

    init(site: URL, token: String, session: URLSession = .shared) {
        self.site = site
        self.token = token
        self.session = session
    }

    func taxonomies() async throws -> [TaxonomyInfo] {
        let data = try await send("GET", "/taxonomies")
        return data.object?["taxonomies"]?.array?.compactMap(Self.taxonomy(from:)) ?? []
    }

    func terms(collection: String, id: String, taxonomy: String) async throws -> [TermLabel] {
        let data = try await send(
            "GET",
            "/content/\(Self.path(collection))/\(Self.path(id))/terms/\(Self.path(taxonomy))"
        )
        return data.object?["terms"]?.array?.compactMap(Self.term(from:)) ?? []
    }

    func settings() async throws -> SiteSettings {
        let data = try await send("GET", "/settings")
        return SiteSettings(
            title: data.object?["title"]?.string ?? "",
            tagline: data.object?["tagline"]?.string ?? ""
        )
    }

    /// The admin manifest: plugins and the custom Portable Text blocks they declare.
    func manifest() async throws -> JSONValue {
        try await send("GET", "/manifest")
    }

    func collections() async throws -> [CollectionDef] {
        let data = try await send("GET", "/schema/collections")
        let items = data.object?["items"]?.array ?? []
        return items.compactMap(Self.collection(from:))
    }

    func collection(_ slug: String) async throws -> CollectionDef {
        let data = try await send("GET", "/schema/collections/\(Self.path(slug))?includeFields=true")
        guard let item = data.object?["item"], let collection = Self.collection(from: item) else {
            throw APIError(status: 500, code: "BAD_RESPONSE", message: "The site did not return a collection.")
        }
        return collection
    }
}
