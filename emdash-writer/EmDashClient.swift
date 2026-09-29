import Foundation

struct FieldDef: Equatable, Identifiable, Sendable {
    var slug: String
    var label: String
    var type: String
    var required: Bool
    var sortOrder: Int

    var id: String { slug }
}

struct CollectionDef: Equatable, Identifiable, Sendable {
    var slug: String
    var label: String
    var labelSingular: String
    var fields: [FieldDef]

    var id: String { slug }

    var titleField: FieldDef? {
        if let title = fields.first(where: { $0.slug == "title" && ($0.type == "string" || $0.type == "text") }) {
            return title
        }
        return fields.filter { $0.type == "string" }.sorted { $0.sortOrder < $1.sortOrder }.first
    }

    var excerptField: FieldDef? {
        fields.first { $0.slug == "excerpt" && ($0.type == "text" || $0.type == "string") }
    }

    var bodyField: FieldDef? {
        let skipped = Set([titleField?.slug, excerptField?.slug].compactMap { $0 })
        let candidates = fields
            .filter { ($0.type == "portableText" || $0.type == "text") && !skipped.contains($0.slug) }
            .sorted { $0.sortOrder < $1.sortOrder }
        if let named = candidates.first(where: { $0.slug == "content" || $0.slug == "body" }) {
            return named
        }
        if let rich = candidates.first(where: { $0.type == "portableText" }) {
            return rich
        }
        return candidates.first
    }
}

struct SiteSettings: Equatable {
    var title: String
    var tagline: String
}

struct TaxonomyInfo: Equatable, Identifiable {
    var name: String
    var label: String
    var collections: [String]

    var id: String { name }
}

struct TermLabel: Equatable, Identifiable {
    var id: String
    var label: String
}

struct ContentSummary: Codable, Equatable, Identifiable {
    var id: String
    var slug: String
    var status: String
    var title: String
    var updatedAt: Date?
    var publishedAt: Date?
    var hasPendingDraft: Bool

    var sortDate: Date { publishedAt ?? updatedAt ?? .distantPast }
}

struct LoadedEntry: Codable, Equatable {
    var id: String
    var rev: String?
    var slug: String
    var status: String
    var title: String
    var body: String
    var excerpt: String
    var updatedAt: String?
    var publishedAt: String?
    var scheduledAt: String?
    var draftRevisionID: String?
}

struct APIError: LocalizedError, Equatable {
    var status: Int
    var code: String
    var message: String

    var errorDescription: String? { message }
}

enum SiteURL {
    static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            text = "https://\(text)"
        }
        guard var parts = URLComponents(string: text),
              let scheme = parts.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = parts.host,
              !host.isEmpty
        else { return nil }
        parts.scheme = scheme
        parts.host = host.lowercased()
        parts.path = ""
        parts.query = nil
        parts.fragment = nil
        parts.user = nil
        parts.password = nil
        return parts.url
    }

    static func endpoint(site: URL, path: String) -> URL {
        let pieces = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var parts = URLComponents(url: site, resolvingAgainstBaseURL: false) ?? URLComponents()
        let suffix = pieces[0].hasPrefix("/") ? String(pieces[0]) : "/" + pieces[0]
        parts.path = "/_emdash/api" + suffix
        parts.query = pieces.count == 2 ? String(pieces[1]) : nil
        return parts.url ?? site
    }
}

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
        return data.object?["taxonomies"]?.array?.compactMap { value -> TaxonomyInfo? in
            guard let object = value.object, let name = object["name"]?.string else { return nil }
            let collections = object["collections"]?.array?.compactMap(\.string) ?? []
            return TaxonomyInfo(name: name, label: object["label"]?.string ?? name, collections: collections)
        } ?? []
    }

    func terms(collection: String, id: String, taxonomy: String) async throws -> [TermLabel] {
        let data = try await send(
            "GET",
            "/content/\(Self.path(collection))/\(Self.path(id))/terms/\(Self.path(taxonomy))"
        )
        return data.object?["terms"]?.array?.compactMap { value -> TermLabel? in
            guard let object = value.object, let id = object["id"]?.string else { return nil }
            let label = object["label"]?.string ?? object["name"]?.string ?? object["slug"]?.string ?? id
            return TermLabel(id: id, label: label)
        } ?? []
    }

    func settings() async throws -> SiteSettings {
        let data = try await send("GET", "/settings")
        return SiteSettings(
            title: data.object?["title"]?.string ?? "",
            tagline: data.object?["tagline"]?.string ?? ""
        )
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

    func list(collection: CollectionDef) async throws -> [ContentSummary] {
        var cursor: String?
        var items: [ContentSummary] = []
        for _ in 0..<20 {
            var path = "/content/\(Self.path(collection.slug))?limit=100"
            if let cursor {
                let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cursor
                path += "&cursor=\(encoded)"
            }
            let data = try await send("GET", path)
            let page = data.object?["items"]?.array ?? []
            items.append(contentsOf: page.compactMap { Self.summary(from: $0, collection: collection) })
            guard let next = data.object?["nextCursor"]?.string, !next.isEmpty else { break }
            cursor = next
        }
        return items.sorted { $0.sortDate > $1.sortDate }
    }

    func load(collection: CollectionDef, id: String, knownPendingDraft: Bool = false) async throws -> LoadedEntry {
        if knownPendingDraft {
            async let payloadTask = send("GET", "/content/\(Self.path(collection.slug))/\(Self.path(id))")
            async let comparisonTask = send("GET", "/content/\(Self.path(collection.slug))/\(Self.path(id))/compare")
            let payload = try await payloadTask
            let comparison = try await comparisonTask
            return try Self.entry(from: payload, comparison: comparison, collection: collection)
        }
        let payload = try await send("GET", "/content/\(Self.path(collection.slug))/\(Self.path(id))")
        guard let item = payload.object?["item"]?.object, let draftID = item["draftRevisionId"]?.string, !draftID.isEmpty else {
            return try Self.entry(from: payload, comparison: nil, collection: collection)
        }
        let comparison = try await send("GET", "/content/\(Self.path(collection.slug))/\(Self.path(id))/compare")
        return try Self.entry(from: payload, comparison: comparison, collection: collection)
    }

    private static func entry(from payload: JSONValue, comparison: JSONValue?, collection: CollectionDef) throws -> LoadedEntry {
        guard var item = payload.object?["item"]?.object else {
            throw APIError(status: 500, code: "BAD_RESPONSE", message: "The site did not return that post.")
        }
        let rev = payload.object?["_rev"]?.string
        if let draftID = item["draftRevisionId"]?.string, !draftID.isEmpty,
           comparison?.object?["hasChanges"]?.boolish == true,
           let draft = comparison?.object?["draft"]?.object {
            item["data"] = .object(draft)
        }
        return loaded(item, rev: rev, collection: collection)
    }

    func create(collection: CollectionDef, title: String, body: String, excerpt: String, slug: String) async throws -> LoadedEntry {
        let bodyObject = await Self.writeBody(
            collection: collection,
            title: title.isEmpty ? "Untitled" : title,
            body: body,
            excerpt: excerpt,
            slug: slug,
            rev: nil,
            skipRevision: false
        )
        let created = try await send("POST", "/content/\(Self.path(collection.slug))", body: bodyObject)
        guard let item = created.object?["item"]?.object, let id = item["id"]?.string, !id.isEmpty else {
            throw APIError(status: 500, code: "BAD_RESPONSE", message: "The site did not return the new post.")
        }
        return Self.ack(item, explicitRev: created.object?["_rev"]?.string)
    }

    func update(
        collection: CollectionDef,
        id: String,
        rev: String?,
        title: String,
        body: String,
        excerpt: String,
        slug: String,
        skipRevision: Bool = false
    ) async throws -> LoadedEntry {
        let bodyObject = await Self.writeBody(
            collection: collection,
            title: title,
            body: body,
            excerpt: excerpt,
            slug: slug,
            rev: rev,
            skipRevision: skipRevision
        )
        let saved = try await send("PUT", "/content/\(Self.path(collection.slug))/\(Self.path(id))", body: bodyObject)
        guard let item = saved.object?["item"]?.object, let savedID = item["id"]?.string, !savedID.isEmpty else {
            return try await load(collection: collection, id: id)
        }
        return Self.ack(item, explicitRev: saved.object?["_rev"]?.string)
    }

    func publish(collection: CollectionDef, id: String) async throws -> LoadedEntry {
        let saved = try await send("POST", "/content/\(Self.path(collection.slug))/\(Self.path(id))/publish", body: .object([:]))
        guard let item = saved.object?["item"]?.object else {
            return try await load(collection: collection, id: id)
        }
        return Self.ack(item, explicitRev: saved.object?["_rev"]?.string)
    }

    func unpublish(collection: CollectionDef, id: String) async throws -> LoadedEntry {
        let saved = try await send("POST", "/content/\(Self.path(collection.slug))/\(Self.path(id))/unpublish", body: .object([:]))
        guard let item = saved.object?["item"]?.object else {
            return try await load(collection: collection, id: id)
        }
        return Self.ack(item, explicitRev: saved.object?["_rev"]?.string)
    }

    func discardDraft(collection: String, id: String) async throws {
        _ = try await send("POST", "/content/\(Self.path(collection))/\(Self.path(id))/discard-draft", body: .object([:]))
    }

    func trash(collection: String, id: String) async throws {
        _ = try await send("DELETE", "/content/\(Self.path(collection))/\(Self.path(id))")
    }

    private static func writeBody(
        collection: CollectionDef,
        title: String,
        body: String,
        excerpt: String,
        slug: String,
        rev: String?,
        skipRevision: Bool
    ) async -> JSONValue {
        await Task.detached(priority: .userInitiated) {
            var data: [String: JSONValue] = [:]
            if let field = collection.titleField {
                data[field.slug] = .string(title)
            }
            if let field = collection.bodyField {
                data[field.slug] = .string(body)
            }
            if let field = collection.excerptField {
                data[field.slug] = .string(excerpt)
            }
            let portable = PortableText.portableData(from: data, fields: collection.fields)
            var bodyObject: [String: JSONValue] = ["data": .object(portable)]
            let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                bodyObject["slug"] = .string(trimmed)
            }
            if let rev, !rev.isEmpty {
                bodyObject["_rev"] = .string(rev)
            }
            if skipRevision {
                bodyObject["skipRevision"] = .bool(true)
            }
            return JSONValue.object(bodyObject)
        }.value
    }

    private func send(_ method: String, _ path: String, body: JSONValue? = nil) async throws -> JSONValue {
        let span = Pace.begin("request")
        let result: JSONValue
        do {
            result = try await perform(method, path, body: body)
        } catch {
            Pace.end(span, detail: "\(method) \(path) failed")
            throw error
        }
        Pace.end(span, detail: "\(method) \(path)")
        return result
    }

    private func perform(_ method: String, _ path: String, body: JSONValue? = nil) async throws -> JSONValue {
        var request = URLRequest(url: SiteURL.endpoint(site: site, path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try body.data()
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = data.isEmpty ? JSONValue.object([:]) : (try? JSONDecoding.value(from: data))
        if !(200..<300).contains(status) {
            throw Self.failure(status: status, json: json)
        }
        guard let json else {
            throw APIError(status: status, code: "BAD_RESPONSE", message: "The site returned something that was not JSON.")
        }
        if json.object?["success"]?.boolish == false {
            throw Self.failure(status: status, json: json)
        }
        return json.object?["data"] ?? json
    }

    private static func failure(status: Int, json: JSONValue?) -> APIError {
        let code = json?.object?["error"]?.object?["code"]?.string ?? "HTTP_\(status)"
        let server = json?.object?["error"]?.object?["message"]?.string ?? "The site refused the request."
        let message: String
        switch code {
        case "CONFLICT":
            message = "This post changed on the site. Reload it, then save again."
        case "ENTRY_LOCKED":
            message = "Someone else is editing this post."
        case "UNAUTHORIZED", "INVALID_TOKEN":
            message = "The token was refused."
        case "FORBIDDEN":
            message = "This token cannot change that post."
        default:
            message = server
        }
        return APIError(status: status, code: code, message: message)
    }

    private static func path(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func collection(from value: JSONValue) -> CollectionDef? {
        guard let object = value.object, let slug = object["slug"]?.string else { return nil }
        let fields = object["fields"]?.array?.compactMap(field(from:)) ?? []
        return CollectionDef(
            slug: slug,
            label: object["label"]?.string ?? slug,
            labelSingular: object["labelSingular"]?.string ?? object["label"]?.string ?? slug,
            fields: fields.sorted { $0.sortOrder < $1.sortOrder }
        )
    }

    private static func field(from value: JSONValue) -> FieldDef? {
        guard let object = value.object, let slug = object["slug"]?.string, let type = object["type"]?.string else {
            return nil
        }
        return FieldDef(
            slug: slug,
            label: object["label"]?.string ?? slug,
            type: type,
            required: object["required"]?.boolish ?? false,
            sortOrder: Int(object["sortOrder"]?.number ?? 0)
        )
    }

    private static func summary(from value: JSONValue, collection: CollectionDef) -> ContentSummary? {
        guard let object = value.object, let id = object["id"]?.string else { return nil }
        let data = object["data"]?.object ?? [:]
        let titleKey = collection.titleField?.slug ?? "title"
        let title = data[titleKey]?.string ?? data["title"]?.string ?? object["slug"]?.string ?? "Untitled"
        return ContentSummary(
            id: id,
            slug: object["slug"]?.string ?? "",
            status: object["status"]?.string ?? "draft",
            title: title.isEmpty ? "Untitled" : title,
            updatedAt: Self.date(object["updatedAt"]?.string),
            publishedAt: Self.date(object["publishedAt"]?.string),
            hasPendingDraft: {
                if let draft = object["draftRevisionId"]?.string, !draft.isEmpty { return true }
                return false
            }()
        )
    }

    /// Identity and revision from a write response. The editor already has the text, so the body is not parsed again.
    private static func ack(_ item: [String: JSONValue], explicitRev: String?) -> LoadedEntry {
        LoadedEntry(
            id: item["id"]?.string ?? "",
            rev: Self.rev(item: item, explicit: explicitRev),
            slug: item["slug"]?.string ?? "",
            status: item["status"]?.string ?? "draft",
            title: "",
            body: "",
            excerpt: "",
            updatedAt: item["updatedAt"]?.string,
            publishedAt: item["publishedAt"]?.string,
            scheduledAt: item["scheduledAt"]?.string,
            draftRevisionID: item["draftRevisionId"]?.string
        )
    }

    /// EmDash `_rev` is standard base64 of `version:updatedAt` when the response omits the token.
    private static func rev(item: [String: JSONValue], explicit: String?) -> String? {
        if let explicit, !explicit.isEmpty { return explicit }
        guard let version = item["version"]?.number, let updated = item["updatedAt"]?.string else { return nil }
        return Data("\(Int(version)):\(updated)".utf8).base64EncodedString()
    }

    private static func loaded(_ item: [String: JSONValue], rev: String?, collection: CollectionDef) -> LoadedEntry {
        let raw = item["data"]?.object ?? [:]
        let data = PortableText.markdownData(from: raw, fields: collection.fields)
        let title: String
        if let field = collection.titleField {
            title = data[field.slug]?.string ?? ""
        } else {
            title = ""
        }
        let body: String
        if let field = collection.bodyField {
            body = WriterText.editorBody(data[field.slug]?.string ?? "")
        } else {
            body = ""
        }
        let excerpt = collection.excerptField.flatMap { data[$0.slug]?.string } ?? ""
        return LoadedEntry(
            id: item["id"]?.string ?? "",
            rev: rev,
            slug: item["slug"]?.string ?? "",
            status: item["status"]?.string ?? "draft",
            title: title,
            body: body,
            excerpt: excerpt,
            updatedAt: item["updatedAt"]?.string,
            publishedAt: item["publishedAt"]?.string,
            scheduledAt: item["scheduledAt"]?.string,
            draftRevisionID: item["draftRevisionId"]?.string
        )
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}

private extension JSONValue {
    var boolish: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .number(let value):
            return value != 0
        case .string(let value):
            return Bool(value)
        default:
            return nil
        }
    }
}
