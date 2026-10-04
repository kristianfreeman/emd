import XCTest

@testable import Emd

@MainActor
final class JournalTests: XCTestCase {
    private let site = "journal-tests.invalid"

    override func tearDown() async throws {
        for id in ["post-1", "local-journal-test"] {
            LocalStore.clearPending(site: site, id: id)
        }
        // The test host is the Debug app, so its store is the Debug one. Leave nothing behind in it.
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        try? FileManager.default.removeItem(at: support.appending(path: "\(AppIdentity.folder)/\(site)"))
    }

    func testUnsentEditsComeBackWhenThePostReopens() {
        let model = AppModel()
        model.siteURL = URL(string: "https://\(site)")
        let first = EditorDocument()
        first.apply(entry(body: "On the site."))
        first.body = "On the site, and more."
        model.journal(first)

        let reopened = EditorDocument()
        reopened.apply(entry(body: "On the site."))
        model.restoreJournal(reopened)

        XCTAssertEqual(reopened.body, "On the site, and more.")
        XCTAssertTrue(reopened.dirty)
    }

    func testSavedTextClearsTheJournal() {
        let model = AppModel()
        model.siteURL = URL(string: "https://\(site)")
        let document = EditorDocument()
        document.apply(entry(body: "Saved."))
        document.body = "Saved, then edited."
        model.journal(document)
        XCTAssertTrue(model.unsentIDs.contains("post-1"))
        model.clearJournal(document)
        XCTAssertNil(LocalStore.pending(site: site, id: "post-1"))
        XCTAssertFalse(model.unsentIDs.contains("post-1"))
    }

    func testNewPostsThatNeverReachedTheSiteComeBackAsDrafts() {
        let model = AppModel()
        model.siteURL = URL(string: "https://\(site)")
        let draft = EditorDocument(localID: "local-journal-test")
        draft.loaded = true
        draft.body = "Written offline."
        model.journal(draft)
        model.drafts = []
        model.restoreJournaledDrafts()
        XCTAssertEqual(model.drafts.first { $0.localID == "local-journal-test" }?.body, "Written offline.")
    }

    private func entry(body: String) -> LoadedEntry {
        LoadedEntry(
            id: "post-1", rev: "1", slug: "post", status: "draft", title: "Post", body: body, excerpt: "",
            updatedAt: nil, publishedAt: nil, scheduledAt: nil, draftRevisionID: nil)
    }
}

extension JournalTests {
    func testFieldsTypedDuringASaveStayUnsaved() {
        let document = EditorDocument()
        document.apply(entry(body: "Body."))
        document.excerpt = "abc"
        let sent = document.text
        document.excerpt = "abcd"
        document.noteSaved(entry(body: "Body."), sent: sent)
        XCTAssertTrue(document.dirty, "the d typed during the save has not reached the site")
        XCTAssertEqual(document.savedText.excerpt, "abc")
        document.noteSaved(entry(body: "Body."), sent: document.text)
        XCTAssertFalse(document.dirty)
    }
}

extension JournalTests {
    func testWritingBackTheSameValueIsNotAnEdit() {
        let document = EditorDocument()
        document.apply(entry(body: "Body."))
        document.title = document.title
        document.slug = document.slug
        document.excerpt = document.excerpt
        XCTAssertFalse(document.dirty, "opening Post Details must not make the post look edited")
        document.excerpt = "new"
        XCTAssertTrue(document.dirty)
    }
}
