import AppKit
import Foundation
import Observation

struct TermGroup: Equatable, Identifiable {
    var taxonomy = ""
    var label: String
    var terms: [TermLabel] = []

    init(taxonomy: String, label: String, terms: [TermLabel]) {
        self.taxonomy = taxonomy
        self.label = label
        self.terms = terms
    }

    var id: String { taxonomy.isEmpty ? label : taxonomy }
    var value: String { terms.map(\.label).joined(separator: ", ") }
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
    /// Where a new post will be created. Posts from the site already live in one.
    var collectionSlug: String?
    /// A scratch post for the debug probe: it never saves and never journals.
    @ObservationIgnored var neverSaves = false
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
    /// Every taxonomy's terms for this post came from the site. Until then, term writes would drop terms.
    var termsLoaded = false
    var dirty = false
    var loaded = false
    /// Why the post could not be opened, when it could not.
    var loadError: String?
    /// Words in the title and body, recounted a moment after typing stops.
    var words = 0
    /// Bumped whenever the app, not the writer, replaces the text. The editor compares this, not the body.
    private(set) var textRevision = 0
    /// Called after each edit the writer makes.
    @ObservationIgnored var onEdit: (() -> Void)?
    @ObservationIgnored private var countTask: Task<Void, Never>?
    private var suppress = false
    private var baseTitle = ""
    private var baseBody = ""
    private var baseExcerpt = ""
    private var baseSlug = ""

    /// Any edit counts. Comparing a long body against its baseline on every keystroke costs milliseconds;
    /// `noteSaved` settles the exact answer once the text is on the site.
    private func mark() {
        guard !suppress else { return }
        dirty = true
        recount()
        onEdit?()
    }

    private func recount() {
        countTask?.cancel()
        countTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.words = WriterText.wordCount(title: self.title, body: self.body)
        }
    }

    /// Puts back text that never reached the site. It counts as an edit.
    func restore(_ text: DraftText) {
        textRevision += 1
        title = text.title
        body = text.body
        excerpt = text.excerpt
        slug = text.slug
    }

    var text: DraftText {
        DraftText(title: title, body: body, excerpt: excerpt, slug: slug)
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
        termsLoaded = false
        dirty = false
        loaded = true
        loadError = nil
        captureBase()
        textRevision += 1
        words = WriterText.wordCount(title: title, body: body)
        suppress = false
    }

    func seed(title: String, slug: String, status: String) {
        suppress = true
        self.title = title
        self.slug = slug
        self.status = status
        dirty = false
        loaded = false
        captureBase()
        textRevision += 1
        suppress = false
    }

    /// The site has `sent`. Anything typed since, in any field, stays unsaved.
    func noteSaved(_ entry: LoadedEntry, sent: DraftText) {
        suppress = true
        remoteID = entry.id
        rev = entry.rev
        status = entry.status
        publishedAt = entry.publishedAt
        scheduledAt = entry.scheduledAt
        draftRevisionID = entry.draftRevisionID
        updatedAt = EditorDocument.date(entry.updatedAt)
        let siteSlug = sent.slug.isEmpty ? entry.slug : sent.slug
        if slug.isEmpty {
            slug = entry.slug
        }
        dirty = title != sent.title || body != sent.body || excerpt != sent.excerpt || slug != siteSlug
        baseTitle = sent.title
        baseBody = sent.body
        baseExcerpt = sent.excerpt
        baseSlug = siteSlug
        loaded = true
        suppress = false
    }

    /// Status changes from publishing. The text and whether it is saved stay as they are.
    func noteStatus(_ entry: LoadedEntry) {
        rev = entry.rev
        status = entry.status
        publishedAt = entry.publishedAt
        scheduledAt = entry.scheduledAt
        draftRevisionID = entry.draftRevisionID
        updatedAt = EditorDocument.date(entry.updatedAt)
    }

    /// The text the site has, as of the last load or save.
    var savedText: DraftText {
        DraftText(title: baseTitle, body: baseBody, excerpt: baseExcerpt, slug: baseSlug)
    }

    func revertEdits() {
        suppress = true
        title = baseTitle
        body = baseBody
        excerpt = baseExcerpt
        slug = baseSlug
        dirty = false
        textRevision += 1
        words = WriterText.wordCount(title: title, body: body)
        suppress = false
    }

    private func captureBase() {
        baseTitle = title
        baseBody = body
        baseExcerpt = excerpt
        baseSlug = slug
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

    nonisolated private static let fractionalDates = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    nonisolated private static let wholeDates = Date.ISO8601FormatStyle()

    nonisolated static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        return (try? fractionalDates.parse(value)) ?? (try? wholeDates.parse(value))
    }
}
