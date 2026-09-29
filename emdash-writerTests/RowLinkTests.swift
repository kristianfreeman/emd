import XCTest

@testable import EmDashWriter

final class RowLinkTests: XCTestCase {
    private let site = URL(string: "https://kristianfreeman.com")!

    func testPostBrowserUsesBlog() {
        let entry = summary(slug: "closing-a-cleaning-company", status: "published")
        let url = RowLink.browser(site: site, collection: "posts", entry: entry)
        XCTAssertEqual(url?.absoluteString, "https://kristianfreeman.com/blog/closing-a-cleaning-company")
    }

    func testReleaseBrowserUsesReleases() {
        let entry = summary(slug: "pull-ep", status: "published")
        let url = RowLink.browser(site: site, collection: "releases", entry: entry)
        XCTAssertEqual(url?.absoluteString, "https://kristianfreeman.com/releases/pull-ep")
    }

    func testDraftHasNoBrowserLink() {
        let entry = summary(slug: "notes", status: "draft")
        XCTAssertNil(RowLink.browser(site: site, collection: "posts", entry: entry))
    }

    func testAdminLinkUsesTheRecord() {
        let url = RowLink.admin(site: site, collection: "posts", id: "01HXK")
        XCTAssertEqual(url?.absoluteString, "https://kristianfreeman.com/_emdash/admin/content/posts/01HXK")
    }

    func testLocalDraftHasNoAdminLink() {
        XCTAssertNil(RowLink.admin(site: site, collection: "posts", id: "local-1"))
    }

    private func summary(slug: String, status: String) -> ContentSummary {
        ContentSummary(
            id: "01HXK",
            slug: slug,
            status: status,
            title: "Title",
            updatedAt: nil,
            publishedAt: nil,
            hasPendingDraft: false
        )
    }
}
