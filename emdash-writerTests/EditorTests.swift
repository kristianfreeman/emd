import XCTest

@testable import EmDashWriter

final class EditorTests: XCTestCase {
    func testMarkdownStylesHideMarkers() {
        let view = QuietTextView.editor()
        view.frame = NSRect(x: 0, y: 0, width: 680, height: 400)
        view.font = .systemFont(ofSize: 15)
        view.textColor = .labelColor
        view.string = "Say **hi** and *there* and [site](https://example.com).\nNext line."
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        view.restyle()
        guard let layout = view.layoutManager, let container = view.textContainer, let storage = view.textStorage else {
            XCTFail("text view has no layout manager")
            return
        }
        layout.ensureLayout(for: container)
        let ns = view.string as NSString
        let hi = ns.range(of: "hi")
        let there = ns.range(of: "there")
        let site = ns.range(of: "site")
        let hiFont = storage.attribute(.font, at: hi.location, effectiveRange: nil) as? NSFont
        let thereFont = storage.attribute(.font, at: there.location, effectiveRange: nil) as? NSFont
        XCTAssertTrue(NSFontManager.shared.traits(of: hiFont ?? .systemFont(ofSize: 15)).contains(.boldFontMask))
        XCTAssertTrue(NSFontManager.shared.traits(of: thereFont ?? .systemFont(ofSize: 15)).contains(.italicFontMask))
        XCTAssertEqual(
            storage.attribute(.underlineStyle, at: site.location, effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue)
        let star = ns.range(of: "**").location
        let starGlyph = layout.glyphIndexForCharacter(at: star)
        XCTAssertTrue(layout.propertyForGlyph(at: starGlyph).contains(.null))
        XCTAssertEqual(layout.glyph(at: starGlyph), 0)
    }

    func testLinkStyleStaysOnTheLabel() {
        let view = QuietTextView.editor()
        view.frame = NSRect(x: 0, y: 0, width: 680, height: 400)
        view.configure(
            TextLook(
                font: .systemFont(ofSize: 15),
                ink: TextInk(color: .labelColor, muted: .secondaryLabelColor, paper: .textBackgroundColor),
                lineHeight: 1.32,
                paragraphSpacing: 15 * 0.28
            ))
        view.string = "Paragraph above the link.\nSee [the site](https://example.com) today."
        view.restyle()
        guard let layout = view.layoutManager, let container = view.textContainer, let storage = view.textStorage else {
            return XCTFail("text view has no layout manager")
        }
        layout.ensureLayout(for: container)
        let ns = view.string as NSString
        let site = ns.range(of: "the site")
        var effective = NSRange()
        let underline = storage.attribute(.underlineStyle, at: site.location, effectiveRange: &effective) as? Int
        XCTAssertEqual(underline, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(effective, site)
        let above = ns.range(of: "Paragraph")
        XCTAssertNil(storage.attribute(.underlineStyle, at: above.location, effectiveRange: nil))
        let siteRect = layout.boundingRect(
            forGlyphRange: layout.glyphRange(forCharacterRange: site, actualCharacterRange: nil), in: container)
        let aboveRect = layout.boundingRect(
            forGlyphRange: layout.glyphRange(forCharacterRange: above, actualCharacterRange: nil), in: container)
        XCTAssertGreaterThan(siteRect.minY, aboveRect.maxY - 1)
        view.setSelectedRange(site)
        view.restyleCaretLine()
        var shown = NSRange()
        let shownUnderline = storage.attribute(.underlineStyle, at: site.location, effectiveRange: &shown) as? Int
        XCTAssertEqual(shownUnderline, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(shown, site)
        let selected = layout.boundingRect(
            forGlyphRange: layout.glyphRange(forCharacterRange: view.selectedRange(), actualCharacterRange: nil),
            in: container)
        XCTAssertGreaterThan(selected.minY, aboveRect.maxY - 1)
    }

    func testInlineMarkdownRuns() {
        let line = "Say **hi** and _go_ and *there* to [the site](https://example.com)."
        let runs = MarkdownRuns.inline(in: line)
        XCTAssertEqual(runs.map(\.kind), [.bold, .italic, .italic, .link])
        XCTAssertEqual((line as NSString).substring(with: runs[0].inner), "hi")
        XCTAssertEqual((line as NSString).substring(with: runs[1].inner), "go")
        XCTAssertEqual((line as NSString).substring(with: runs[2].inner), "there")
        XCTAssertEqual((line as NSString).substring(with: runs[3].inner), "the site")
        XCTAssertEqual((line as NSString).substring(with: runs[0].markers[0]), "**")
        XCTAssertEqual((line as NSString).substring(with: runs[3].markers[1]), "](https://example.com)")
    }

    func testPartialRestyleLeavesTheRestOfThePost() {
        let view = QuietTextView.editor()
        view.frame = NSRect(x: 0, y: 0, width: 680, height: 800)
        view.font = .systemFont(ofSize: 15)
        view.textColor = .labelColor
        let first = "Say **hi** here."
        let last = "And **go** there."
        var lines = [first]
        for index in 0..<80 {
            lines.append("Filler line \(index) with **bold** and [site](https://example.com).")
        }
        lines.append(last)
        view.string = lines.joined(separator: "\n")
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        view.restyle()
        guard let layout = view.layoutManager, let storage = view.textStorage else {
            XCTFail("text view has no layout manager")
            return
        }
        layout.ensureLayout(for: view.textContainer!)
        let ns = view.string as NSString
        let firstStar = ns.range(of: "**").location
        let lastLine = ns.lineRange(for: NSRange(location: ns.length - 1, length: 0))
        view.restyle(around: lastLine)
        layout.ensureLayout(for: view.textContainer!)
        let firstGlyph = layout.glyphIndexForCharacter(at: firstStar)
        XCTAssertTrue(layout.propertyForGlyph(at: firstGlyph).contains(.null))
        let go = ns.range(of: "go", options: .backwards)
        let goFont = storage.attribute(.font, at: go.location, effectiveRange: nil) as? NSFont
        XCTAssertTrue(NSFontManager.shared.traits(of: goFont ?? .systemFont(ofSize: 15)).contains(.boldFontMask))
    }

    func testRestyleOfOneLineIsMuchCheaperThanTheWholePost() {
        let view = QuietTextView.editor()
        view.frame = NSRect(x: 0, y: 0, width: 680, height: 800)
        view.font = .systemFont(ofSize: 15)
        view.textColor = .labelColor
        let line = "Say **hi** and *there* to [the site](https://example.com)."
        view.string = Array(repeating: line, count: 400).joined(separator: "\n")
        view.setSelectedRange(NSRange(location: 0, length: 0))
        Pace.reset()
        view.restyle()
        let full = Pace.snapshot().last?.milliseconds ?? -1
        Pace.reset()
        let edited = NSRange(location: 0, length: 0)
        for _ in 0..<20 {
            view.restyle(around: edited)
        }
        let partials = Pace.snapshot().map(\.milliseconds)
        let average = partials.reduce(0, +) / Double(max(partials.count, 1))
        print("restyle full \(String(format: "%.2f", full))ms partial avg \(String(format: "%.2f", average))ms")
        XCTAssertGreaterThan(full, 0)
        XCTAssertLessThan(average, full * 0.35)
    }

    func testRelayoutAfterAKeystrokeStaysCheap() {
        let column = ColumnView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        column.bodyView.font = .systemFont(ofSize: 15)
        let line = "Say **hi** and *there* to [the site](https://example.com)."
        column.bodyView.string = Array(repeating: line, count: 400).joined(separator: "\n")
        column.bodyView.restyle()
        Pace.reset()
        column.layout()
        let cold = Pace.snapshot().filter { $0.name == "layout" }.map(\.milliseconds).max() ?? -1
        Pace.reset()
        column.bodyView.setSelectedRange(NSRange(location: 0, length: 0))
        column.bodyView.insertText("Z", replacementRange: NSRange(location: 0, length: 0))
        column.bodyView.restyle(around: NSRange(location: 0, length: 1))
        column.layout()
        let edited = Pace.snapshot().filter { $0.name == "layout" }.map(\.milliseconds).max() ?? -1
        print("layout cold \(String(format: "%.2f", cold))ms edited \(String(format: "%.2f", edited))ms")
        XCTAssertGreaterThan(cold, 0)
        XCTAssertLessThan(edited, max(8, cold * 0.45))
    }
}

extension EditorTests {
    func testTypingInAHeadingKeepsItsSize() {
        let view = QuietTextView.editor()
        view.frame = NSRect(x: 0, y: 0, width: 680, height: 400)
        view.configure(
            TextLook(
                font: .systemFont(ofSize: 15),
                ink: TextInk(color: .labelColor, muted: .secondaryLabelColor, paper: .textBackgroundColor),
                lineHeight: 1.3,
                paragraphSpacing: 4
            ))
        view.string = "# Hi"
        view.setSelectedRange(NSRange(location: 4, length: 0))
        view.restyle()
        let first = (view.textStorage?.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)?.pointSize
        for letter in ["t", "h", "e", "r", "e"] {
            view.insertText(letter, replacementRange: view.selectedRange())
            view.restyle(around: view.selectedRange())
        }
        let last = (view.textStorage?.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)?.pointSize
        XCTAssertEqual(first ?? 0, 15 * 1.34, accuracy: 0.01)
        XCTAssertEqual(last, first)
    }
}

extension EditorTests {
    func testFenceStateAtEachLine() {
        let view = QuietTextView.editor()
        let text = "intro ``` not a fence\n```swift\nlet x = 1\n  ```\nafter\n```\nopen at end"
        let ns = text as NSString
        func open(before line: String) -> Bool {
            view.fenceOpen(before: ns.range(of: line).location, ns: ns)
        }
        XCTAssertFalse(open(before: "intro"))
        XCTAssertFalse(open(before: "```swift"))
        XCTAssertTrue(open(before: "let x"))
        XCTAssertTrue(open(before: "  ```"))
        XCTAssertFalse(open(before: "after"))
        XCTAssertTrue(open(before: "open at end"))
    }
}

extension EditorTests {
    func testHiddenMarkersMoveWithTheText() {
        XCTAssertEqual(
            QuietTextView.shifted(IndexSet([2, 3, 10]), edited: NSRange(location: 0, length: 1), delta: 1),
            IndexSet([3, 4, 11]))
        XCTAssertEqual(
            QuietTextView.shifted(IndexSet([2, 3, 10]), edited: NSRange(location: 3, length: 0), delta: -4),
            IndexSet([2, 6]))
        let view = QuietTextView.editor()
        view.font = .systemFont(ofSize: 15)
        view.string = "One **two** three.\nNext **line** here."
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.restyle()
        let before = view.hiddenCharacters
        view.insertText("XY", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(view.hiddenCharacters, IndexSet(before.map { $0 + 2 }))
    }

    /// Typing in the middle of a long post lays out what is on screen, not everything after the edit.
    func testTypingMidwayThroughALongPostStaysCheap() {
        let line = "Say **hi** and *there* to [the site](https://example.com), with more words to wrap the line.\n"
        let column = ColumnView(frame: NSRect(x: 0, y: 0, width: 1000, height: 800))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 1000, height: 800))
        scroll.documentView = column
        column.bodyView.configure(
            TextLook(
                font: WriterFont.geistSans.nsFont(size: 16),
                ink: TextInk(color: .black, muted: .gray, paper: .white),
                lineHeight: 1.32,
                paragraphSpacing: 16 * 0.28
            ))
        column.bodyView.string = String(repeating: line, count: 1200)
        column.bodyView.restyle()
        column.layout()
        column.bodyView.setSelectedRange(NSRange(location: 60000, length: 0))
        column.bodyView.scrollRangeToVisible(column.bodyView.selectedRange())
        var times: [Double] = []
        for letter in "The quick brown fox jumps over the lazy dog." {
            let started = CFAbsoluteTimeGetCurrent()
            let at = column.bodyView.selectedRange().location
            column.bodyView.insertText(String(letter), replacementRange: NSRange(location: NSNotFound, length: 0))
            column.bodyView.restyle(around: NSRange(location: at, length: 1))
            column.noteTyping()
            column.layoutSubtreeIfNeeded()
            times.append((CFAbsoluteTimeGetCurrent() - started) * 1000)
        }
        let median = times.sorted()[times.count / 2]
        print("keystroke median \(String(format: "%.2f", median))ms, max \(String(format: "%.2f", times.max() ?? 0))ms")
        XCTAssertLessThan(median, 8)
        // Stale marker positions made TextKit rebuild glyphs for the whole post in bursts: over 100ms a key.
        XCTAssertLessThan(times.max() ?? 0, 30)
        withExtendedLifetime(scroll) {}
    }
}
