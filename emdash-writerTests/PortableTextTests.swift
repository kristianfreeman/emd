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

    func testUnknownBlockSurvives() {
        let original: JSONValue = .array([
            .object([
                "_type": .string("image"),
                "_key": .string("img1"),
                "alt": .string("Cover"),
                "asset": .object(["url": .string("https://example.com/cover.jpg")]),
            ])
        ])
        let markdown = PortableText.toMarkdown(original.array ?? [])
        XCTAssertTrue(markdown.contains("<!--ec:block"))
        let parsed = PortableText.fromMarkdown(markdown)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].object?["_type"], .string("image"))
        XCTAssertEqual(parsed[0].object?["alt"], .string("Cover"))
        XCTAssertEqual(parsed[0].object?["asset"]?.object?["url"], .string("https://example.com/cover.jpg"))
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
