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
    var document: EditorDocument?
    var query = ""
    var filter: LibraryFilter = .all
    var appearance: AppearanceChoice
    var fontChoice: WriterFont
    var fontSize: Double
    var focusMode: Bool {
        didSet { defaults.set(focusMode, forKey: "focus") }
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
    var loadingLibrary = false
    var notice = ""
    var confirmTrash = false

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
    var refreshAfterConnect = false
    var applyingRemote = false
    let defaults = UserDefaults.standard

    init() {
        appearance = AppearanceChoice(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
        fontChoice = WriterFont(rawValue: UserDefaults.standard.string(forKey: "font") ?? "") ?? .geistSans
        let storedSize = UserDefaults.standard.double(forKey: "fontSize")
        fontSize = storedSize == 0 || storedSize >= 20 ? 15 : min(24, max(13, storedSize))
        focusMode = UserDefaults.standard.bool(forKey: "focus")
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

    func setFocus(_ enabled: Bool) {
        focusMode = enabled
        defaults.set(enabled, forKey: "focus")
    }

    func setTypewriter(_ enabled: Bool) {
        typewriter = enabled
        defaults.set(enabled, forKey: "typewriter")
    }

    func setInspector(_ shown: Bool) {
        showInspector = shown
        defaults.set(shown, forKey: "inspector")
    }

    func openSite() {
        guard let siteURL else { return }
        NSWorkspace.shared.open(siteURL)
    }
}
