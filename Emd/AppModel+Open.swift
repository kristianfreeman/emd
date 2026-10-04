import Foundation

extension AppModel {
    /// Launch comes back to the post that was open, from the cache, before the site answers.
    func reopenLast() {
        guard document == nil, let id = defaults.string(forKey: "lastOpen") else { return }
        guard entries.contains(where: { $0.id == id }) else { return }
        openFromList(id)
    }

    /// Arrowing through the list opens each row it passes. Only the last one is worth finishing.
    func openFromList(_ id: String) {
        openTask?.cancel()
        openTask = Task { await open(id) }
    }

    func open(_ id: String) async {
        if document?.id == id { return }
        if adoptDraft(id) { return }
        await openRemote(id)
    }

    private func openRemote(_ id: String) async {
        openToken += 1
        let token = openToken
        guard !id.hasPrefix("local-") else { return }
        let opened = placeholder(for: id)
        document = opened.document
        guard client != nil, collection != nil else {
            refreshAfterConnect = true
            return
        }
        await mergeRemote(id: id, token: token, opened: opened)
    }

    private func adoptDraft(_ id: String) -> Bool {
        guard let local = drafts.first(where: { $0.id == id }) else { return false }
        document = local
        if local.dirty { scheduleAutosave() }
        return true
    }

    private func placeholder(for id: String) -> Opened {
        let placeholder = EditorDocument()
        placeholder.remoteID = id
        seed(placeholder, id: id)
        return cached(placeholder, id: id)
    }

    private func seed(_ placeholder: EditorDocument, id: String) {
        if let summary = entries.first(where: { $0.id == id }) {
            placeholder.seed(title: summary.title, slug: summary.slug, status: summary.status)
            return
        }
        placeholder.loaded = false
    }

    private func cached(_ placeholder: EditorDocument, id: String) -> Opened {
        var opened = Opened(document: placeholder)
        let site = siteURL?.host ?? ""
        guard let cached = LocalStore.entry(site: site, id: id) else { return opened }
        applyingRemote = true
        placeholder.apply(cached)
        applyingRemote = false
        restoreJournal(placeholder)
        opened.baselineTitle = cached.title
        opened.baselineBody = cached.body
        return opened
    }

    private func mergeRemote(id: String, token: Int, opened: Opened) async {
        do {
            let span = Pace.begin("open")
            let loaded = try await fetchEntry(id: id)
            Pace.end(span, detail: id)
            guard token == openToken, document?.localID == opened.document.localID else { return }
            applyLoaded(loaded, to: opened)
            await refreshTerms(for: opened.document)
        } catch {
            noteOpenFailure(token, placeholder: opened.document, error: error)
        }
    }

    private func applyLoaded(_ loaded: LoadedEntry, to opened: Opened) {
        if opened.document.dirty {
            noteDirty(loaded, on: opened.document, title: opened.baselineTitle, body: opened.baselineBody)
            return
        }
        applyingRemote = true
        opened.document.apply(loaded)
        applyingRemote = false
        remember(loaded)
        restoreJournal(opened.document)
    }

    private func noteDirty(_ loaded: LoadedEntry, on document: EditorDocument, title: String, body: String) {
        guard loaded.title == title, loaded.body == body else {
            conflicted = true
            notice = "This post changed on the site while you were writing. Your text is safe here."
            return
        }
        document.rev = loaded.rev
        document.status = loaded.status
        document.publishedAt = loaded.publishedAt
        document.scheduledAt = loaded.scheduledAt
        document.draftRevisionID = loaded.draftRevisionID
    }

    private func noteOpenFailure(_ token: Int, placeholder: EditorDocument, error: Error) {
        guard token == openToken else { return }
        guard !placeholder.loaded else { return }
        placeholder.loadError = error.localizedDescription
    }

    func prefetch(_ id: String) {
        guard !id.hasPrefix("local-"), id != document?.remoteID, client != nil else { return }
        let site = siteURL?.host ?? ""
        if LocalStore.hasEntry(site: site, id: id) { return }
        prefetchTask?.cancel()
        prefetchTask = Task { @MainActor in
            await self.prefetchAfterDelay(id)
        }
    }

    private func prefetchAfterDelay(_ id: String) async {
        try? await Task.sleep(for: .milliseconds(90))
        guard !Task.isCancelled else { return }
        guard let loaded = try? await fetchEntry(id: id) else { return }
        remember(loaded)
    }

    func pullOpen() async {
        guard let id = document?.remoteID, let captured = document else { return }
        openToken += 1
        let context = PullContext(
            captured: captured,
            id: id,
            token: openToken,
            baseline: TextBaseline(title: captured.title, body: captured.body)
        )
        do {
            let loaded = try await fetchEntry(id: id)
            applyPull(loaded, context: context)
        } catch {
            notePullFailure(context.captured, error)
        }
    }

    private func applyPull(_ loaded: LoadedEntry, context: PullContext) {
        guard context.token == openToken, context.captured.remoteID == context.id else { return }
        let opened = Opened(
            document: context.captured,
            baselineTitle: context.baseline.title,
            baselineBody: context.baseline.body
        )
        applyLoaded(loaded, to: opened)
    }

    private func notePullFailure(_ captured: EditorDocument, _ error: Error) {
        guard captured.loaded != true else { return }
        captured.loadError = error.localizedDescription
    }

    func retryOpen() async {
        document?.loadError = nil
        await pullOpen()
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

    /// ⌘N on an empty new post stays on it rather than stacking another Untitled.
    func newPost() {
        filter = .all
        query = ""
        let start = startingBody()
        let blank = DraftText(title: "", body: start, excerpt: "", slug: "")
        if let empty = drafts.first(where: {
            $0.remoteID == nil && !$0.dirty && $0.text == blank && $0.collectionSlug == collection?.slug
        }) {
            document = empty
            editorFocusID = empty.localID
            return
        }
        let draft = EditorDocument()
        draft.collectionSlug = collection?.slug
        draft.loaded = true
        draft.status = "draft"
        draft.start(body: start)
        drafts.insert(draft, at: 0)
        document = draft
        editorFocusID = draft.localID
    }

    /// A page starts with its regions, each empty under its divider. A post starts blank.
    private func startingBody() -> String {
        let regions = collection?.regionFields ?? []
        return regions.isEmpty ? "" : Regions.joined(regions.map { ($0.slug, "") })
    }

    /// Reloading replaces the open post with the site's copy, so unsent edits ask first.
    func requestReload() {
        if document?.dirty == true {
            confirmReload = true
            return
        }
        Task { await reloadOpen() }
    }

    func reloadOpen() async {
        guard let document, let remoteID = document.remoteID, let client, let collection else {
            await loadLibrary()
            return
        }
        do {
            document.apply(try await client.load(collection: collection, id: remoteID))
            conflicted = false
            clearJournal(document)
            await refreshTerms(for: document)
            await loadLibrary()
            notice = ""
        } catch {
            report(error)
        }
    }
}

private struct Opened {
    var document: EditorDocument
    var baselineTitle = ""
    var baselineBody = ""
}

private struct TextBaseline {
    var title: String
    var body: String
}

private struct PullContext {
    var captured: EditorDocument
    var id: String
    var token: Int
    var baseline: TextBaseline
}
