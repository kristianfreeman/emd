import Foundation

extension AppModel {
    func publish() async {
        guard let document else { return }
        guard uploadsInFlight == 0 else {
            flash("Images are still uploading")
            return
        }
        notice = ""
        let wasLive = postState(document).isLive
        guard await savedForPublish(document), let remoteID = document.remoteID, let client, let collection else {
            return
        }
        let done = await transition(document) { try await client.publish(collection: collection, id: remoteID) }
        if done { flash(wasLive ? "Changes published" : "Published") }
    }

    func unpublish() async {
        guard let document, let remoteID = document.remoteID, let client, let collection else { return }
        notice = ""
        await saveChain?.value
        let done = await transition(document) { try await client.unpublish(collection: collection, id: remoteID) }
        if done { flash("Unpublished") }
    }

    /// Saves, then asks the site to publish at `date`.
    func schedule(at date: Date) async {
        guard let document else { return }
        notice = ""
        guard await savedForPublish(document), let remoteID = document.remoteID, let client, let collection else {
            return
        }
        let done = await transition(document) {
            try await client.schedule(collection: collection, id: remoteID, at: date)
        }
        if done { flash("Scheduled for \(date.formatted(date: .abbreviated, time: .shortened))") }
    }

    func unschedule() async {
        guard let document, let remoteID = document.remoteID, let client, let collection else { return }
        notice = ""
        let done = await transition(document) { try await client.unschedule(collection: collection, id: remoteID) }
        if done { flash("No longer scheduled") }
    }

    /// Publishing sends what the site already has, so unsaved text goes up first.
    private func savedForPublish(_ document: EditorDocument) async -> Bool {
        if document.dirty || document.remoteID == nil {
            lastEdit = .distantPast
            await enqueueSave(publishIfLive: false, skipRevision: false)
        } else {
            await saveChain?.value
        }
        return !saveFailed && document.remoteID != nil
    }

    /// Publish and unpublish change status, not text. Anything typed while the request was out stays unsaved.
    private func transition(
        _ document: EditorDocument,
        request: () async throws -> LoadedEntry
    ) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            document.noteStatus(try await request())
            remember(document)
            patchRow(document)
            return true
        } catch {
            report(error)
            return false
        }
    }

    func flash(_ text: String) {
        flashText = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.flashText == text else { return }
            self.flashText = ""
        }
    }

    func requestDiscard(_ id: String) {
        discardID = id
        confirmDiscard = true
    }

    func discardDraft() async {
        guard let document, let remoteID = document.remoteID, let client, let collection else { return }
        notice = ""
        busy = true
        defer { busy = false }
        do {
            try await client.discardDraft(collection: collection.slug, id: remoteID)
            document.apply(try await client.load(collection: collection, id: remoteID))
            clearJournal(document)
            remember(document)
            patchRow(document)
            flash("Unpublished changes discarded")
        } catch {
            report(error)
        }
    }

    func trash() async {
        let target = trashID ?? document?.id
        trashID = nil
        guard let target else { return }
        if dropLocal(target) { return }
        await trashSaved(target)
    }

    private func dropLocal(_ id: String) -> Bool {
        let openLocal = document?.remoteID == nil && (document?.id == id || document?.localID == id)
        let stored = drafts.contains { $0.remoteID == nil && ($0.localID == id || $0.id == id) }
        guard openLocal || stored else { return false }
        for draft in drafts where draft.localID == id || draft.id == id {
            forget(draft)
        }
        drafts.removeAll { $0.localID == id || $0.id == id }
        if let document, document.id == id || document.localID == id {
            forget(document)
            self.document = nil
        }
        return true
    }

    /// A trashed post must not come back from the journal.
    private func forget(_ document: EditorDocument) {
        document.dirty = false
        clearJournal(document)
    }

    private func trashSaved(_ id: String) async {
        guard let client, let collection else { return }
        busy = true
        defer { busy = false }
        do {
            try await client.trash(collection: collection.slug, id: id)
            if let document, document.remoteID == id || document.id == id {
                forget(document)
                self.document = nil
            }
            entries.removeAll { $0.id == id }
        } catch {
            report(error)
        }
    }
}
