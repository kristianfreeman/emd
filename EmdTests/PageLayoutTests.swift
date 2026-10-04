import AppKit
import XCTest

@testable import Emd

/// Custom blocks come from the manifest and round-trip as the EmDash admin writes them; a page's regions load
/// into one text and save back into their own fields.
final class PageLayoutTests: XCTestCase {
    /// The `page-blocks` plugin as kristianfreeman.com declares it, plus a disabled plugin and a bare embed.
    private let manifest: JSONValue = .object([
        "plugins": .object([
            "page-blocks": .object([
                "enabled": .bool(true),
                "portableTextBlocks": .array([
                    .object([
                        "type": .string("musicList"), "label": .string("Music list"), "icon": .string("list"),
                        "category": .string("Sections"), "description": .string("Releases and mixes"),
                        "fields": .array([
                            .object([
                                "type": .string("text_input"), "action_id": .string("heading"),
                                "label": .string("Heading"), "initial_value": .string("Music"),
                            ]),
                            .object([
                                "type": .string("number_input"), "action_id": .string("limit"),
                                "label": .string("How many"), "initial_value": .number(12), "min": .number(1),
                                "max": .number(50),
                            ]),
                            .object([
                                "type": .string("select"), "action_id": .string("include"), "label": .string("Include"),
                                "initial_value": .string("all"),
                                "options": .array([
                                    .object(["label": .string("Releases and mixes"), "value": .string("all")]),
                                    .object(["label": .string("Releases only"), "value": .string("releases")]),
                                ]),
                            ]),
                        ]),
                    ])
                ]),
            ]),
            "off": .object([
                "enabled": .bool(false),
                "portableTextBlocks": .array([.object(["type": .string("hidden"), "label": .string("Hidden")])]),
            ]),
            "embeds": .object([
                "portableTextBlocks": .array([
                    .object([
                        "type": .string("youtube"), "label": .string("YouTube"), "placeholder": .string("https://"),
                    ])
                ])
            ]),
        ])
    ])

    private var music: BlockDef { PageBlocks.definitions(fromManifest: manifest)["musicList"]! }

    func testDefinitionsComeFromEnabledPlugins() {
        let definitions = PageBlocks.definitions(fromManifest: manifest)
        XCTAssertEqual(Set(definitions.keys), ["musicList", "youtube"])
        XCTAssertEqual(music.category, "Sections")
        XCTAssertEqual(music.fields.map(\.kind), [.text, .number, .choice])
        XCTAssertEqual(music.fields[1].maximum, 50)
        XCTAssertEqual(definitions["youtube"]?.fields.map(\.actionID), ["url"])
        XCTAssertEqual(definitions["youtube"]?.category, "Embeds")
    }

    func testANewBlockHasEveryFieldAndAnEmptyID() {
        let block = PageBlocks.newBlock(music)
        XCTAssertEqual(block["_type"], .string("musicList"))
        XCTAssertEqual(block["id"], .string(""))
        XCTAssertEqual(block["heading"], .string("Music"))
        XCTAssertEqual(block["limit"], .number(12))
        XCTAssertEqual(block["include"], .string("all"))
        XCTAssertNotNil(block["_key"]?.string)
    }

    func testEditingKeepsOtherKeysAndWritesNumbers() {
        let stored: [String: JSONValue] = [
            "_type": .string("musicList"), "_key": .string("k1"), "heading": .string("Music"), "limit": .string("8"),
            "extra": .string("kept"),
        ]
        let edited = PageBlocks.applying(["heading": .string("Listen")], to: stored, definition: music)
        XCTAssertEqual(edited["heading"], .string("Listen"))
        XCTAssertEqual(edited["limit"], .number(8))
        XCTAssertEqual(edited["include"], .string("all"))
        XCTAssertEqual(edited["extra"], .string("kept"))
        XCTAssertEqual(edited["_key"], .string("k1"))
        XCTAssertEqual(edited["id"], .string(""))
        XCTAssertEqual(
            PageBlocks.summary(edited, definition: music),
            "Heading: “Listen” · How many: 8 · Include: Releases and mixes")
    }

    func testABlockLineSavesAsTheSameBlock() {
        let block = PageBlocks.newBlock(music)
        let line = BlockLine.line(block)
        XCTAssertEqual(BlockLine.block(line), block)
        XCTAssertEqual(PortableText.fromMarkdown(line).first?.object, block)
        XCTAssertEqual(PortableText.toMarkdown([.object(block)]), line + "\n")
    }

    // MARK: Regions

    private let page = CollectionDef(
        slug: "pages", label: "Pages", labelSingular: "Page",
        fields: [
            FieldDef(slug: "title", label: "Title", type: "string", required: true, sortOrder: 0),
            FieldDef(slug: "layout", label: "Layout", type: "select", required: false, sortOrder: 1),
            FieldDef(slug: "main", label: "Main", type: "portableText", required: false, sortOrder: 3),
            FieldDef(slug: "aside", label: "Aside", type: "portableText", required: false, sortOrder: 2),
        ])

    func testOnlyEntriesWithSeveralRichFieldsHaveRegions() {
        XCTAssertEqual(page.regionFields.map(\.slug), ["aside", "main"])
        let post = CollectionDef(
            slug: "posts", label: "Posts", labelSingular: "Post",
            fields: [FieldDef(slug: "content", label: "Content", type: "portableText", required: false, sortOrder: 1)])
        XCTAssertTrue(post.regionFields.isEmpty)
    }

    func testRegionsLoadIntoOneTextAndSplitBack() {
        let data: [String: JSONValue] = ["aside": .string("# Kristian\n\nHello.\n"), "main": .string("Music below.\n")]
        let text = EmDashClient.body(data, collection: page)
        XCTAssertEqual(
            text, "<!--emd:region aside-->\n\n# Kristian\n\nHello.\n\n<!--emd:region main-->\n\nMusic below.")
        XCTAssertEqual(
            Regions.split(text, slugs: ["aside", "main"]), ["aside": "# Kristian\n\nHello.", "main": "Music below."])
    }

    func testAMissingMarkerNeverMovesTextIntoAnotherRegion() {
        let split = Regions.split("Stray words.\n\n<!--emd:region main-->\n\nMain.", slugs: ["aside", "main"])
        XCTAssertEqual(split, ["aside": "Stray words.", "main": "Main."])
        XCTAssertEqual(Regions.split("<!--emd:region aside-->\n\nOnly aside.", slugs: ["aside", "main"])["main"], "")
    }

    func testEmptyRegionsKeepTheirMarkers() {
        XCTAssertEqual(
            Regions.joined([("aside", ""), ("main", "")]), "<!--emd:region aside-->\n\n<!--emd:region main-->")
    }

    func testMarkersAreNotWords() {
        XCTAssertEqual(WriterText.readableWords(in: "<!--emd:region aside-->\n\nTwo words."), 2)
    }
}

/// A divider cannot be deleted or joined onto, and a card acts as one object.
final class RegionEditorTests: XCTestCase {
    private var coordinator: WritingColumn.Coordinator?

    @MainActor
    private func editor(_ text: String) -> QuietTextView {
        let view = QuietTextView.editor()
        let coordinator = WritingColumn.Coordinator.probe()
        coordinator.undo.groupsByEvent = false
        self.coordinator = coordinator
        view.delegate = coordinator
        view.configure(
            TextLook(
                font: .systemFont(ofSize: 15), ink: TextInk(color: .black, muted: .gray, paper: .white),
                lineHeight: 1.3, paragraphSpacing: 4))
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 400)
        view.textContainer?.size = NSSize(width: 500, height: 10000)
        view.regionLabels = ["aside": "Aside", "main": "Main"]
        view.string = text
        view.restyle()
        return view
    }

    private let text = "<!--emd:region aside-->\n\nHello.\n\n<!--emd:region main-->\nMain text."

    @MainActor
    func testTypingInARegionIsFine() {
        let view = editor(text)
        let at = (text as NSString).range(of: "Hello").location
        XCTAssertFalse(view.breaksDivider(NSRange(location: at, length: 5), with: "Hi"))
    }

    @MainActor
    func testADividerCannotBeDeletedOrJoined() {
        let view = editor(text)
        let ns = text as NSString
        let main = ns.range(of: "<!--emd:region main-->")
        XCTAssertTrue(view.breaksDivider(main, with: ""))
        XCTAssertTrue(view.breaksDivider(NSRange(location: 0, length: ns.length), with: ""))
        XCTAssertTrue(view.breaksDivider(NSRange(location: NSMaxRange(main), length: 1), with: ""))
        XCTAssertTrue(view.breaksDivider(NSRange(location: main.location + 3, length: 0), with: "x"))
        XCTAssertFalse(view.breaksDivider(NSRange(location: main.location - 1, length: 1), with: ""))
    }

    @MainActor
    func testInsertingABlockGivesItAParagraphOfItsOwn() {
        let view = editor("<!--emd:region aside-->\n\nIntro.\n\n<!--emd:region main-->\n\nMain.")
        let definition = BlockDef(
            type: "postList", label: "Writing list",
            fields: [BlockField(kind: .number, actionID: "limit", label: "How many", initial: .number(8))])
        view.setSelectedRange(NSRange(location: (view.string as NSString).range(of: "Intro").location + 2, length: 0))
        coordinator?.undo.beginUndoGrouping()
        view.insertBlock(definition)
        coordinator?.undo.endUndoGrouping()
        let lines = view.string.components(separatedBy: "\n")
        XCTAssertEqual(lines[2], "Intro.")
        XCTAssertEqual(lines[3], "")
        XCTAssertEqual(BlockLine.block(lines[4])?["limit"], .number(8))
        XCTAssertEqual(lines[5], "")
        XCTAssertEqual(lines[6], "<!--emd:region main-->")
    }

    @MainActor
    func testDividersAndCardsAreObjects() {
        let view = editor(text)
        XCTAssertNotNil(view.imageContent(around: 0))
        let block = BlockLine.line(["_type": .string("postList"), "_key": .string("k"), "id": .string("")])
        view.blockDefs = ["postList": BlockDef(type: "postList", label: "Writing list", fields: [])]
        view.string = "Intro.\n\n\(block)\n\nAfter."
        view.restyle()
        XCTAssertNotNil(view.imageContent(around: 8))
        XCTAssertNotNil(view.card(NSRange(location: 8, length: (block as NSString).length)))
    }
}
