import AppKit
import Foundation
import Observation

struct TermGroup: Equatable, Identifiable {
    var label: String
    var value: String

    var id: String { label }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case drafts
    case live

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .drafts: "Drafts"
        case .live: "Published"
        }
    }
}

@Observable
@MainActor
final class EditorDocument {
    let localID: String
    let openedAt = Date()
    var remoteID: String?
    var rev: String?
    var slug = "" { didSet { mark() } }
    var status = "draft"
    var title = "" { didSet { mark() } }
    var body = "" { didSet { mark() } }
    var excerpt = "" { didSet { mark() } }
    var updatedAt: Date?
    var publishedAt: String?
    var scheduledAt: String?
    var draftRevisionID: String?
    var termGroups: [TermGroup] = []
    var dirty = false
    var loaded = false
    private var suppress = false

    private func mark() {
        if !suppress {
            dirty = true
        }
    }

    var id: String { remoteID ?? localID }

    init(localID: String = "local-\(UUID().uuidString)") {
        self.localID = localID
    }

    func apply(_ entry: LoadedEntry) {
        suppress = true
        remoteID = entry.id
        rev = entry.rev
        slug = entry.slug
        status = entry.status
        title = entry.title
        body = entry.body
        excerpt = entry.excerpt
        updatedAt = EditorDocument.date(entry.updatedAt)
        publishedAt = entry.publishedAt
        scheduledAt = entry.scheduledAt
        draftRevisionID = entry.draftRevisionID
        termGroups = []
        dirty = false
        loaded = true
        suppress = false
    }

    func seed(title: String, slug: String, status: String) {
        suppress = true
        self.title = title
        self.slug = slug
        self.status = status
        dirty = false
        loaded = false
        suppress = false
    }

    func noteSaved(_ entry: LoadedEntry, sentTitle: String, sentBody: String) {
        suppress = true
        remoteID = entry.id
        rev = entry.rev
        status = entry.status
        publishedAt = entry.publishedAt
        scheduledAt = entry.scheduledAt
        draftRevisionID = entry.draftRevisionID
        updatedAt = EditorDocument.date(entry.updatedAt)
        if slug.isEmpty {
            slug = entry.slug
        }
        dirty = title != sentTitle || body != sentBody
        loaded = true
        suppress = false
    }

    var publishedLabel: String {
        guard let publishedAt, let date = EditorDocument.date(publishedAt) else {
            return "Not published"
        }
        return date.formatted(date: .long, time: .omitted)
    }

    var listTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    var statusLine: String {
        var parts: [String] = []
        switch status {
        case "published":
            parts.append(draftRevisionID == nil ? "Published" : "Published, draft waiting")
        case "scheduled":
            parts.append("Scheduled")
        default:
            parts.append("Draft")
        }
        if dirty {
            parts.append("unsaved")
        }
        return parts.joined(separator: " · ")
    }

    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}

@Observable
@MainActor
final class AppModel {
    var siteURL: URL?
    var siteTitle = ""
    var tagline = ""
    var collections: [CollectionDef] = []
    var collectionSlug = ""
    var entries: [ContentSummary] = []
    var document: EditorDocument?
    var query = ""
    var filter: LibraryFilter = .all
    var appearance: AppearanceChoice
    var fontChoice: WriterFont
    var fontSize: Double
    var focusMode: Bool {
        didSet { defaults.set(focusMode, forKey: "focus") }
    }
    var typewriter: Bool {
        didSet { defaults.set(typewriter, forKey: "typewriter") }
    }
    var showInspector: Bool {
        didSet { defaults.set(showInspector, forKey: "inspector") }
    }
    var taxonomies: [TaxonomyInfo] = []
    var busy = false
    /// Cached posts are on screen while the site is still connecting.
    var warming = false
    var loadingLibrary = false
    var notice = ""
    var confirmTrash = false

    private var client: EmDashClient?
    private var drafts: [EditorDocument] = []
    private var openToken = 0
    private var autosaveTask: Task<Void, Never>?
    private var lastEdit = Date.distantPast
    private var saveGeneration = 0
    private var saveChain: Task<Void, Never>?
    private var saving = false
    private var creatingLocalIDs: Set<String> = []
    private var loads: [String: Task<LoadedEntry, Error>] = [:]
    private var prefetchTask: Task<Void, Never>?
    private var refreshAfterConnect = false
    var applyingRemote = false
    private let defaults = UserDefaults.standard

    init() {
        appearance = AppearanceChoice(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
        fontChoice = WriterFont(rawValue: UserDefaults.standard.string(forKey: "font") ?? "") ?? .geistSans
        let storedSize = UserDefaults.standard.double(forKey: "fontSize")
        fontSize = storedSize == 0 || storedSize >= 20 ? 15 : min(24, max(13, storedSize))
        focusMode = UserDefaults.standard.bool(forKey: "focus")
        typewriter = UserDefaults.standard.bool(forKey: "typewriter")
        if UserDefaults.standard.object(forKey: "inspector") == nil {
            showInspector = true
        } else {
            showInspector = UserDefaults.standard.bool(forKey: "inspector")
        }
        collectionSlug = UserDefaults.standard.string(forKey: "collection") ?? "posts"
        if let raw = UserDefaults.standard.string(forKey: "siteURL") {
            siteURL = SiteURL.normalize(raw)
        }
        siteTitle = UserDefaults.standard.string(forKey: "siteTitle") ?? ""
        if let host = siteURL?.host,
           let cached = LocalStore.library(site: host, collection: collectionSlug),
           !cached.isEmpty {
            entries = cached
            warming = true
        }
    }

    var collection: CollectionDef? {
        collections.first { $0.slug == collectionSlug } ?? collections.first { $0.slug == "posts" } ?? collections.first
    }

    var isConnected: Bool { client != nil && siteURL != nil }

    var visibleEntries: [ContentSummary] {
        let locals: [ContentSummary] = drafts.map { draft in
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
        let remote = entries.map { entry -> ContentSummary in
            guard let document, document.remoteID == entry.id else { return entry }
            var copy = entry
            copy.title = document.listTitle
            copy.slug = document.slug
            copy.status = document.status
            copy.hasPendingDraft = document.draftRevisionID != nil
            return copy
        }
        return (locals + remote).filter { entry in
            switch filter {
            case .all:
                break
            case .drafts:
                if entry.status != "draft" && entry.status != "scheduled" && !entry.hasPendingDraft { return false }
            case .live:
                if entry.status != "published" { return false }
            }
            let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !needle.isEmpty && !entry.title.lowercased().contains(needle) && !entry.slug.lowercased().contains(needle) {
                return false
            }
            return true
        }
        .sorted { $0.sortDate > $1.sortDate }
    }

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
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = SiteURL.normalize(site) else {
            notice = "Enter the site address, like https://example.com."
            return
        }
        guard !trimmedToken.isEmpty else {
            notice = "Paste an API token from the EmDash admin."
            return
        }
        busy = true
        notice = ""
        defer {
            busy = false
            warming = false
        }
        let next = EmDashClient(site: url, token: trimmedToken)
        do {
            async let settingsTask = next.settings()
            async let collectionsTask = next.collections()
            async let taxonomiesTask = next.taxonomies()
            let settings = try await settingsTask
            var found = try await collectionsTask
            let taxes = (try? await taxonomiesTask) ?? []
            if found.contains(where: { $0.fields.isEmpty }) || found.allSatisfy(\.fields.isEmpty) {
                found = try await withThrowingTaskGroup(of: CollectionDef.self) { group in
                    for item in found {
                        group.addTask { try await next.collection(item.slug) }
                    }
                    var detailed: [CollectionDef] = []
                    for try await item in group {
                        detailed.append(item)
                    }
                    return detailed.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
                }
            }
            if storeToken {
                try KeychainStore.save(token: trimmedToken)
            }
            client = next
            siteURL = url
            siteTitle = settings.title.isEmpty ? (url.host ?? "Site") : settings.title
            tagline = settings.tagline
            collections = Self.ordered(found)
            taxonomies = taxes
            defaults.set(url.absoluteString, forKey: "siteURL")
            defaults.set(siteTitle, forKey: "siteTitle")
            if !found.contains(where: { $0.slug == collectionSlug }) {
                collectionSlug = found.first { $0.slug == "posts" }?.slug ?? found.first?.slug ?? ""
            }
            defaults.set(collectionSlug, forKey: "collection")
            await loadLibrary()
            if refreshAfterConnect, document?.remoteID != nil {
                refreshAfterConnect = false
                await pullOpen()
            }
        } catch {
            report(error)
        }
    }

    func disconnect() {
        KeychainStore.clear()
        client = nil
        collections = []
        entries = []
        drafts = []
        document = nil
        taxonomies = []
        siteTitle = ""
        tagline = ""
        notice = ""
        warming = false
    }

    func chooseCollection(_ slug: String) async {
        collectionSlug = slug
        defaults.set(slug, forKey: "collection")
        document = nil
        await loadLibrary()
    }

    func loadLibrary() async {
        guard let client, let collection else { return }
        let site = siteURL?.host ?? ""
        if entries.isEmpty, let cached = LocalStore.library(site: site, collection: collection.slug), !cached.isEmpty {
            entries = cached
        }
        loadingLibrary = true
        defer { loadingLibrary = false }
        do {
            let detailed = collection.fields.isEmpty ? try await client.collection(collection.slug) : collection
            if let index = collections.firstIndex(where: { $0.slug == detailed.slug }) {
                collections[index] = detailed
            }
            let span = Pace.begin("library")
            entries = try await client.list(collection: detailed)
            Pace.end(span, detail: "\(entries.count) posts")
            LocalStore.storeLibrary(site: site, collection: detailed.slug, entries: entries)
            notice = ""
        } catch {
            report(error)
        }
    }

    func open(_ id: String) async {
        if document?.id == id { return }
        if let local = drafts.first(where: { $0.id == id }) {
            document = local
            return
        }
        openToken += 1
        let token = openToken
        if id.hasPrefix("local-") {
            return
        }
        let placeholder = EditorDocument()
        placeholder.remoteID = id
        if let summary = entries.first(where: { $0.id == id }) {
            placeholder.seed(title: summary.title, slug: summary.slug, status: summary.status)
        } else {
            placeholder.loaded = false
        }
        let site = siteURL?.host ?? ""
        var baselineTitle = ""
        var baselineBody = ""
        if let cached = LocalStore.entry(site: site, id: id) {
            applyingRemote = true
            placeholder.apply(cached)
            applyingRemote = false
            baselineTitle = cached.title
            baselineBody = cached.body
        }
        document = placeholder
        guard client != nil, collection != nil else {
            refreshAfterConnect = true
            return
        }
        do {
            let span = Pace.begin("open")
            let loaded = try await fetchEntry(id: id)
            Pace.end(span, detail: id)
            guard token == openToken, document?.localID == placeholder.localID else { return }
            if placeholder.dirty {
                if loaded.title == baselineTitle && loaded.body == baselineBody {
                    placeholder.rev = loaded.rev
                    placeholder.status = loaded.status
                    placeholder.publishedAt = loaded.publishedAt
                    placeholder.scheduledAt = loaded.scheduledAt
                    placeholder.draftRevisionID = loaded.draftRevisionID
                } else {
                    notice = "This post also changed on the site. Reload to see that version."
                }
            } else {
                applyingRemote = true
                placeholder.apply(loaded)
                applyingRemote = false
                remember(loaded)
            }
            await refreshTerms(for: placeholder)
        } catch {
            guard token == openToken else { return }
            if !placeholder.loaded {
                report(error)
            }
        }
    }

    func prefetch(_ id: String) {
        guard !id.hasPrefix("local-"), id != document?.remoteID, client != nil else { return }
        let site = siteURL?.host ?? ""
        if LocalStore.entry(site: site, id: id) != nil { return }
        prefetchTask?.cancel()
        prefetchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            guard let loaded = try? await fetchEntry(id: id) else { return }
            remember(loaded)
        }
    }

    private func pullOpen() async {
        guard let id = document?.remoteID else { return }
        openToken += 1
        let token = openToken
        let placeholder = document
        let baselineTitle = placeholder?.title ?? ""
        let baselineBody = placeholder?.body ?? ""
        do {
            let loaded = try await fetchEntry(id: id)
            guard token == openToken, let placeholder, placeholder.remoteID == id else { return }
            if placeholder.dirty {
                if loaded.title != baselineTitle || loaded.body != baselineBody {
                    notice = "This post also changed on the site. Reload to see that version."
                } else {
                    placeholder.rev = loaded.rev
                    placeholder.status = loaded.status
                    placeholder.publishedAt = loaded.publishedAt
                    placeholder.scheduledAt = loaded.scheduledAt
                    placeholder.draftRevisionID = loaded.draftRevisionID
                }
            } else {
                applyingRemote = true
                placeholder.apply(loaded)
                applyingRemote = false
                remember(loaded)
            }
        } catch {
            if placeholder?.loaded != true {
                report(error)
            }
        }
    }

    private func fetchEntry(id: String) async throws -> LoadedEntry {
        if let existing = loads[id] {
            return try await existing.value
        }
        guard let client, let collection else {
            throw APIError(status: 0, code: "OFFLINE", message: "Not connected.")
        }
        let pending = entries.first { $0.id == id }?.hasPendingDraft == true
        let task = Task { @MainActor in
            try await client.load(collection: collection, id: id, knownPendingDraft: pending)
        }
        loads[id] = task
        do {
            let loaded = try await task.value
            loads[id] = nil
            return loaded
        } catch {
            loads[id] = nil
            throw error
        }
    }

    func newPost() {
        let draft = EditorDocument()
        draft.loaded = true
        draft.status = "draft"
        drafts.insert(draft, at: 0)
        document = draft
    }

    func scheduleAutosave() {
        guard !applyingRemote, let document, document.dirty else { return }
        let hasText = !document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !document.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasText else { return }
        lastEdit = Date()
        guard autosaveTask == nil else { return }
        autosaveTask = Task { @MainActor in
            defer { autosaveTask = nil }
            while !Task.isCancelled {
                let remaining = lastEdit.addingTimeInterval(2.5).timeIntervalSinceNow
                if remaining > 0.05 {
                    try? await Task.sleep(for: .milliseconds(Int(remaining * 1000)))
                    continue
                }
                guard self.document?.dirty == true else { break }
                await enqueueSave(publishIfLive: true, skipRevision: true)
                if self.document?.dirty != true { break }
                lastEdit = Date()
            }
        }
    }

    func save() async {
        lastEdit = .distantPast
        await enqueueSave(publishIfLive: true, skipRevision: false)
    }

    private func enqueueSave(publishIfLive: Bool, skipRevision: Bool) async {
        let previous = saveChain
        let next = Task { @MainActor in
            await previous?.value
            await self.performSave(publishIfLive: publishIfLive, skipRevision: skipRevision)
        }
        saveChain = next
        await next.value
    }

    private func performSave(publishIfLive: Bool, skipRevision: Bool) async {
        guard !busy, !saving, let document, let client, let collection, document.dirty else { return }
        let sentTitle = document.title
        let sentBody = document.body
        let sentExcerpt = document.excerpt
        let sentSlug = document.slug
        let wasNew = document.remoteID == nil
        let keepLive = publishIfLive && document.status == "published"
        let localID = document.localID
        if wasNew {
            if creatingLocalIDs.contains(localID) { return }
            creatingLocalIDs.insert(localID)
        }
        saveGeneration += 1
        let generation = saveGeneration
        saving = true
        notice = ""
        let span = Pace.begin("save")
        defer {
            saving = false
            creatingLocalIDs.remove(localID)
            Pace.end(span, detail: keepLive ? "live" : "draft")
        }
        do {
            let saved: LoadedEntry
            if let remoteID = document.remoteID, !remoteID.isEmpty {
                saved = try await client.update(
                    collection: collection,
                    id: remoteID,
                    rev: document.rev,
                    title: sentTitle,
                    body: sentBody,
                    excerpt: sentExcerpt,
                    slug: sentSlug,
                    skipRevision: skipRevision
                )
            } else {
                saved = try await client.create(
                    collection: collection,
                    title: sentTitle,
                    body: sentBody,
                    excerpt: sentExcerpt,
                    slug: sentSlug
                )
                document.remoteID = saved.id
                document.rev = saved.rev
            }
            guard generation == saveGeneration else { return }
            applyingRemote = true
            drafts.removeAll { $0.localID == localID }
            document.noteSaved(saved, sentTitle: sentTitle, sentBody: sentBody)
            applyingRemote = false
            if keepLive, let remoteID = document.remoteID {
                let live = try await client.publish(collection: collection, id: remoteID)
                guard generation == saveGeneration else { return }
                applyingRemote = true
                document.noteSaved(live, sentTitle: sentTitle, sentBody: sentBody)
                applyingRemote = false
            }
            rememberOpen()
            if wasNew, let remoteID = document.remoteID {
                let summary = ContentSummary(
                    id: remoteID,
                    slug: document.slug,
                    status: document.status,
                    title: document.listTitle,
                    updatedAt: Date(),
                    publishedAt: EditorDocument.date(document.publishedAt),
                    hasPendingDraft: document.draftRevisionID != nil
                )
                entries.removeAll { $0.id == remoteID }
                entries.insert(summary, at: 0)
                if let site = siteURL?.host {
                    LocalStore.storeLibrary(site: site, collection: collection.slug, entries: entries)
                }
            } else if let remoteID = document.remoteID, let index = entries.firstIndex(where: { $0.id == remoteID }) {
                entries[index].title = document.listTitle
                entries[index].status = document.status
                entries[index].updatedAt = Date()
                entries[index].publishedAt = EditorDocument.date(document.publishedAt)
            }
        } catch {
            report(error)
        }
    }

    func setLive(_ live: Bool) async {
        lastEdit = .distantPast
        await enqueueSave(publishIfLive: false, skipRevision: false)
        guard notice.isEmpty else { return }
        if live {
            await publish()
        } else {
            await unpublish()
        }
    }

    func publish() async {
        guard let document else { return }
        if document.dirty || document.remoteID == nil {
            await enqueueSave(publishIfLive: false, skipRevision: false)
        } else {
            await saveChain?.value
        }
        guard notice.isEmpty, let remoteID = document.remoteID, let client, let collection else { return }
        busy = true
        defer { busy = false }
        do {
            let loaded = try await client.publish(collection: collection, id: remoteID)
            applyingRemote = true
            document.noteSaved(loaded, sentTitle: document.title, sentBody: document.body)
            applyingRemote = false
            rememberOpen()
            await refreshTerms(for: document)
            await loadLibrary()
        } catch {
            report(error)
        }
    }

    func unpublish() async {
        guard let document, let remoteID = document.remoteID, let client, let collection else { return }
        await saveChain?.value
        busy = true
        defer { busy = false }
        do {
            let loaded = try await client.unpublish(collection: collection, id: remoteID)
            applyingRemote = true
            document.noteSaved(loaded, sentTitle: document.title, sentBody: document.body)
            applyingRemote = false
            rememberOpen()
            await refreshTerms(for: document)
            await loadLibrary()
        } catch {
            report(error)
        }
    }

    func discardDraft() async {
        guard let document, let remoteID = document.remoteID, let client, let collection else { return }
        busy = true
        defer { busy = false }
        do {
            try await client.discardDraft(collection: collection.slug, id: remoteID)
            document.apply(try await client.load(collection: collection, id: remoteID))
            await refreshTerms(for: document)
            await loadLibrary()
        } catch {
            report(error)
        }
    }

    func trash() async {
        guard let document else { return }
        if document.remoteID == nil {
            drafts.removeAll { $0.localID == document.localID }
            self.document = nil
            return
        }
        guard let remoteID = document.remoteID, let client, let collection else { return }
        busy = true
        defer { busy = false }
        do {
            try await client.trash(collection: collection.slug, id: remoteID)
            self.document = nil
            await loadLibrary()
        } catch {
            report(error)
        }
    }

    func reloadOpen() async {
        guard let document, let remoteID = document.remoteID, let client, let collection else {
            await loadLibrary()
            return
        }
        do {
            document.apply(try await client.load(collection: collection, id: remoteID))
            await refreshTerms(for: document)
            await loadLibrary()
            notice = ""
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        if Self.cancelled(error) {
            if notice.caseInsensitiveCompare("cancelled") == .orderedSame
                || notice.caseInsensitiveCompare("canceled") == .orderedSame {
                notice = ""
            }
            return
        }
        notice = error.localizedDescription
    }

    private static func cancelled(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
        if ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError { return true }
        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.caseInsensitiveCompare("cancelled") == .orderedSame
            || text.caseInsensitiveCompare("canceled") == .orderedSame
    }

    func setAppearance(_ choice: AppearanceChoice) {
        appearance = choice
        defaults.set(choice.rawValue, forKey: "appearance")
    }

    func setFont(_ choice: WriterFont) {
        fontChoice = choice
        defaults.set(choice.rawValue, forKey: "font")
    }

    func setFontSize(_ size: Double) {
        fontSize = min(24, max(13, size))
        defaults.set(fontSize, forKey: "fontSize")
    }

    func setFocus(_ enabled: Bool) {
        focusMode = enabled
        defaults.set(enabled, forKey: "focus")
    }

    func setTypewriter(_ enabled: Bool) {
        typewriter = enabled
        defaults.set(enabled, forKey: "typewriter")
    }

    func setInspector(_ shown: Bool) {
        showInspector = shown
        defaults.set(shown, forKey: "inspector")
    }

    var applicableTaxonomies: [TaxonomyInfo] {
        guard let collection else { return [] }
        return taxonomies.filter { $0.collections.isEmpty || $0.collections.contains(collection.slug) }
    }

    private func remember(_ entry: LoadedEntry) {
        guard let site = siteURL?.host, !entry.id.isEmpty else { return }
        LocalStore.storeEntry(site: site, entry: entry)
    }

    private func rememberOpen() {
        guard let document, let remoteID = document.remoteID else { return }
        remember(LoadedEntry(
            id: remoteID,
            rev: document.rev,
            slug: document.slug,
            status: document.status,
            title: document.title,
            body: document.body,
            excerpt: document.excerpt,
            updatedAt: nil,
            publishedAt: document.publishedAt,
            scheduledAt: document.scheduledAt,
            draftRevisionID: document.draftRevisionID
        ))
    }

    private func refreshTerms(for document: EditorDocument) async {
        guard let client, let collection, let remoteID = document.remoteID else {
            document.termGroups = []
            return
        }
        let applicable = taxonomies.filter { $0.collections.isEmpty || $0.collections.contains(collection.slug) }
        let slug = collection.slug
        let groups = await withTaskGroup(of: (Int, TermGroup).self) { group in
            for (index, taxonomy) in applicable.enumerated() {
                group.addTask {
                    let labels = (try? await client.terms(collection: slug, id: remoteID, taxonomy: taxonomy.name)) ?? []
                    let term = TermGroup(label: taxonomy.label, value: labels.map(\.label).joined(separator: ", "))
                    return (index, term)
                }
            }
            var collected: [(Int, TermGroup)] = []
            for await item in group {
                collected.append(item)
            }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
        guard document.remoteID == remoteID else { return }
        document.termGroups = groups
    }

    private static func ordered(_ collections: [CollectionDef]) -> [CollectionDef] {
        collections.sorted { left, right in
            if left.slug == "posts" { return true }
            if right.slug == "posts" { return false }
            return left.label.localizedCaseInsensitiveCompare(right.label) == .orderedAscending
        }
    }

    func openSite() {
        guard let siteURL else { return }
        NSWorkspace.shared.open(siteURL)
    }
}
