import XCTest
@testable import EmDashWriter

final class WriterTests: XCTestCase {
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
        let written = PortableText.portableData(from: [
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

    func testSiteURL() {
        let url = SiteURL.normalize(" Example.com/blog ")
        XCTAssertEqual(url?.absoluteString, "https://example.com")
        XCTAssertEqual(
            SiteURL.endpoint(site: url!, path: "/content/posts?limit=100").absoluteString,
            "https://example.com/_emdash/api/content/posts?limit=100"
        )
        XCTAssertNil(SiteURL.normalize("not a url :::"))
    }

    func testCollectionChoosesPostFields() {
        let collection = CollectionDef(
            slug: "posts",
            label: "Posts",
            labelSingular: "Post",
            fields: [
                FieldDef(slug: "title", label: "Title", type: "string", required: true, sortOrder: 0),
                FieldDef(slug: "excerpt", label: "Excerpt", type: "text", required: false, sortOrder: 1),
                FieldDef(slug: "content", label: "Content", type: "portableText", required: false, sortOrder: 2),
            ]
        )
        XCTAssertEqual(collection.titleField?.slug, "title")
        XCTAssertEqual(collection.bodyField?.slug, "content")
        XCTAssertEqual(collection.excerptField?.slug, "excerpt")
    }

    func testClientLoadsDraftAsMarkdown() async throws {
        let protocolBox = MockURLProtocol.self
        protocolBox.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/compare") {
                let body: [String: Any] = [
                    "success": true,
                    "data": [
                        "hasChanges": true,
                        "draft": [
                            "title": "Draft title",
                            "content": [
                                [
                                    "_type": "block",
                                    "style": "normal",
                                    "children": [["_type": "span", "text": "Draft body"]],
                                ],
                            ],
                        ],
                    ],
                ]
                return (200, try JSONSerialization.data(withJSONObject: body))
            }
            let body: [String: Any] = [
                "success": true,
                "data": [
                    "item": [
                        "id": "post1",
                        "slug": "launch",
                        "status": "published",
                        "draftRevisionId": "draft1",
                        "updatedAt": "2026-09-28T12:00:00Z",
                        "data": [
                            "title": "Live title",
                            "content": [
                                [
                                    "_type": "block",
                                    "style": "normal",
                                    "children": [["_type": "span", "text": "Live body"]],
                                ],
                            ],
                        ],
                    ],
                    "_rev": "rev1",
                ],
            ]
            return (200, try JSONSerialization.data(withJSONObject: body))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [protocolBox]
        let client = EmDashClient(
            site: URL(string: "https://example.com")!,
            token: "secret",
            session: URLSession(configuration: configuration)
        )
        let collection = CollectionDef(
            slug: "posts",
            label: "Posts",
            labelSingular: "Post",
            fields: [
                FieldDef(slug: "title", label: "Title", type: "string", required: true, sortOrder: 0),
                FieldDef(slug: "content", label: "Content", type: "portableText", required: false, sortOrder: 1),
            ]
        )
        let entry = try await client.load(collection: collection, id: "post1")
        XCTAssertEqual(entry.title, "Draft title")
        XCTAssertEqual(entry.body, "Draft body")
        XCTAssertEqual(entry.rev, "rev1")
        XCTAssertEqual(entry.status, "published")
    }

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
        XCTAssertEqual(storage.attribute(.underlineStyle, at: site.location, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        let star = ns.range(of: "**").location
        let starGlyph = layout.glyphIndexForCharacter(at: star)
        XCTAssertTrue(layout.propertyForGlyph(at: starGlyph).contains(.null))
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

    func testClientSurfacesConflict() async throws {
        MockURLProtocol.handler = { _ in
            let body = [
                "success": false,
                "error": ["code": "CONFLICT", "message": "stale"],
            ] as [String: Any]
            return (409, try JSONSerialization.data(withJSONObject: body))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = EmDashClient(
            site: URL(string: "https://example.com")!,
            token: "secret",
            session: URLSession(configuration: configuration)
        )
        do {
            _ = try await client.settings()
            XCTFail("expected conflict")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "CONFLICT")
            XCTAssertTrue(error.message.contains("Reload"))
        }
    }

    func testUpdateReadsTheWriteResponse() async throws {
        var calls: [(String, String)] = []
        MockURLProtocol.handler = { request in
            calls.append((request.httpMethod ?? "", request.url?.path ?? ""))
            let sent = Self.requestBody(request)
            let json = try JSONSerialization.jsonObject(with: sent) as? [String: Any]
            XCTAssertEqual(json?["skipRevision"] as? Bool, true)
            let body: [String: Any] = [
                "success": true,
                "data": [
                    "item": [
                        "id": "post1",
                        "slug": "launch",
                        "status": "published",
                        "updatedAt": "2026-09-29T12:00:00.000Z",
                        "version": 4,
                        "draftRevisionId": "draft9",
                    ],
                    "_rev": "rev-from-write",
                ],
            ]
            return (200, try JSONSerialization.data(withJSONObject: body))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = EmDashClient(
            site: URL(string: "https://example.com")!,
            token: "secret",
            session: URLSession(configuration: configuration)
        )
        let collection = CollectionDef(
            slug: "posts",
            label: "Posts",
            labelSingular: "Post",
            fields: [
                FieldDef(slug: "title", label: "Title", type: "string", required: true, sortOrder: 0),
                FieldDef(slug: "content", label: "Content", type: "portableText", required: false, sortOrder: 1),
            ]
        )
        let entry = try await client.update(
            collection: collection,
            id: "post1",
            rev: "rev-old",
            title: "Launch",
            body: "Hello",
            excerpt: "",
            slug: "launch",
            skipRevision: true
        )
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.0, "PUT")
        XCTAssertTrue(calls.first?.1.hasSuffix("/content/posts/post1") == true)
        XCTAssertEqual(entry.rev, "rev-from-write")
        XCTAssertEqual(entry.draftRevisionID, "draft9")
        XCTAssertEqual(entry.status, "published")
    }

    func testPublishEncodesRevWhenTheResponseOmitsIt() async throws {
        MockURLProtocol.handler = { _ in
            let body: [String: Any] = [
                "success": true,
                "data": [
                    "item": [
                        "id": "post1",
                        "slug": "launch",
                        "status": "published",
                        "updatedAt": "2026-09-29T12:00:00.000Z",
                        "version": 8,
                    ],
                ],
            ]
            return (200, try JSONSerialization.data(withJSONObject: body))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = EmDashClient(
            site: URL(string: "https://example.com")!,
            token: "secret",
            session: URLSession(configuration: configuration)
        )
        let collection = CollectionDef(
            slug: "posts",
            label: "Posts",
            labelSingular: "Post",
            fields: [FieldDef(slug: "title", label: "Title", type: "string", required: true, sortOrder: 0)]
        )
        let entry = try await client.publish(collection: collection, id: "post1")
        let expected = Data("8:2026-09-29T12:00:00.000Z".utf8).base64EncodedString()
        XCTAssertEqual(entry.rev, expected)
        XCTAssertEqual(entry.status, "published")
        XCTAssertNil(entry.draftRevisionID)
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
        column.titleView.font = .systemFont(ofSize: 18)
        let line = "Say **hi** and *there* to [the site](https://example.com)."
        column.bodyView.string = Array(repeating: line, count: 400).joined(separator: "\n")
        column.titleView.string = "Launch"
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

extension WriterTests {
    fileprivate static func requestBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody, !body.isEmpty { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 4096)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
