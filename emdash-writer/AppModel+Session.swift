import Foundation

extension AppModel {
    func restore() async {
        guard client == nil, let siteURL else {
            warming = false
            return
        }
        guard let token = KeychainStore.load(), !token.isEmpty else {
            warming = false
            return
        }
        await connect(site: siteURL.absoluteString, token: token, storeToken: false)
    }

    func connect(site: String, token: String, storeToken: Bool = true) async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = SiteURL.normalize(site) else {
            notice = "Enter the site address, like https://example.com."
            return
        }
        guard !trimmed.isEmpty else {
            notice = "Paste an API token from the EmDash admin."
            return
        }
        guard SiteURL.isSecure(url) else {
            notice = "Use an https address. Over http the token would travel unencrypted."
            return
        }
        busy = true
        notice = ""
        defer {
            busy = false
            warming = false
        }
        let next = EmDashClient(site: url, token: trimmed)
        do {
            let session = try await session(from: next)
            let request = ConnectRequest(client: next, url: url, token: trimmed, storeToken: storeToken)
            try applySession(session, request)
            await loadLibrary()
            await refreshOpenIfNeeded()
        } catch {
            noteConnectFailure(error, restoring: !storeToken)
        }
    }

    /// A launch that cannot reach the site keeps the cached library. A rejected token still goes to Connect.
    private func noteConnectFailure(_ error: Error, restoring: Bool) {
        guard restoring, Self.unreachable(error) else {
            report(error)
            return
        }
        offline = true
        notice = "Offline. Edits are kept on this Mac until the site is back."
        scheduleReconnect()
    }

    static func unreachable(_ error: Error) -> Bool {
        let codes: Set<URLError.Code> = [
            .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
            .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed,
        ]
        guard let url = error as? URLError else { return false }
        return codes.contains(url.code)
    }

    private func scheduleReconnect() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, self.offline, self.client == nil else { return }
            await self.restore()
        }
    }

    private func session(from client: EmDashClient) async throws -> SiteSession {
        async let settingsTask = client.settings()
        async let collectionsTask = client.collections()
        async let taxonomiesTask = client.taxonomies()
        let settings = try await settingsTask
        let found = try await collectionsTask
        let taxes = (try? await taxonomiesTask) ?? []
        let detailed = try await collections(found, using: client)
        return SiteSession(settings: settings, collections: detailed, taxonomies: taxes)
    }

    private func collections(_ found: [CollectionDef], using client: EmDashClient) async throws -> [CollectionDef] {
        guard needsDetail(found) else { return found }
        return try await detailed(found, using: client)
    }

    private func needsDetail(_ found: [CollectionDef]) -> Bool {
        found.contains { $0.fields.isEmpty } || found.allSatisfy(\.fields.isEmpty)
    }

    private func detailed(_ found: [CollectionDef], using client: EmDashClient) async throws -> [CollectionDef] {
        try await withThrowingTaskGroup(of: CollectionDef.self) { group in
            self.enqueue(found, using: client, group: &group)
            return try await self.gathered(&group)
        }
    }

    private func enqueue(
        _ found: [CollectionDef],
        using client: EmDashClient,
        group: inout ThrowingTaskGroup<CollectionDef, Error>
    ) {
        for item in found {
            group.addTask { try await client.collection(item.slug) }
        }
    }

    private func gathered(_ group: inout ThrowingTaskGroup<CollectionDef, Error>) async throws -> [CollectionDef] {
        var detailed: [CollectionDef] = []
        for try await item in group {
            detailed.append(item)
        }
        return detailed.sorted { left, right in
            left.label.localizedCaseInsensitiveCompare(right.label) == .orderedAscending
        }
    }

    private func applySession(_ session: SiteSession, _ request: ConnectRequest) throws {
        if request.storeToken {
            try KeychainStore.save(token: request.token)
        }
        if let current = siteURL?.host, current != request.url.host {
            leaveSite()
        }
        client = request.client
        siteURL = request.url
        offline = false
        siteTitle = titled(session.settings, host: request.url.host)
        tagline = session.settings.tagline
        collections = ordered(session.collections)
        taxonomies = session.taxonomies
        defaults.set(request.url.absoluteString, forKey: "siteURL")
        defaults.set(siteTitle, forKey: "siteTitle")
        keepCollection(session.collections)
        restoreJournaledDrafts()
    }

    private func titled(_ settings: SiteSettings, host: String?) -> String {
        guard settings.title.isEmpty else { return settings.title }
        return host ?? "Site"
    }

    private func ordered(_ collections: [CollectionDef]) -> [CollectionDef] {
        collections.sorted { left, right in
            if left.slug == "posts" { return true }
            if right.slug == "posts" { return false }
            return left.label.localizedCaseInsensitiveCompare(right.label) == .orderedAscending
        }
    }

    private func keepCollection(_ found: [CollectionDef]) {
        if !found.contains(where: { $0.slug == collectionSlug }) {
            collectionSlug = found.first { $0.slug == "posts" }?.slug ?? found.first?.slug ?? ""
        }
        defaults.set(collectionSlug, forKey: "collection")
    }

    private func refreshOpenIfNeeded() async {
        guard refreshAfterConnect, document?.remoteID != nil else { return }
        refreshAfterConnect = false
        await pullOpen()
    }

    func disconnect() {
        KeychainStore.clear()
        client = nil
        collections = []
        leaveSite()
        taxonomies = []
        siteTitle = ""
        tagline = ""
        notice = ""
        warming = false
        offline = false
        conflicted = false
    }

    func chooseCollection(_ slug: String) async {
        await saveUnlessLive()
        collectionSlug = slug
        defaults.set(slug, forKey: "collection")
        document = nil
        await loadLibrary()
    }

    func loadLibrary() async {
        guard let client, let collection else { return }
        let site = siteURL?.host ?? ""
        showCachedLibrary(site: site, slug: collection.slug)
        loadingLibrary = true
        defer { loadingLibrary = false }
        do {
            let detailed = try await resolved(collection, client: client)
            let span = Pace.begin("library")
            entries = try await client.list(collection: detailed)
            Pace.end(span, detail: "\(entries.count) posts")
            LocalStore.storeLibrary(site: site, collection: detailed.slug, entries: entries)
            notice = ""
        } catch {
            report(error)
        }
    }

    private func showCachedLibrary(site: String, slug: String) {
        guard entries.isEmpty, let cached = LocalStore.library(site: site, collection: slug), !cached.isEmpty else {
            return
        }
        entries = cached
    }

    private func resolved(_ collection: CollectionDef, client: EmDashClient) async throws -> CollectionDef {
        let detailed = try await filled(collection, client: client)
        if let index = collections.firstIndex(where: { $0.slug == detailed.slug }) {
            collections[index] = detailed
        }
        return detailed
    }

    private func filled(_ collection: CollectionDef, client: EmDashClient) async throws -> CollectionDef {
        guard collection.fields.isEmpty else { return collection }
        return try await client.collection(collection.slug)
    }

    func report(_ error: Error) {
        guard cancelled(error) else {
            notice = error.localizedDescription
            return
        }
        clearCancelledNotice()
    }

    private func clearCancelledNotice() {
        guard
            notice.caseInsensitiveCompare("cancelled") == .orderedSame
                || notice.caseInsensitiveCompare("canceled") == .orderedSame
        else { return }
        notice = ""
    }

    private func cancelled(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        if cocoaCancelled(error) { return true }
        return describedCancel(error)
    }

    private func cocoaCancelled(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
        return ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError
    }

    private func describedCancel(_ error: Error) -> Bool {
        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.caseInsensitiveCompare("cancelled") == .orderedSame
            || text.caseInsensitiveCompare("canceled") == .orderedSame
    }
}

private struct SiteSession {
    var settings: SiteSettings
    var collections: [CollectionDef]
    var taxonomies: [TaxonomyInfo]
}

private struct ConnectRequest {
    var client: EmDashClient
    var url: URL
    var token: String
    var storeToken = true
}
