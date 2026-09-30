import Foundation

/// Last library and last opened bodies, so the window paints before the network returns.
enum LocalStore {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
    /// Cache writes encode whole posts and libraries, so they happen off the main thread, in order.
    /// The journal of unsent text stays synchronous: it has to be on disk before a quit finishes.
    private static let writes = DispatchQueue(label: "LocalStore.writes", qos: .utility)
    private static let madeLock = NSLock()
    nonisolated(unsafe) private static var made: [String: URL] = [:]

    static func library(site: String, collection: String) -> [ContentSummary]? {
        guard let url = file(site: site, name: "library-\(safe(collection)).json") else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode([ContentSummary].self, from: data)
    }

    static func storeLibrary(site: String, collection: String, entries: [ContentSummary]) {
        writes.async {
            guard let url = file(site: site, name: "library-\(safe(collection)).json") else { return }
            guard let data = try? JSONEncoder().encode(entries) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    static func entry(site: String, id: String) -> LoadedEntry? {
        guard let url = file(site: site, name: "entry-\(safe(id)).json") else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(LoadedEntry.self, from: data)
    }

    static func storeEntry(site: String, entry: LoadedEntry) {
        guard !entry.id.isEmpty else { return }
        writes.async {
            guard let url = file(site: site, name: "entry-\(safe(entry.id)).json") else { return }
            guard let data = try? JSONEncoder().encode(entry) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Whether a post is cached, without reading it.
    static func hasEntry(site: String, id: String) -> Bool {
        guard let url = file(site: site, name: "entry-\(safe(id)).json") else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Text written before a save was sent. It is removed once the site has the same text.
    static func pending(site: String, id: String) -> DraftText? {
        guard let url = file(site: site, name: "pending-\(safe(id)).json") else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(DraftText.self, from: data)
    }

    static func storePending(site: String, id: String, text: DraftText) {
        guard let url = file(site: site, name: "pending-\(safe(id)).json") else { return }
        guard let data = try? encoder.encode(text) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Every post with journaled text, by id.
    static func pendingIDs(site: String) -> Set<String> {
        guard let root = directory(site: site) else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return Set(
            names.filter { $0.hasPrefix("pending-") && $0.hasSuffix(".json") }.map {
                String($0.dropFirst("pending-".count).dropLast(".json".count))
            })
    }

    /// Drafts the site never saw, by local id.
    static func pendingDrafts(site: String) -> [(id: String, text: DraftText)] {
        guard let root = directory(site: site) else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { $0.hasPrefix("pending-local-") }.compactMap { name in
            let id = String(name.dropFirst("pending-".count).dropLast(".json".count))
            return pending(site: site, id: id).map { (id, $0) }
        }
    }

    static func clearPending(site: String, id: String) {
        guard let url = file(site: site, name: "pending-\(safe(id)).json") else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func file(site: String, name: String) -> URL? {
        guard let root = directory(site: site) else { return nil }
        return root.appendingPathComponent(name)
    }

    private static func directory(site: String) -> URL? {
        madeLock.lock()
        defer { madeLock.unlock() }
        // A folder removed while the app runs is made again, rather than failing every write after.
        if let known = made[site], FileManager.default.fileExists(atPath: known.path) { return known }
        let root = createdDirectory(site: site)
        made[site] = root
        return root
    }

    private static func createdDirectory(site: String) -> URL? {
        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let root =
                base
                .appendingPathComponent("Emd", isDirectory: true)
                .appendingPathComponent(safe(site), isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            return root
        } catch {
            return nil
        }
    }

    private static func safe(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let text = String(scalars)
        return text.isEmpty ? "site" : text
    }
}
