import AppKit
import XCTest

@testable import Emd

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
        XCTAssertEqual(view.selectedRange().location, NSMaxRange(image) + 2, "past the blank line, at After.")
        view.setSelectedRange(NSRange(location: NSMaxRange(image) + 1, length: 0))
        XCTAssertEqual(view.selectedRange().location, image.location, "the blank line after selects the picture")
        view.setSelectedRange(NSRange(location: image.location - 1, length: 0))
        XCTAssertEqual(view.selectedRange().location, 6, "one step back leaves for the end of Hello.")
        view.setSelectedRange(NSRange(location: 7, length: 0))
        XCTAssertEqual(view.selectedRange().location, image.location, "the blank line before selects the picture")
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

extension ImageObjectTests {
    func testArrowsStepOverHiddenLinkMarkdown() {
        let view = QuietTextView.editor()
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 400)
        view.textContainer?.size = NSSize(width: 500, height: 10000)
        view.font = .systemFont(ofSize: 15)
        view.string = "See [docs](https://example.com) now."
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.restyle()
        let labelEnd = 9
        let linkEnd = 31
        view.setSelectedRange(NSRange(location: labelEnd, length: 0))
        view.setSelectedRange(NSRange(location: labelEnd + 1, length: 0))
        XCTAssertEqual(view.selectedRange().location, linkEnd + 1, "right from the label goes past the space")
        view.setSelectedRange(NSRange(location: linkEnd, length: 0))
        view.setSelectedRange(NSRange(location: linkEnd - 1, length: 0))
        XCTAssertEqual(view.selectedRange().location, labelEnd - 1, "left from after the link goes into the label")
        view.setSelectedRange(NSRange(location: linkEnd, length: 0))
        view.deleteBackward(nil)
        XCTAssertEqual(view.string, "See [doc](https://example.com) now.", "backspace takes the label's last letter")
    }
}

extension ImageObjectTests {
    private func view(_ text: String, caret: Int = 0) -> QuietTextView {
        let view = QuietTextView.editor()
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 600)
        view.textContainer?.size = NSSize(width: 500, height: 10000)
        view.configure(
            TextLook(
                font: .systemFont(ofSize: 15), ink: TextInk(color: .black, muted: .gray, paper: .white),
                lineHeight: 1.3, paragraphSpacing: 4))
        view.string = text
        view.setSelectedRange(NSRange(location: caret, length: 0))
        view.restyle()
        return view
    }

    func testAPostEndingInAPictureKeepsItSelected() {
        let text = "Hi.\n\n" + line
        let view = view(text)
        let start = (text as NSString).range(of: line).location
        view.setSelectedRange(NSRange(location: start, length: 0))
        view.moveRight(nil)
        XCTAssertEqual(view.selectedRange().location, start, "nowhere to go, so the picture stays selected")
    }

    func testStepsBetweenTwoPicturesSelectEach() {
        let other = "![](https://example.invalid/b.png =400x200)"
        let text = line + "\n\n" + other + "\n\nEnd."
        let view = view(text, caret: (text as NSString).length)
        let second = (text as NSString).range(of: other).location
        view.setSelectedRange(NSRange(location: second, length: 0))
        view.setSelectedRange(NSRange(location: second - 1, length: 0))
        XCTAssertEqual(view.selectedRange().location, 0, "back from the second picture selects the first")
    }

    func testBackspaceUnderAPictureSelectsIt() {
        let text = line + "\nWorld"
        let view = view(text, caret: (text as NSString).length)
        view.setSelectedRange(NSRange(location: (line as NSString).length + 1, length: 0))
        view.deleteBackward(nil)
        XCTAssertEqual(view.string, text, "nothing deleted")
        XCTAssertEqual(view.selectedRange().location, 0)
    }

    func testASelectionThatOnlyTouchesAPictureLeavesIt() {
        let text = "Above\n" + line
        let view = view(text, caret: 0)
        view.setSelectedRange(NSRange(location: 0, length: 6))
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 6))
    }

    func testASelectionCanShrinkBackPastAPicture() {
        let text = "Above\n" + line + "\nBelow"
        let view = view(text, caret: 0)
        let image = (text as NSString).range(of: line)
        view.setSelectedRange(NSRange(location: 0, length: NSMaxRange(image) + 1))
        view.setSelectedRange(NSRange(location: 0, length: NSMaxRange(image) - 1))
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: image.location))
    }

    func testWordMovesAtALinksStart() {
        let view = view("See [docs](https://example.com) now.", caret: 4)
        view.moveWordRight(nil)
        XCTAssertEqual(view.selectedRange().location, 9, "from before a link, one word: to the end of its label")
        view.moveWordRight(nil)
        XCTAssertEqual(view.selectedRange().location, 35, "from the end of its label, past the address to now|")
        view.setSelectedRange(NSRange(location: 31, length: 0))
        view.moveWordLeft(nil)
        XCTAssertEqual(view.selectedRange().location, 5, "from after a link, back to the start of its label")
    }
}
