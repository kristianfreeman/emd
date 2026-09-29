import Foundation

/// Text that has not reached the site yet is also on disk, so a quit, a crash, or a dropped connection
/// cannot take it. The copy goes away once a save lands.
extension AppModel {
    func journal(_ document: EditorDocument) {
        guard document.dirty, !document.neverSaves, let site = siteURL?.host else { return }
        LocalStore.storePending(site: site, id: document.id, text: document.text)
    }

    /// A new post journals under its local id until the site gives it one, so both are cleared.
    func clearJournal(_ document: EditorDocument) {
        guard let site = siteURL?.host else { return }
        LocalStore.clearPending(site: site, id: document.localID)
        guard let remoteID = document.remoteID else { return }
        LocalStore.clearPending(site: site, id: remoteID)
    }

    /// New posts that never reached the site come back as drafts.
    func restoreJournaledDrafts() {
        guard let site = siteURL?.host else { return }
        let known = Set(drafts.map(\.localID))
        for (id, text) in LocalStore.pendingDrafts(site: site) where !known.contains(id) {
            let draft = EditorDocument(localID: id)
            draft.loaded = true
            draft.restore(text)
            drafts.append(draft)
        }
    }

    /// Puts unsent text back into a post that just opened, and queues it to save.
    func restoreJournal(_ document: EditorDocument) {
        guard let site = siteURL?.host, let remoteID = document.remoteID else { return }
        guard let pending = LocalStore.pending(site: site, id: remoteID) else { return }
        guard pending != document.text else {
            LocalStore.clearPending(site: site, id: remoteID)
            return
        }
        document.restore(pending)
        notice = "Restored edits that had not reached the site."
        scheduleAutosave()
    }

    /// Whether quitting now could lose text.
    var hasUnsentText: Bool {
        document?.dirty == true && document?.neverSaves == false
    }

    /// Journal first, which is instant, then give the site a few seconds to take a real save.
    func flushBeforeQuit() async {
        guard let document else { return }
        journal(document)
        let saving = Task { await self.save() }
        let deadline = Task {
            try? await Task.sleep(for: .seconds(4))
            saving.cancel()
        }
        await saving.value
        deadline.cancel()
    }
}

/// Resolving a post that changed on the site while it was being edited here.
extension AppModel {
    /// Saves this text over the site's newer copy.
    func keepMine() async {
        guard let document, let remoteID = document.remoteID, let client, let collection else { return }
        do {
            let latest = try await client.load(collection: collection, id: remoteID)
            document.rev = latest.rev
            conflicted = false
            notice = ""
            await save()
        } catch {
            report(error)
        }
    }

    /// Posts and drafts from one site never follow you to another.
    func leaveSite() {
        for draft in drafts where draft.dirty {
            journal(draft)
        }
        document = nil
        drafts = []
        entries = []
        conflicted = false
    }
}
