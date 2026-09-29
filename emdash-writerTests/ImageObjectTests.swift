import AppKit
import XCTest

@testable import EmDashWriter

final class ImageObjectTests: XCTestCase {
    private let line = "![](https://example.invalid/a.png =400x200)"

    private func editor() -> (QuietTextView, NSRange) {
        let view = QuietTextView.editor()
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 600)
        view.textContainer?.size = NSSize(width: 500, height: 10000)
        view.configure(
            TextLook(
                font: .systemFont(ofSize: 15),
                ink: TextInk(color: .black, muted: .gray, paper: .white),
                lineHeight: 1.3,
                paragraphSpacing: 4
            ))
        view.string = "Hello.\n\n" + line + "\n\nAfter."
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.restyle()
        return (view, (view.string as NSString).range(of: line))
    }

    func testArrowingOntoAPictureSelectsItThenMovesPast() {
        let (view, image) = editor()
        view.setSelectedRange(NSRange(location: image.location + 5, length: 0))
        XCTAssertEqual(view.selectedRange(), NSRange(location: image.location, length: 0))
        XCTAssertTrue(view.isImageObjectSelected(image))
        view.setSelectedRange(NSRange(location: image.location + 1, length: 0))
        XCTAssertEqual(view.selectedRange().location, NSMaxRange(image) + 1)
        view.setSelectedRange(NSRange(location: NSMaxRange(image), length: 0))
        XCTAssertEqual(view.selectedRange().location, image.location)
    }

    func testASelectionTakesTheWholePicture() {
        let (view, image) = editor()
        view.setSelectedRange(NSRange(location: 2, length: image.location + 4 - 2))
        XCTAssertEqual(NSMaxRange(view.selectedRange()), NSMaxRange(image))
    }

    func testTypingOnAPictureStartsAParagraphAfterIt() {
        let (view, image) = editor()
        view.setSelectedRange(NSRange(location: image.location, length: 0))
        view.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(view.string, "Hello.\n\n" + line + "\n\nx\n\nAfter.")
    }

    func testDeleteRemovesThePictureAndItsBlankLine() {
        let (view, image) = editor()
        view.setSelectedRange(NSRange(location: image.location, length: 0))
        view.deleteBackward(nil)
        XCTAssertEqual(view.string, "Hello.\n\nAfter.")
    }
}

extension ImageObjectTests {
    func testTheCaretHidesWhileAPictureIsSelected() {
        let (view, image) = editor()
        view.setSelectedRange(NSRange(location: image.location, length: 0))
        XCTAssertEqual(view.insertionPointColor, .clear)
        view.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertNotEqual(view.insertionPointColor, .clear)
    }
}
