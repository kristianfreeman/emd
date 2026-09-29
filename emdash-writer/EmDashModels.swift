import Foundation

struct FieldDef: Equatable, Identifiable, Sendable {
    var slug: String
    var label: String
    var type: String
    var required: Bool
    var sortOrder: Int

    var id: String { slug }
}

struct CollectionDef: Equatable, Identifiable, Sendable {
    var slug: String
    var label: String
    var labelSingular: String
    var fields: [FieldDef]
    /// What the collection turns on. EmDash's default is drafts and revisions.
    var supports: [String] = ["drafts", "revisions"]

    var id: String { slug }

    /// Without revisions, a save to a published post changes the live post itself.
    var keepsRevisions: Bool { supports.contains("revisions") }

    var titleField: FieldDef? {
        if let title = fields.first(where: { $0.slug == "title" && ($0.type == "string" || $0.type == "text") }) {
            return title
        }
        return fields.filter { $0.type == "string" }.sorted { $0.sortOrder < $1.sortOrder }.first
    }

    var excerptField: FieldDef? {
        fields.first { $0.slug == "excerpt" && ($0.type == "text" || $0.type == "string") }
    }

    var bodyField: FieldDef? {
        let skipped = Set([titleField?.slug, excerptField?.slug].compactMap { $0 })
        let candidates = bodyCandidates(skipping: skipped)
        if let named = candidates.first(where: { $0.slug == "content" || $0.slug == "body" }) {
            return named
        }
        if let rich = candidates.first(where: { $0.type == "portableText" }) {
            return rich
        }
        return candidates.first
    }

    private func bodyCandidates(skipping skipped: Set<String>) -> [FieldDef] {
        fields
            .filter { ($0.type == "portableText" || $0.type == "text") && !skipped.contains($0.slug) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}

struct SiteSettings: Equatable {
    var title: String
    var tagline: String
}

struct TaxonomyInfo: Equatable, Identifiable {
    var name: String
    var label: String
    var collections: [String]

    var id: String { name }
}

struct TermLabel: Equatable, Identifiable {
    var id: String
    var label: String
}

struct ContentSummary: Codable, Equatable, Identifiable {
    var id: String
    var slug: String
    var status: String
    var title: String
    var updatedAt: Date?
    var publishedAt: Date?
    var hasPendingDraft: Bool

    var sortDate: Date { publishedAt ?? updatedAt ?? .distantPast }
}

struct LoadedEntry: Codable, Equatable {
    var id: String
    var rev: String?
    var slug: String
    var status: String
    var title: String
    var body: String
    var excerpt: String
    var updatedAt: String?
    var publishedAt: String?
    var scheduledAt: String?
    var draftRevisionID: String?
}

struct APIError: LocalizedError, Equatable {
    var status: Int
    var code: String
    var message: String

    var errorDescription: String? { message }
}

struct DraftText: Equatable, Codable {
    var title: String
    var body: String
    var excerpt: String
    var slug: String

    static let empty = DraftText(title: "", body: "", excerpt: "", slug: "")
}

struct DraftWrite: Equatable {
    var text: DraftText
    var rev: String?
    var skipRevision: Bool = false
    /// Leave the body out when it has not changed. The site merges fields, so the stored body stays exact.
    var sendsBody = true
}

enum SiteURL {
    /// https anywhere, http only for a site running on this Mac or the local network.
    static func isSecure(_ url: URL) -> Bool {
        guard url.scheme == "http" else { return true }
        let host = url.host ?? ""
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local")
    }

    static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        text = withScheme(text)
        return parts(of: text)
    }

    private static func withScheme(_ text: String) -> String {
        guard !text.contains("://") else { return text }
        return "https://\(text)"
    }

    private static func parts(of text: String) -> URL? {
        guard var parts = URLComponents(string: text), let scheme = webScheme(parts.scheme), let host = parts.host,
            !host.isEmpty
        else { return nil }
        parts.scheme = scheme
        parts.host = host.lowercased()
        parts.path = ""
        parts.query = nil
        parts.fragment = nil
        parts.user = nil
        parts.password = nil
        return parts.url
    }

    private static func webScheme(_ scheme: String?) -> String? {
        guard let scheme = scheme?.lowercased() else { return nil }
        guard scheme == "http" || scheme == "https" else { return nil }
        return scheme
    }

    static func endpoint(site: URL, path: String) -> URL {
        let pieces = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var parts = URLComponents(url: site, resolvingAgainstBaseURL: false) ?? URLComponents()
        let suffix = pieces[0].hasPrefix("/") ? String(pieces[0]) : "/" + pieces[0]
        parts.path = "/_emdash/api" + suffix
        parts.query = pieces.count == 2 ? String(pieces[1]) : nil
        return parts.url ?? site
    }
}
