import AppKit
import Foundation

extension AppModel {
    func requestTrash(_ id: String) {
        trashID = id
        confirmTrash = true
    }

    func title(for id: String) -> String {
        if let document, document.id == id || document.localID == id { return document.listTitle }
        if let draft = drafts.first(where: { $0.id == id || $0.localID == id }) { return draft.listTitle }
        return entries.first { $0.id == id }?.title ?? "Untitled"
    }

    func rename(_ id: String, to title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if owns(id) {
            document?.title = trimmed
            await save()
            return
        }
        await renameSaved(id, title: trimmed)
    }

    func publishRow(_ id: String) async {
        if owns(id) || adoptLocal(id) {
            await publish()
            return
        }
        await sendRow(id, action: "publish")
    }

    func unpublishRow(_ id: String) async {
        if owns(id) {
            await unpublish()
            return
        }
        await sendRow(id, action: "unpublish")
    }

    func discardRow(_ id: String) async {
        if owns(id) {
            await discardDraft()
            return
        }
        await discardSaved(id)
    }

    func showInBrowser(_ entry: ContentSummary) {
        guard let siteURL, let collection else { return }
        guard let url = RowLink.browser(site: siteURL, collection: collection.slug, entry: entry) else { return }
        NSWorkspace.shared.open(url)
    }

    var canShowOpenInBrowser: Bool {
        guard let entry = openSummary, let siteURL, let collection else { return false }
        return RowLink.browser(site: siteURL, collection: collection.slug, entry: entry) != nil
    }

    func showOpenInBrowser() {
        guard let entry = openSummary else { return }
        showInBrowser(entry)
    }

    private var openSummary: ContentSummary? {
        guard let remoteID = document?.remoteID else { return nil }
        return entries.first { $0.id == remoteID }
    }

    /// Saves, so the preview shows what was just typed, then opens the site's signed preview link.
    func previewOpen() async {
        guard let document, let client, let collection else { return }
        await saveUnlessLive()
        guard let remoteID = document.remoteID else { return }
        do {
            let slug = document.savedText.slug.isEmpty ? document.slug : document.savedText.slug
            let path = RowLink.path(collection: collection.slug, slug: slug)
            NSWorkspace.shared.open(try await client.previewURL(collection: collection.slug, id: remoteID, path: path))
        } catch {
            report(error)
        }
    }

    func showInAdmin(_ id: String) {
        guard let siteURL, let collection else { return }
        guard let url = RowLink.admin(site: siteURL, collection: collection.slug, id: id) else { return }
        NSWorkspace.shared.open(url)
    }

    private func owns(_ id: String) -> Bool {
        guard let document else { return false }
        return document.id == id || document.localID == id || document.remoteID == id
    }

    private func adoptLocal(_ id: String) -> Bool {
        guard let local = drafts.first(where: { $0.localID == id || $0.id == id }) else { return false }
        document = local
        return true
    }

    private func renameSaved(_ id: String, title: String) async {
        guard let client, let collection else { return }
        busy = true
        defer { busy = false }
        do {
            let saved = try await renamed(client, collection: collection, id: id, title: title)
            remember(saved)
            await loadLibrary()
        } catch {
            report(error)
        }
    }

    private func renamed(
        _ client: EmDashClient,
        collection: CollectionDef,
        id: String,
        title: String
    ) async throws -> LoadedEntry {
        let loaded = try await client.load(collection: collection, id: id)
        let text = DraftText(title: title, body: loaded.body, excerpt: loaded.excerpt, slug: loaded.slug)
        let write = DraftWrite(text: text, rev: loaded.rev, sendsBody: false)
        return try await client.update(collection: collection, id: id, draft: write)
    }

    private func sendRow(_ id: String, action: String) async {
        guard let client, let collection else { return }
        busy = true
        defer { busy = false }
        do {
            if action == "publish" {
                _ = try await client.publish(collection: collection, id: id)
            } else {
                _ = try await client.unpublish(collection: collection, id: id)
            }
            await loadLibrary()
        } catch {
            report(error)
        }
    }

    private func discardSaved(_ id: String) async {
        guard let client, let collection else { return }
        busy = true
        defer { busy = false }
        do {
            try await client.discardDraft(collection: collection.slug, id: id)
            await loadLibrary()
        } catch {
            report(error)
        }
    }
}

enum RowLink {
    static func browser(site: URL, collection: String, entry: ContentSummary) -> URL? {
        guard entry.status == "published" else { return nil }
        let slug = entry.slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty else { return nil }
        return site.appending(path: folder(collection)).appending(path: slug)
    }

    static func admin(site: URL, collection: String, id: String) -> URL? {
        guard !id.isEmpty, !id.hasPrefix("local-") else { return nil }
        return
            site
            .appending(path: "_emdash")
            .appending(path: "admin")
            .appending(path: "content")
            .appending(path: collection)
            .appending(path: id)
    }

    /// Where the site shows a post: `/blog/<slug>` for posts, `/<collection>/<slug>` otherwise.
    static func path(collection: String, slug: String) -> String? {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else { return nil }
        return "/\(folder(collection))/\(trimmed)"
    }

    private static func folder(_ collection: String) -> String {
        collection == "posts" ? "blog" : collection
    }
}
