import Foundation

extension EmDashClient {
    func list(collection: CollectionDef) async throws -> [ContentSummary] {
        var fetch = ListFetch()
        while fetch.more {
            fetch = try await nextPage(collection, fetch)
        }
        return fetch.items.sorted { $0.sortDate > $1.sortDate }
    }

    func load(collection: CollectionDef, id: String, knownPendingDraft: Bool = false) async throws -> LoadedEntry {
        if knownPendingDraft {
            return try await loadCompared(collection, id: id)
        }
        return try await loadIfDraft(collection, id: id)
    }

    func create(collection: CollectionDef, draft: DraftWrite) async throws -> LoadedEntry {
        let created = try await send(
            "POST",
            "/content/\(Self.path(collection.slug))",
            body: await Self.writeBody(collection: collection, draft: Self.titled(draft))
        )
        return try Self.created(created)
    }

    func update(collection: CollectionDef, id: String, draft: DraftWrite) async throws -> LoadedEntry {
        let saved = try await send(
            "PUT",
            "/content/\(Self.path(collection.slug))/\(Self.path(id))",
            body: await Self.writeBody(collection: collection, draft: draft)
        )
        return try await stored(saved, collection: collection, id: id)
    }

    func publish(collection: CollectionDef, id: String) async throws -> LoadedEntry {
        try await postAction("publish", collection: collection, id: id)
    }

    /// Publishes the saved draft at `date`. The site refuses times that have passed.
    func schedule(collection: CollectionDef, id: String, at date: Date) async throws -> LoadedEntry {
        let at = date.formatted(.iso8601)
        let saved = try await send(
            "POST", "/content/\(Self.path(collection.slug))/\(Self.path(id))/schedule",
            body: .object(["scheduledAt": .string(at)]))
        return try await stored(saved, collection: collection, id: id)
    }

    func unschedule(collection: CollectionDef, id: String) async throws -> LoadedEntry {
        let saved = try await send("DELETE", "/content/\(Self.path(collection.slug))/\(Self.path(id))/schedule")
        return try await stored(saved, collection: collection, id: id)
    }

    func unpublish(collection: CollectionDef, id: String) async throws -> LoadedEntry {
        try await postAction("unpublish", collection: collection, id: id)
    }

    func discardDraft(collection: String, id: String) async throws {
        _ = try await send(
            "POST", "/content/\(Self.path(collection))/\(Self.path(id))/discard-draft", body: .object([:]))
    }

    func trash(collection: String, id: String) async throws {
        _ = try await send("DELETE", "/content/\(Self.path(collection))/\(Self.path(id))")
    }

    fileprivate struct ListFetch {
        var items: [ContentSummary] = []
        var cursor: String?
        var more = true
        var pages = 0
    }

    fileprivate func nextPage(_ collection: CollectionDef, _ fetch: ListFetch) async throws -> ListFetch {
        let data = try await send("GET", pagePath(collection, cursor: fetch.cursor))
        let page = data.object?["items"]?.array ?? []
        var copy = fetch
        copy.pages += 1
        copy.items.append(contentsOf: page.compactMap { Self.summary(from: $0, collection: collection) })
        copy.cursor = data.object?["nextCursor"]?.string
        copy.more = Self.continues(copy)
        return copy
    }

    fileprivate func pagePath(_ collection: CollectionDef, cursor: String?) -> String {
        var path = "/content/\(Self.path(collection.slug))?limit=100"
        guard let cursor, !cursor.isEmpty else { return path }
        // Cursors are base64, and a bare `+` in a query reads as a space.
        let unreserved = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encoded = cursor.addingPercentEncoding(withAllowedCharacters: unreserved) ?? cursor
        path += "&cursor=\(encoded)"
        return path
    }

    fileprivate static func continues(_ fetch: ListFetch) -> Bool {
        guard fetch.pages < 20, let cursor = fetch.cursor, !cursor.isEmpty else { return false }
        return true
    }

    fileprivate func loadCompared(_ collection: CollectionDef, id: String) async throws -> LoadedEntry {
        async let payloadTask = send("GET", "/content/\(Self.path(collection.slug))/\(Self.path(id))")
        async let comparisonTask = send("GET", "/content/\(Self.path(collection.slug))/\(Self.path(id))/compare")
        let payload = try await payloadTask
        let comparison = try await comparisonTask
        return try Self.entry(from: payload, comparison: comparison, collection: collection)
    }

    fileprivate func loadIfDraft(_ collection: CollectionDef, id: String) async throws -> LoadedEntry {
        let payload = try await send("GET", "/content/\(Self.path(collection.slug))/\(Self.path(id))")
        guard let item = payload.object?["item"]?.object, Self.hasDraft(item) else {
            return try Self.entry(from: payload, comparison: nil, collection: collection)
        }
        let comparison = try await send("GET", "/content/\(Self.path(collection.slug))/\(Self.path(id))/compare")
        return try Self.entry(from: payload, comparison: comparison, collection: collection)
    }

    static func hasDraft(_ item: [String: JSONValue]) -> Bool {
        guard let draftID = item["draftRevisionId"]?.string else { return false }
        return !draftID.isEmpty
    }

    fileprivate static func entry(from payload: JSONValue, comparison: JSONValue?, collection: CollectionDef) throws
        -> LoadedEntry
    {
        guard var item = payload.object?["item"]?.object else {
            throw APIError(status: 500, code: "BAD_RESPONSE", message: "The site did not return that post.")
        }
        item = withDraft(item, comparison: comparison)
        return loaded(item, rev: payload.object?["_rev"]?.string, collection: collection)
    }

    fileprivate static func withDraft(_ item: [String: JSONValue], comparison: JSONValue?) -> [String: JSONValue] {
        guard hasDraft(item), comparison?.object?["hasChanges"]?.boolish == true,
            let draft = comparison?.object?["draft"]?.object
        else { return item }
        var copy = item
        copy["data"] = .object(draft)
        return copy
    }

    fileprivate static func titled(_ draft: DraftWrite) -> DraftWrite {
        guard draft.text.title.isEmpty else { return draft }
        var copy = draft
        copy.text.title = "Untitled"
        return copy
    }

    fileprivate static func created(_ created: JSONValue) throws -> LoadedEntry {
        guard let item = created.object?["item"]?.object, let id = item["id"]?.string, !id.isEmpty else {
            throw APIError(status: 500, code: "BAD_RESPONSE", message: "The site did not return the new post.")
        }
        return ack(item, explicitRev: created.object?["_rev"]?.string)
    }

    fileprivate func stored(_ saved: JSONValue, collection: CollectionDef, id: String) async throws -> LoadedEntry {
        guard let item = saved.object?["item"]?.object, let savedID = item["id"]?.string, !savedID.isEmpty else {
            return try await load(collection: collection, id: id)
        }
        return Self.ack(item, explicitRev: saved.object?["_rev"]?.string)
    }

    fileprivate func postAction(_ action: String, collection: CollectionDef, id: String) async throws -> LoadedEntry {
        let saved = try await send(
            "POST",
            "/content/\(Self.path(collection.slug))/\(Self.path(id))/\(action)",
            body: .object([:])
        )
        return try await stored(saved, collection: collection, id: id)
    }

    fileprivate static func writeBody(collection: CollectionDef, draft: DraftWrite) async -> JSONValue {
        await Task.detached(priority: .userInitiated) {
            payload(collection: collection, draft: draft)
        }.value
    }

    fileprivate static func payload(collection: CollectionDef, draft: DraftWrite) -> JSONValue {
        let data = fieldData(collection, draft)
        return envelope(PortableText.portableData(from: data, fields: collection.fields), draft: draft)
    }

    fileprivate static func fieldData(_ collection: CollectionDef, _ draft: DraftWrite) -> [String: JSONValue] {
        var data: [String: JSONValue] = [:]
        assign(&data, collection.titleField, draft.text.title)
        if draft.sendsBody {
            assign(&data, collection.bodyField, draft.text.body)
        }
        assign(&data, collection.excerptField, draft.text.excerpt)
        return data
    }

    fileprivate static func assign(_ data: inout [String: JSONValue], _ field: FieldDef?, _ value: String) {
        guard let field else { return }
        data[field.slug] = .string(value)
    }

    fileprivate static func envelope(_ portable: [String: JSONValue], draft: DraftWrite) -> JSONValue {
        var body: [String: JSONValue] = ["data": .object(portable)]
        putSlug(&body, draft.text.slug)
        putRev(&body, draft.rev)
        putSkip(&body, draft.skipRevision)
        return .object(body)
    }

    fileprivate static func putSlug(_ body: inout [String: JSONValue], _ slug: String) {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        body["slug"] = .string(trimmed)
    }

    fileprivate static func putRev(_ body: inout [String: JSONValue], _ rev: String?) {
        guard let rev, !rev.isEmpty else { return }
        body["_rev"] = .string(rev)
    }

    fileprivate static func putSkip(_ body: inout [String: JSONValue], _ skip: Bool) {
        guard skip else { return }
        body["skipRevision"] = .bool(true)
    }
}
