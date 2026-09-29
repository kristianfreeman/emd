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
