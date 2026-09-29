import Foundation

/// What the open post can do next. The toolbar, the Post menu, and the subtitle all read from this.
@MainActor
struct PostState {
    var document: EditorDocument
    /// False for a collection without revisions, where saving a published post changes the live post.
    var keepsRevisions = true

    init(_ document: EditorDocument, keepsRevisions: Bool = true) {
        self.document = document
        self.keepsRevisions = keepsRevisions
    }

    /// Saving this post would change what readers see right now. A scheduled post is not live yet.
    var writesLive: Bool {
        document.status == "published" && !keepsRevisions
    }

    var isLive: Bool {
        document.status == "published" || document.status == "scheduled"
    }

    /// A live post with a saved draft revision, or edits on the way to one.
    var hasUnpublishedChanges: Bool {
        isLive && (document.draftRevisionID != nil || document.dirty)
    }

    var canDiscardChanges: Bool {
        isLive && document.draftRevisionID != nil
    }

    /// A scheduled post has no publish-now button: its edits save to the draft the schedule will publish.
    var canPublish: Bool {
        guard document.status != "scheduled" else { return false }
        guard document.remoteID != nil || document.words > 0 || !document.title.isEmpty else { return false }
        return !isLive || hasUnpublishedChanges
    }

    var publishTitle: String {
        if !isLive { return "Publish" }
        if hasUnpublishedChanges { return writesLive ? "Update Live Post" : "Update" }
        return document.status == "scheduled" ? "Scheduled" : "Published"
    }

    var publishSymbol: String {
        if !isLive { return "paperplane" }
        if hasUnpublishedChanges { return "arrow.up.circle" }
        return document.status == "scheduled" ? "clock" : "checkmark.circle"
    }

    var label: String {
        switch document.status {
        case "published" where writesLive && document.dirty: "Published, edits not live yet"
        case "published": hasUnpublishedChanges ? "Published, with unpublished changes" : "Published"
        case "scheduled": scheduledLabel
        default: "Draft"
        }
    }

    private var scheduledLabel: String {
        guard let date = EditorDocument.date(document.scheduledAt) else { return "Scheduled" }
        return "Scheduled for \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    var isScheduled: Bool { document.status == "scheduled" || document.scheduledAt != nil }

    var words: String {
        let count = document.words
        return count == 1 ? "1 word" : "\(count.formatted()) words"
    }
}
