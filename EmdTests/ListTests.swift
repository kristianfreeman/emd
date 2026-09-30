import AppKit
import XCTest

@testable import Emd

final class ListTests: XCTestCase {
    private func editor(_ text: String, caret: Int? = nil) -> QuietTextView {
        let view = QuietTextView.editor()
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 400)
        view.textContainer?.size = NSSize(width: 500, height: 10000)
        view.configure(
            TextLook(
                font: .systemFont(ofSize: 15),
                ink: TextInk(color: .black, muted: .gray, paper: .white),
                lineHeight: 1.3,
                paragraphSpacing: 4
            ))
        view.string = text
        view.setSelectedRange(NSRange(location: caret ?? (text as NSString).length, length: 0))
        view.restyle()
        return view
    }

    func testNumberedItemsCountUpByLevel() {
        let lines = ["1. a", "1. b", "  1. c", "  1. d", "1. e", "", "1. f", "```", "1. code", "```"]
        XCTAssertEqual(
            PortableText.renumbered(lines),
            ["1. a", "2. b", "  1. c", "  2. d", "3. e", "", "1. f", "```", "1. code", "```"])
    }

    func testReturnContinuesAndEndsAList() {
        let view = editor("- one")
        view.insertNewline(nil)
        XCTAssertEqual(view.string, "- one\n- ")
        view.insertNewline(nil)
        XCTAssertEqual(view.string, "- one\n")
        let numbered = editor("3. three")
        numbered.insertNewline(nil)
        XCTAssertEqual(numbered.string, "3. three\n4. ")
    }

    func testTabNestsAnItem() {
        let view = editor("- one\n- two")
        view.insertTab(nil)
        XCTAssertEqual(view.string, "- one\n  - two")
        view.insertBacktab(nil)
        XCTAssertEqual(view.string, "- one\n- two")
    }

    func testBulletsAreMarkedAndPicturesSkipSpelling() {
        let view = editor("- one\n\n![](https://example.invalid/a.png =400x200)", caret: 0)
        XCTAssertTrue(view.bulletCharacters.contains(0))
        let image = (view.string as NSString).range(of: "![](")
        XCTAssertFalse(view.allowsSpelling(in: NSRange(location: image.location + 5, length: 4)))
        XCTAssertTrue(view.allowsSpelling(in: NSRange(location: 2, length: 3)))
    }
}
