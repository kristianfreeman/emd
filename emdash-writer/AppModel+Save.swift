import Foundation

extension AppModel {
    func scheduleAutosave() {
        guard !applyingRemote, !conflicted, let document, document.dirty else { return }
        guard hasSavableText(document) else { return }
        lastEdit = Date()
        guard autosaveTask == nil else { return }
        autosaveTask = Task { @MainActor in
            defer { self.autosaveTask = nil }
            await self.waitUntilSettled()
        }
    }

    private func hasSavableText(_ document: EditorDocument) -> Bool {
        document.title.contains { !$0.isWhitespace } || document.body.contains { !$0.isWhitespace }
    }

    private func waitUntilSettled() async {
        while await keepWaiting() {}
    }

    private func keepWaiting() async -> Bool {
        guard !Task.isCancelled else { return false }
        let remaining = lastEdit.addingTimeInterval(2.5).timeIntervalSinceNow
        if remaining > 0.05 {
            try? await Task.sleep(for: .milliseconds(Int(remaining * 1000)))
            return true
        }
        guard let document, document.dirty else { return false }
        journal(document)
        // Without revisions this save would be the live post. It waits for Update, safe in the journal.
        guard !postState(document).writesLive else { return false }
        await enqueueSave(publishIfLive: false, skipRevision: true)
        return scheduleRetry()
    }

    /// Whether to keep going after a save: yes while text is still unsent and the failure can pass.
    private func scheduleRetry() -> Bool {
        guard document?.dirty == true else {
            saveFailures = 0
            return false
        }
        guard !saveFailed || retryable(saveError) else { return false }
        saveFailures = saveFailed ? saveFailures + 1 : 0
        let backoff = min(57.5, 2.5 * (pow(2, Double(saveFailures)) - 1))
        lastEdit = Date().addingTimeInterval(backoff)
        return true
    }

    /// The network and the server's own trouble pass. A rejected request fails the same way again.
    private func retryable(_ error: Error?) -> Bool {
        if let api = error as? APIError { return api.status >= 500 || api.status == 429 }
        return error is URLError
    }

    func postState(_ document: EditorDocument) -> PostState {
        PostState(document, keepsRevisions: collection?.keepsRevisions ?? true)
    }

    /// Saves before leaving the post, unless that would change a live post by itself. Then it journals.
    func saveUnlessLive() async {
        guard let document, postState(document).writesLive else { return await save() }
        journal(document)
    }

    func save() async {
        lastEdit = .distantPast
        await enqueueSave(publishIfLive: false, skipRevision: false)
    }

    func enqueueSave(publishIfLive: Bool, skipRevision: Bool) async {
        let previous = saveChain
        let next = Task { @MainActor in
            await previous?.value
            await self.performSave(publishIfLive: publishIfLive, skipRevision: skipRevision)
        }
        saveChain = next
        await next.value
    }

    private func performSave(publishIfLive: Bool, skipRevision: Bool) async {
        guard let request = saveRequest(publishIfLive: publishIfLive, skipRevision: skipRevision) else { return }
        guard claimCreate(request) else { return }
        saveGeneration += 1
        let generation = saveGeneration
        saving = true
        saveFailed = false
        saveError = nil
        notice = ""
        let span = Pace.begin("save")
        defer { finishSave(request, span: span) }
        journal(request.document)
        do {
            try await writeAndNote(request, generation: generation)
        } catch {
            saveFailed = true
            saveError = error
            noteSaveFailure(error)
        }
    }

    private func noteSaveFailure(_ error: Error) {
        guard (error as? APIError)?.status == 409 else {
            report(error)
            return
        }
        conflicted = true
        notice = "This post changed on the site while you were writing. Your text is safe here."
    }

    private func saveRequest(publishIfLive: Bool, skipRevision: Bool) -> SaveRequest? {
        guard !busy, !saving else { return nil }
        guard let document, document.dirty, !document.neverSaves else { return nil }
        guard let client, let collection else { return nil }
        // A new post belongs to the collection it was started in.
        guard document.collectionSlug == nil || document.collectionSlug == collection.slug else { return nil }
        return SaveRequest(
            document: document,
            client: client,
            collection: collection,
            text: SaveText(
                title: document.title,
                body: document.body,
                excerpt: document.excerpt,
                slug: document.slug
            ),
            wasNew: document.remoteID == nil,
            keepLive: publishIfLive && document.status == "published",
            localID: document.localID,
            skipRevision: skipRevision
        )
    }

    private func claimCreate(_ request: SaveRequest) -> Bool {
        guard request.wasNew else { return true }
        guard !creatingLocalIDs.contains(request.localID) else { return false }
        creatingLocalIDs.insert(request.localID)
        return true
    }

    private func finishSave(_ request: SaveRequest, span: Pace.Span) {
        saving = false
        creatingLocalIDs.remove(request.localID)
        Pace.end(span, detail: request.keepLive ? "live" : "draft")
    }

    private func writeAndNote(_ request: SaveRequest, generation: Int) async throws {
        let saved = try await writeDraft(request)
        guard generation == saveGeneration else { return }
        stamp(saved, request: request)
        guard try await noteLive(request, generation: generation) else { return }
        remember(request.document)
        noteSidebar(request)
    }

    private func writeDraft(_ request: SaveRequest) async throws -> LoadedEntry {
        if let remoteID = request.document.remoteID, !remoteID.isEmpty {
            return try await request.client.update(
                collection: request.collection,
                id: remoteID,
                draft: written(request)
            )
        }
        let created = DraftWrite(text: request.text.draft)
        let saved = try await request.client.create(collection: request.collection, draft: created)
        request.document.remoteID = saved.id
        request.document.rev = saved.rev
        return saved
    }

    private func written(_ request: SaveRequest) -> DraftWrite {
        DraftWrite(
            text: request.text.draft,
            rev: request.document.rev,
            skipRevision: request.skipRevision,
            sendsBody: request.text.body != request.document.savedText.body
        )
    }

    private func stamp(_ entry: LoadedEntry, request: SaveRequest) {
        applyingRemote = true
        drafts.removeAll { $0.localID == request.localID }
        request.document.noteSaved(entry, sentTitle: request.text.title, sentBody: request.text.body)
        applyingRemote = false
        if !request.document.dirty { clearJournal(request.document) }
    }

    private func noteLive(_ request: SaveRequest, generation: Int) async throws -> Bool {
        guard request.keepLive, let remoteID = request.document.remoteID else { return true }
        let live = try await request.client.publish(collection: request.collection, id: remoteID)
        guard generation == saveGeneration else { return false }
        stamp(live, request: request)
        return true
    }

    private func noteSidebar(_ request: SaveRequest) {
        guard let remoteID = request.document.remoteID else { return }
        if request.wasNew {
            insertSummary(remoteID, request: request)
            return
        }
        patchRow(request.document)
    }

    private func insertSummary(_ remoteID: String, request: SaveRequest) {
        let summary = ContentSummary(
            id: remoteID,
            slug: request.document.slug,
            status: request.document.status,
            title: request.document.listTitle,
            updatedAt: Date(),
            publishedAt: EditorDocument.date(request.document.publishedAt),
            hasPendingDraft: request.document.draftRevisionID != nil
        )
        entries.removeAll { $0.id == remoteID }
        entries.insert(summary, at: 0)
        guard let site = siteURL?.host else { return }
        LocalStore.storeLibrary(site: site, collection: request.collection.slug, entries: entries)
    }
}

private struct SaveText {
    var title: String
    var body: String
    var excerpt: String
    var slug: String

    var draft: DraftText {
        DraftText(title: title, body: body, excerpt: excerpt, slug: slug)
    }
}

private struct SaveRequest {
    var document: EditorDocument
    var client: EmDashClient
    var collection: CollectionDef
    var text: SaveText
    var wasNew = false
    var keepLive = false
    var localID = ""
    var skipRevision = false
}
