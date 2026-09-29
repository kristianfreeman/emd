import AppKit
import XCTest

@testable import EmDashWriter

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
