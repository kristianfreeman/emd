import XCTest

@testable import Emd

/// `[^1]` and `[^1]: note` go to the site as marks and a block every EmDash site draws, and come back the same.
final class FootnoteTests: XCTestCase {
    private let post =
        "Words here.[^1] More words.[^2]\n\nAfter.\n\n[^1]: The **first** note.\n[^2]: See [docs](https://example.com)."

    func testReferenceIsASuperscriptLinkToItsNote() {
        let blocks = PortableText.fromMarkdown("Words.[^1]")
        let block = blocks.first?.object
        let children = block?["children"]?.array?.compactMap(\.object) ?? []
        let note = children.first { $0["text"]?.string == "1" }
        let marks = note?["marks"]?.array?.compactMap(\.string) ?? []
        XCTAssertTrue(marks.contains("superscript"))
        let link = block?["markDefs"]?.array?.first?.object
        XCTAssertEqual(link?["href"]?.string, "#fn-1")
        XCTAssertTrue(marks.contains(link?["_key"]?.string ?? "-"))
    }

    func testNotesBecomeOneHTMLBlockWithAnchors() {
        let blocks = PortableText.fromMarkdown(post).compactMap(\.object)
        let notes = blocks.filter { $0["_type"]?.string == "htmlBlock" }
        XCTAssertEqual(notes.count, 1)
        let html = notes.first?["html"]?.string ?? ""
        XCTAssertTrue(html.contains("id=\"fn-1\""))
        XCTAssertTrue(html.contains("id=\"fn-2\""))
        XCTAssertTrue(html.contains("<strong>first</strong>"))
        XCTAssertTrue(html.contains("<a href=\"https://example.com\">docs</a>"))
    }

    func testPostRoundTrips() {
        XCTAssertEqual(PortableText.toMarkdown(PortableText.fromMarkdown(post)), post + "\n")
    }

    func testNoteMarkupIsEscaped() {
        let markdown = "[^a]: 1 < 2 & \"quoted\"\n"
        let html = PortableText.fromMarkdown(markdown).first?.object?["html"]?.string ?? ""
        XCTAssertTrue(html.contains("1 &lt; 2 &amp; &quot;quoted&quot;"))
        XCTAssertEqual(PortableText.toMarkdown(PortableText.fromMarkdown(markdown)), markdown)
    }

    func testEditedNoteBlockStaysFenced() {
        let block: [String: JSONValue] = [
            "_type": .string("htmlBlock"), "_key": .string("k"),
            "html": .string("<section class=\"footnotes\"><p>Hand edited</p></section>"),
        ]
        XCTAssertTrue(PortableText.toMarkdown([.object(block)]).hasPrefix("<!--ec:block"))
    }

    func testSuperscriptAloneIsNotAFootnote() {
        let block: [String: JSONValue] = [
            "_type": .string("block"), "_key": .string("b"), "style": .string("normal"), "markDefs": .array([]),
            "children": .array([PortableText.span("x", marks: []), PortableText.span("2", marks: ["superscript"])]),
        ]
        XCTAssertFalse(PortableText.toMarkdown([.object(block)]).contains("[^"))
    }

    func testLinkAfterReferenceStaysALink() {
        let block = PortableText.fromMarkdown("Note[^1] and [a link](https://example.com).").first?.object
        let hrefs = block?["markDefs"]?.array?.compactMap { $0.object?["href"]?.string } ?? []
        XCTAssertEqual(hrefs, ["#fn-1", "https://example.com"])
    }

    func testLabelsAreNotWords() {
        XCTAssertEqual(WriterText.readableWords(in: "One two.[^1]\n\n[^1]: Three."), 3)
    }
}
