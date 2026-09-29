import Foundation

/// Last library and last opened bodies, so the window paints before the network returns.
enum LocalStore {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func library(site: String, collection: String) -> [ContentSummary]? {
        guard let url = file(site: site, name: "library-\(safe(collection)).json") else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode([ContentSummary].self, from: data)
    }

    static func storeLibrary(site: String, collection: String, entries: [ContentSummary]) {
        guard let url = file(site: site, name: "library-\(safe(collection)).json") else { return }
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func entry(site: String, id: String) -> LoadedEntry? {
        guard let url = file(site: site, name: "entry-\(safe(id)).json") else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(LoadedEntry.self, from: data)
    }

    static func storeEntry(site: String, entry: LoadedEntry) {
        guard !entry.id.isEmpty, let url = file(site: site, name: "entry-\(safe(entry.id)).json") else { return }
        guard let data = try? encoder.encode(entry) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func file(site: String, name: String) -> URL? {
        guard let root = directory(site: site) else { return nil }
        return root.appendingPathComponent(name)
    }

    private static func directory(site: String) -> URL? {
        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let root = base
                .appendingPathComponent("EmDashWriter", isDirectory: true)
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
