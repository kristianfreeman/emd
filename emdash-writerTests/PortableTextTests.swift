import XCTest

@testable import EmDashWriter

final class PortableTextTests: XCTestCase {
    func testParagraphRoundTrip() {
        let markdown = "Hello there.\n"
        let blocks = PortableText.fromMarkdown(markdown)
        XCTAssertEqual(PortableText.toMarkdown(blocks), markdown)
    }

    func testHeadingListAndMarks() {
        let markdown = """
            # Launch
            Say **hi** and _go_ to [the site](https://example.com).

            - one
            - two

            1. first
            """
        let again = PortableText.toMarkdown(PortableText.fromMarkdown(markdown + "\n"))
        XCTAssertTrue(again.contains("# Launch"))
        XCTAssertTrue(again.contains("**hi**"))
        XCTAssertTrue(again.contains("_go_"))
        XCTAssertTrue(again.contains("[the site](https://example.com)"))
        XCTAssertTrue(again.contains("- one"))
        XCTAssertTrue(again.contains("- two"))
        XCTAssertTrue(again.contains("1. first"))
    }

    func testCodeFence() {
        let markdown = """
            ```swift
            let x = 1
            ```
            """
        let again = PortableText.toMarkdown(PortableText.fromMarkdown(markdown + "\n"))
        XCTAssertTrue(again.contains("```swift"))
        XCTAssertTrue(again.contains("let x = 1"))
    }

    func testSimpleImageRoundTrip() {
        let markdown = "Before\n\n![Cover](https://example.com/cover.jpg)\n\nAfter\n"
        let blocks = PortableText.fromMarkdown(markdown)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[1].object?["_type"], .string("image"))
        XCTAssertEqual(blocks[1].object?["alt"], .string("Cover"))
        XCTAssertEqual(blocks[1].object?["asset"]?.object?["url"], .string("https://example.com/cover.jpg"))
        XCTAssertNil(blocks[1].object?["asset"]?.object?["_ref"])
        XCTAssertEqual(PortableText.toMarkdown(blocks), markdown)
    }

    func testRichImageStaysFenced() {
        let original: JSONValue = .array([
            .object([
                "_key": .string("img1"),
                "_type": .string("image"),
                "alt": .string("Cover"),
                "asset": .object([
                    "_ref": .string("01HXK"),
                    "url": .string("/_emdash/api/media/file/01HXK.jpg"),
                ]),
                "caption": .string("Night"),
                "width": .number(1920),
            ])
        ])
        let markdown = PortableText.toMarkdown(original.array ?? [])
        XCTAssertTrue(markdown.contains("<!--ec:block"))
        XCTAssertFalse(markdown.contains("!["))
        XCTAssertEqual(PortableText.fromMarkdown(markdown), original.array)
    }

    func testUnknownBlockSurvives() {
        let original: JSONValue = .array([
            .object([
                "_key": .string("html1"),
                "_type": .string("htmlBlock"),
                "html": .string("<p>kept</p>"),
            ])
        ])
        let markdown = PortableText.toMarkdown(original.array ?? [])
        XCTAssertTrue(markdown.contains("<!--ec:block"))
        XCTAssertEqual(PortableText.fromMarkdown(markdown), original.array)
    }

    func testOnlyPortableTextFieldsConvert() {
        let fields = [
            FieldDef(slug: "title", label: "Title", type: "string", required: true, sortOrder: 0),
            FieldDef(slug: "content", label: "Content", type: "portableText", required: false, sortOrder: 1),
            FieldDef(slug: "excerpt", label: "Excerpt", type: "text", required: false, sortOrder: 2),
        ]
        let written = PortableText.portableData(
            from: [
                "title": .string("Hello"),
                "content": .string("Body copy"),
                "excerpt": .string("Short"),
            ], fields: fields)
        XCTAssertEqual(written["title"], .string("Hello"))
        XCTAssertEqual(written["excerpt"], .string("Short"))
        XCTAssertNotNil(written["content"]?.array)
        let read = PortableText.markdownData(from: written, fields: fields)
        XCTAssertEqual(read["content"], .string("Body copy\n"))
    }

    func testWordCountAndEditorBody() {
        XCTAssertEqual(WriterText.wordCount(title: "Hello", body: "there friend"), 3)
        XCTAssertEqual(WriterText.editorBody("Hello\n\n"), "Hello")
    }

}
