import Foundation

/// What the open post can do next. The toolbar, the Post menu, and the subtitle all read from this.
@MainActor
struct PostState {
    var document: EditorDocument

    init(_ document: EditorDocument) {
        self.document = document
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

    var canPublish: Bool {
        guard document.remoteID != nil || document.words > 0 || !document.title.isEmpty else { return false }
        return !isLive || hasUnpublishedChanges
    }

    var publishTitle: String {
        if !isLive { return "Publish" }
        if hasUnpublishedChanges { return "Update" }
        return document.status == "scheduled" ? "Scheduled" : "Published"
    }

    var publishSymbol: String {
        if !isLive { return "paperplane" }
        if hasUnpublishedChanges { return "arrow.up.circle" }
        return document.status == "scheduled" ? "clock" : "checkmark.circle"
    }

    var label: String {
        switch document.status {
        case "published": hasUnpublishedChanges ? "Published, with unpublished changes" : "Published"
        case "scheduled": "Scheduled"
        default: "Draft"
        }
    }

    var words: String {
        let count = document.words
        return count == 1 ? "1 word" : "\(count.formatted()) words"
    }
}
