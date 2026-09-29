import Foundation

extension AppModel {
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
}
