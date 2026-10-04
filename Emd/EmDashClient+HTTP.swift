import Foundation

extension EmDashClient {
    func send(_ method: String, _ path: String, body: JSONValue? = nil) async throws -> JSONValue {
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

    func perform(_ method: String, _ path: String, body: JSONValue? = nil) async throws -> JSONValue {
        let (data, response) = try await session.data(for: request(method, path, body: body))
        return try Self.decoded(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    func request(_ method: String, _ path: String, body: JSONValue?) throws -> URLRequest {
        var request = URLRequest(url: SiteURL.endpoint(site: site, path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        try attach(body, to: &request)
        return request
    }

    func attach(_ body: JSONValue?, to request: inout URLRequest) throws {
        guard let body else { return }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try body.data()
    }

    static func decoded(_ data: Data, status: Int) throws -> JSONValue {
        let json = data.isEmpty ? JSONValue.object([:]) : (try? JSONDecoding.value(from: data))
        try reject(status: status, json: json)
        guard let json else {
            throw APIError(
                status: status, code: "BAD_RESPONSE", message: "The site returned something that was not JSON.")
        }
        return json.object?["data"] ?? json
    }

    static func reject(status: Int, json: JSONValue?) throws {
        if !(200..<300).contains(status) {
            throw failure(status: status, json: json)
        }
        if json?.object?["success"]?.boolish == false {
            throw failure(status: status, json: json)
        }
    }

    static func failure(status: Int, json: JSONValue?) -> APIError {
        let code = json?.object?["error"]?.object?["code"]?.string ?? "HTTP_\(status)"
        let server = json?.object?["error"]?.object?["message"]?.string ?? "The site refused the request."
        return APIError(status: status, code: code, message: messages[code] ?? server)
    }

    static let messages = [
        "CONFLICT": "This post changed on the site. Reload it, then save again.",
        "ENTRY_LOCKED": "Someone else is editing this post.",
        "UNAUTHORIZED": "The token was refused.",
        "INVALID_TOKEN": "The token was refused.",
        "FORBIDDEN": "This token cannot change that post.",
    ]

    static func path(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    static func taxonomy(from value: JSONValue) -> TaxonomyInfo? {
        guard let object = value.object, let name = object["name"]?.string else { return nil }
        let collections = object["collections"]?.array?.compactMap(\.string) ?? []
        return TaxonomyInfo(
            name: name, label: object["label"]?.string ?? name, collections: collections,
            labelSingular: object["labelSingular"]?.string ?? "")
    }

    static func term(from value: JSONValue) -> TermLabel? {
        guard let object = value.object, let id = object["id"]?.string else { return nil }
        return TermLabel(id: id, label: termLabel(object, id: id))
    }

    static func termLabel(_ object: [String: JSONValue], id: String) -> String {
        object["label"]?.string ?? object["name"]?.string ?? object["slug"]?.string ?? id
    }

    static func collection(from value: JSONValue) -> CollectionDef? {
        guard let object = value.object, let slug = object["slug"]?.string else { return nil }
        let fields = object["fields"]?.array?.compactMap(field(from:)) ?? []
        return CollectionDef(
            slug: slug,
            label: object["label"]?.string ?? slug,
            labelSingular: object["labelSingular"]?.string ?? object["label"]?.string ?? slug,
            fields: fields.sorted { $0.sortOrder < $1.sortOrder },
            supports: object["supports"]?.array?.compactMap(\.string) ?? ["drafts", "revisions"]
        )
    }

    static func field(from value: JSONValue) -> FieldDef? {
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

    static func summary(from value: JSONValue, collection: CollectionDef) -> ContentSummary? {
        guard let object = value.object, let id = object["id"]?.string else { return nil }
        let data = object["data"]?.object ?? [:]
        return ContentSummary(
            id: id,
            slug: object["slug"]?.string ?? "",
            status: object["status"]?.string ?? "draft",
            title: summaryTitle(data, object: object, collection: collection),
            updatedAt: date(object["updatedAt"]?.string),
            publishedAt: date(object["publishedAt"]?.string),
            hasPendingDraft: hasDraft(object)
        )
    }

    static func summaryTitle(
        _ data: [String: JSONValue],
        object: [String: JSONValue],
        collection: CollectionDef
    ) -> String {
        let titleKey = collection.titleField?.slug ?? "title"
        let title = data[titleKey]?.string ?? data["title"]?.string ?? object["slug"]?.string ?? "Untitled"
        guard !title.isEmpty else { return "Untitled" }
        return title
    }

    static func ack(_ item: [String: JSONValue], explicitRev: String?) -> LoadedEntry {
        LoadedEntry(
            id: item["id"]?.string ?? "",
            rev: rev(item: item, explicit: explicitRev),
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

    static func rev(item: [String: JSONValue], explicit: String?) -> String? {
        if let explicit, !explicit.isEmpty { return explicit }
        guard let version = item["version"]?.number, let updated = item["updatedAt"]?.string else { return nil }
        return Data("\(Int(version)):\(updated)".utf8).base64EncodedString()
    }

    static func loaded(_ item: [String: JSONValue], rev: String?, collection: CollectionDef) -> LoadedEntry {
        let raw = item["data"]?.object ?? [:]
        let data = PortableText.markdownData(from: raw, fields: collection.fields)
        return LoadedEntry(
            id: item["id"]?.string ?? "",
            rev: rev,
            slug: item["slug"]?.string ?? "",
            status: item["status"]?.string ?? "draft",
            title: text(data, field: collection.titleField),
            body: body(data, collection: collection),
            excerpt: collection.excerptField.flatMap { data[$0.slug]?.string } ?? "",
            updatedAt: item["updatedAt"]?.string,
            publishedAt: item["publishedAt"]?.string,
            scheduledAt: item["scheduledAt"]?.string,
            draftRevisionID: item["draftRevisionId"]?.string
        )
    }

    static func text(_ data: [String: JSONValue], field: FieldDef?) -> String {
        guard let field else { return "" }
        return data[field.slug]?.string ?? ""
    }

    /// The body field's Markdown, or every region under its marker for an entry written in several.
    static func body(_ data: [String: JSONValue], collection: CollectionDef) -> String {
        let regions = collection.regionFields
        guard !regions.isEmpty else { return editorText(data, field: collection.bodyField) }
        return Regions.joined(regions.map { ($0.slug, data[$0.slug]?.string ?? "") })
    }

    static func editorText(_ data: [String: JSONValue], field: FieldDef?) -> String {
        guard let field else { return "" }
        return WriterText.editorBody(data[field.slug]?.string ?? "")
    }

    static func date(_ value: String?) -> Date? {
        EditorDocument.date(value)
    }
}
