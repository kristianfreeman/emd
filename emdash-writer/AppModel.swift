import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppModel {
    var siteURL: URL?
    var siteTitle = ""
    var tagline = ""
    var collections: [CollectionDef] = []
    var collectionSlug = ""
    var entries: [ContentSummary] = []
    var document: EditorDocument? {
        didSet {
            // A pending autosave follows the open post, so text left behind goes to disk now.
            if let oldValue, oldValue !== document { journal(oldValue) }
            document?.onEdit = { [weak self] in self?.scheduleAutosave() }
            if document?.neverSaves != true { defaults.set(document?.remoteID, forKey: "lastOpen") }
        }
    }
    var query = ""
    var filter: LibraryFilter = .all
    var appearance: AppearanceChoice
    var fontChoice: WriterFont
    var fontSize: Double
    var focusMode: Bool {
        didSet { defaults.set(focusMode, forKey: "focus") }
    }
    var focusDepth: FocusDepth {
        didSet { defaults.set(focusDepth.rawValue, forKey: "focusDepth") }
    }
    var typewriter: Bool {
        didSet { defaults.set(typewriter, forKey: "typewriter") }
    }
    var showInspector: Bool {
        didSet { defaults.set(showInspector, forKey: "inspector") }
    }
    var taxonomies: [TaxonomyInfo] = []
    var busy = false
    /// Cached posts are on screen while the site is still connecting.
    var warming = false
    /// The stored site could not be reached. Cached posts stay open for writing and a reconnect is queued.
    var offline = false
    var loadingLibrary = false
    var notice = ""
    var confirmTrash = false
    var confirmReload = false
    var showingDetails = false
    var confirmDiscard = false
    var discardID: String?
    /// A short confirmation, like "Published", shown in the subtitle for a few seconds.
    var flashText = ""
    /// The last save threw. Publishing waits on this rather than on whatever `notice` happens to say.
    var saveFailed = false
    var saveError: Error?
    /// Consecutive autosaves that failed for reasons worth retrying. Each one doubles the wait.
    var saveFailures = 0
    /// The site's copy moved on while this one was being edited. Saving waits for a decision.
    var conflicted = false
    /// The post whose editor should take the keyboard once it is on screen.
    var editorFocusID: String?
    /// Bumped to hand the keyboard back to the post list.
    var sidebarFocusToken = 0
    /// Bumped by Search Posts. The sidebar opens, if it was hidden, and its search field takes the keyboard.
    var searchToken = 0
    var trashID: String?

    var client: EmDashClient?
    var drafts: [EditorDocument] = []
    var openToken = 0
    var autosaveTask: Task<Void, Never>?
    var lastEdit = Date.distantPast
    var saveGeneration = 0
    var saveChain: Task<Void, Never>?
    var saving = false
    var creatingLocalIDs: Set<String> = []
    var loads: [String: Task<LoadedEntry, Error>] = [:]
    var prefetchTask: Task<Void, Never>?
    var openTask: Task<Void, Never>?
    /// Images still on their way to the site. Publishing waits for them.
    var uploadsInFlight = 0
    /// The page on screen, so an upload can finish as an undoable edit instead of a text swap.
    @ObservationIgnored weak var editorView: QuietTextView?
    @ObservationIgnored var editorDocumentID: String?
    var refreshAfterConnect = false
    var applyingRemote = false
    let defaults = UserDefaults.standard

    init() {
        appearance = AppearanceChoice(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
        fontChoice = WriterFont(rawValue: UserDefaults.standard.string(forKey: "font") ?? "") ?? .geistSans
        let storedSize = UserDefaults.standard.double(forKey: "fontSize")
        fontSize = storedSize == 0 ? 15 : min(24, max(13, storedSize))
        focusMode = UserDefaults.standard.bool(forKey: "focus")
        focusDepth = FocusDepth(rawValue: UserDefaults.standard.integer(forKey: "focusDepth")) ?? .muted
        typewriter = UserDefaults.standard.bool(forKey: "typewriter")
        if UserDefaults.standard.object(forKey: "inspector") == nil {
            showInspector = true
        } else {
            showInspector = UserDefaults.standard.bool(forKey: "inspector")
        }
        collectionSlug = UserDefaults.standard.string(forKey: "collection") ?? "posts"
        if let raw = UserDefaults.standard.string(forKey: "siteURL") {
            siteURL = SiteURL.normalize(raw)
        }
        siteTitle = UserDefaults.standard.string(forKey: "siteTitle") ?? ""
        if let host = siteURL?.host,
            let cached = LocalStore.library(site: host, collection: collectionSlug),
            !cached.isEmpty
        {
            entries = cached
            warming = true
        }
    }

    var collection: CollectionDef? {
        collections.first { $0.slug == collectionSlug } ?? collections.first { $0.slug == "posts" } ?? collections.first
    }

    var isConnected: Bool { client != nil && siteURL != nil }

    var applicableTaxonomies: [TaxonomyInfo] {
        guard let collection else { return [] }
        return taxonomies.filter { $0.collections.isEmpty || $0.collections.contains(collection.slug) }
    }

    func setAppearance(_ choice: AppearanceChoice) {
        appearance = choice
        defaults.set(choice.rawValue, forKey: "appearance")
    }

    func setFont(_ choice: WriterFont) {
        fontChoice = choice
        defaults.set(choice.rawValue, forKey: "font")
    }

    func setFontSize(_ size: Double) {
        fontSize = min(24, max(13, size))
        defaults.set(fontSize, forKey: "fontSize")
    }

    func setInspector(_ shown: Bool) {
        showInspector = shown
        defaults.set(shown, forKey: "inspector")
    }

    func focusEditor() {
        editorFocusID = document?.localID
    }

    func focusSidebar() {
        editorFocusID = nil
        sidebarFocusToken += 1
    }

    /// Caret memory is per site and post. A draft the site has not seen yet goes by its local id.
    func caretKey(_ document: EditorDocument) -> String {
        guard let remoteID = document.remoteID else { return document.localID }
        return "\(siteURL?.host ?? "")|\(remoteID)"
    }

    func openSite() {
        guard let siteURL else { return }
        NSWorkspace.shared.open(siteURL)
    }
}
