import XCTest

@testable import Emd

/// A post read from the site and saved back must come back as the same blocks.
final class FidelityTests: XCTestCase {
    func testUnderscoresInsideWordsStayPlain() {
        let block = paragraph([span("see file_name_here now")])
        let markdown = PortableText.toMarkdown([.object(block)])
        XCTAssertEqual(markdown, "see file_name_here now\n")
        assertSurvives(block)
    }

    func testLiteralMarkersAreEscapedNotLost() {
        let block = paragraph([span("2 * 3 * 4 and a_b_ and `tick`")])
        assertSurvives(block)
        XCTAssertTrue(PortableText.toMarkdown([.object(block)]).contains("\\*"))
    }

    func testNestedMarksRoundTrip() {
        assertSurvives(paragraph([span("both", marks: ["strong", "em"])]))
        let link = paragraph(
            [span("bold link", marks: ["strong", "l1"])],
            defs: [["_key": .string("l1"), "_type": .string("link"), "href": .string("https://example.com")]]
        )
        assertSurvives(link)
    }

    func testLossyBlocksStayFenced() {
        let paren = paragraph(
            [span("wiki", marks: ["l1"])],
            defs: [["_key": .string("l1"), "_type": .string("link"), "href": .string("https://w.org/Foo_(bar)")]]
        )
        let underline = paragraph([span("under", marks: ["underline"])])
        let softBreak = paragraph([span("line one\nline two")])
        let listLooking = paragraph([span("1999. A year")])
        var custom = paragraph([span("lead")])
        custom["style"] = .string("lead")
        for block in [paren, underline, softBreak, listLooking, custom] {
            XCTAssertTrue(PortableText.toMarkdown([.object(block)]).hasPrefix("<!--ec:block"), "\(block)")
            assertSurvives(block)
        }
    }

    func testEmptyParagraphSurvives() {
        let blocks: [JSONValue] = [
            .object(paragraph([span("a")])), .object(paragraph([span("")])), .object(paragraph([span("b")])),
        ]
        let again = PortableText.fromMarkdown(PortableText.toMarkdown(blocks))
        XCTAssertEqual(again.count, 3)
    }

    func testEditorEmphasisFormsSave() {
        let blocks = PortableText.fromMarkdown("An *italic* and __bold__ word.\n")
        let children = blocks.first?.object?["children"]?.array ?? []
        let marked = children.compactMap(\.object).filter { !($0["marks"]?.array ?? []).isEmpty }
        XCTAssertEqual(marked.map { $0["text"]?.string }, ["italic", "bold"])
    }

    // MARK: Helpers

    private func assertSurvives(_ block: [String: JSONValue], file: StaticString = #filePath, line: UInt = #line) {
        let again = PortableText.fromMarkdown(PortableText.toMarkdown([.object(block)]))
        XCTAssertEqual(again.count, 1, file: file, line: line)
        guard let object = again.first?.object else { return }
        XCTAssertEqual(PortableText.normalized(object), PortableText.normalized(block), file: file, line: line)
    }

    private func paragraph(_ children: [JSONValue], defs: [[String: JSONValue]] = []) -> [String: JSONValue] {
        [
            "_type": .string("block"),
            "_key": .string("k"),
            "style": .string("normal"),
            "markDefs": .array(defs.map { .object($0) }),
            "children": .array(children),
        ]
    }

    private func span(_ text: String, marks: [String] = []) -> JSONValue {
        .object([
            "_type": .string("span"), "_key": .string("s"), "text": .string(text),
            "marks": .array(marks.map { .string($0) }),
        ])
    }
}
