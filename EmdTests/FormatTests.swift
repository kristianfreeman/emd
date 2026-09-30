import AppKit
import XCTest

@testable import Emd

final class FormatTests: XCTestCase {
    private func editor(_ text: String, selection: NSRange) -> QuietTextView {
        let view = QuietTextView.editor()
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 400)
        view.textContainer?.size = NSSize(width: 500, height: 10000)
        view.font = .systemFont(ofSize: 15)
        view.string = text
        view.setSelectedRange(selection)
        view.restyle()
        return view
    }

    func testBoldWrapsAndUnwraps() {
        let view = editor("make this bold", selection: NSRange(location: 5, length: 4))
        view.toggleMarker("**")
        XCTAssertEqual(view.string, "make **this** bold")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 7, length: 4))
        view.toggleMarker("**")
        XCTAssertEqual(view.string, "make this bold")
    }

    func testAnEmptySelectionGetsAPair() {
        let view = editor("x ", selection: NSRange(location: 2, length: 0))
        view.toggleMarker("_")
        XCTAssertEqual(view.string, "x __")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 3, length: 0))
    }

    func testTheLinkUnderTheCaretIsFound() {
        let view = editor("Read [the docs](https://example.com/a_b) now.", selection: NSRange(location: 8, length: 0))
        let link = view.linkAround(view.selectedRange())
        XCTAssertEqual(link?.label, "the docs")
        XCTAssertEqual(link?.address, "https://example.com/a_b")
        XCTAssertEqual(link?.whole, NSRange(location: 5, length: 35))
        XCTAssertNil(view.linkAround(NSRange(location: 1, length: 0)))
    }
}

extension FormatTests {
    func testPastingAnAddressOverWordsLinksThem() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("emd-tests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("https://example.com/a", forType: .string)
        let view = editor("read the docs today", selection: NSRange(location: 5, length: 8))
        XCTAssertTrue(view.pasteLinkOverSelection(pasteboard))
        XCTAssertEqual(view.string, "read [the docs](https://example.com/a) today")
        pasteboard.clearContents()
        pasteboard.setString("just words", forType: .string)
        let plain = editor("read the docs", selection: NSRange(location: 5, length: 3))
        XCTAssertFalse(plain.pasteLinkOverSelection(pasteboard))
        XCTAssertNil(QuietTextView.webAddress("mailto:someone@example.com"))
    }
}

extension FormatTests {
    func testLinkingAndUnlinking() {
        let view = editor("read the docs", selection: NSRange(location: 5, length: 8))
        view.applyLink(" https://example.com/(a) ", to: nil, selection: view.selectedRange())
        XCTAssertEqual(view.string, "read [the docs](https://example.com/(a%29)")
        let found = view.linkAround(NSRange(location: 8, length: 0))
        XCTAssertEqual(found?.address, "https://example.com/(a%29")
        view.applyLink("https://other.example", to: found, selection: NSRange(location: 8, length: 0))
        XCTAssertEqual(view.string, "read [the docs](https://other.example)")
        view.unlink(view.linkAround(NSRange(location: 8, length: 0)))
        XCTAssertEqual(view.string, "read the docs")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 5, length: 8))
    }

    func testANewLinkWithNothingSelectedSelectsItsLabel() {
        let view = editor("see ", selection: NSRange(location: 4, length: 0))
        view.applyLink("https://example.com", to: nil, selection: view.selectedRange())
        XCTAssertEqual(view.string, "see [link](https://example.com)")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 5, length: 4))
    }
}
