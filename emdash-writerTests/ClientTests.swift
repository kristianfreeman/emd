import XCTest

@testable import EmDashWriter

final class ClientTests: XCTestCase {
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
        MockURLProtocol.handler = MockURLProtocol.draftAndLive
        let entry = try await client().load(collection: contentPosts(), id: "post1")
        XCTAssertEqual(entry.title, "Draft title")
        XCTAssertEqual(entry.body, "Draft body")
        XCTAssertEqual(entry.rev, "rev1")
        XCTAssertEqual(entry.status, "published")
    }

    func testClientSurfacesConflict() async throws {
        MockURLProtocol.handler = MockURLProtocol.conflict
        do {
            _ = try await client().settings()
            XCTFail("expected conflict")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "CONFLICT")
            XCTAssertTrue(error.message.contains("Reload"))
        }
    }

    func testUpdateReadsTheWriteResponse() async throws {
        MockURLProtocol.calls = []
        MockURLProtocol.handler = MockURLProtocol.recordWrite
        let entry = try await client().update(
            collection: contentPosts(),
            id: "post1",
            draft: DraftWrite(
                text: DraftText(title: "Launch", body: "Hello", excerpt: "", slug: "launch"),
                rev: "rev-old",
                skipRevision: true
            )
        )
        XCTAssertEqual(MockURLProtocol.calls.count, 1)
        XCTAssertEqual(MockURLProtocol.calls.first?.0, "PUT")
        XCTAssertTrue(MockURLProtocol.calls.first?.1.hasSuffix("/content/posts/post1") == true)
        XCTAssertEqual(entry.rev, "rev-from-write")
        XCTAssertEqual(entry.draftRevisionID, "draft9")
        XCTAssertEqual(entry.status, "published")
    }

    func testPublishEncodesRevWhenTheResponseOmitsIt() async throws {
        MockURLProtocol.handler = MockURLProtocol.publishAck
        let fields = [FieldDef(slug: "title", label: "Title", type: "string", required: true, sortOrder: 0)]
        let entry = try await client().publish(collection: posts(fields), id: "post1")
        let expected = Data("8:2026-09-29T12:00:00.000Z".utf8).base64EncodedString()
        XCTAssertEqual(entry.rev, expected)
        XCTAssertEqual(entry.status, "published")
        XCTAssertNil(entry.draftRevisionID)
    }

    private func client() -> EmDashClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return EmDashClient(
            site: URL(string: "https://example.com")!,
            token: "secret",
            session: URLSession(configuration: configuration)
        )
    }

    private func contentPosts() -> CollectionDef {
        posts([
            FieldDef(slug: "title", label: "Title", type: "string", required: true, sortOrder: 0),
            FieldDef(slug: "content", label: "Content", type: "portableText", required: false, sortOrder: 1),
        ])
    }

    private func posts(_ fields: [FieldDef]) -> CollectionDef {
        CollectionDef(slug: "posts", label: "Posts", labelSingular: "Post", fields: fields)
    }
}

extension ClientTests {
    fileprivate static func requestBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody, !body.isEmpty { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        return read(stream)
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        while let chunk = next(stream, buffer: buffer) {
            data.append(chunk)
        }
        return data
    }

    private static func next(_ stream: InputStream, buffer: UnsafeMutablePointer<UInt8>) -> Data? {
        let count = stream.read(buffer, maxLength: 4096)
        guard count > 0 else { return nil }
        return Data(bytes: buffer, count: count)
    }
}

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var calls: [(String, String)] = []

    static func draftAndLive(_ request: URLRequest) throws -> (Int, Data) {
        let path = request.url?.path ?? ""
        if path.hasSuffix("/compare") { return try json(compareDraft()) }
        return try json(liveItem())
    }

    static func conflict(_ request: URLRequest) throws -> (Int, Data) {
        let body = ["success": false, "error": ["code": "CONFLICT", "message": "stale"]] as [String: Any]
        return (409, try JSONSerialization.data(withJSONObject: body))
    }

    static func recordWrite(_ request: URLRequest) throws -> (Int, Data) {
        calls.append((request.httpMethod ?? "", request.url?.path ?? ""))
        let sent = try JSONSerialization.jsonObject(with: ClientTests.requestBody(request)) as? [String: Any]
        XCTAssertEqual(sent?["skipRevision"] as? Bool, true)
        return try json(writeItem())
    }

    static func publishAck(_ request: URLRequest) throws -> (Int, Data) {
        try json(publishItem())
    }

    private static func json(_ body: [String: Any]) throws -> (Int, Data) {
        (200, try JSONSerialization.data(withJSONObject: body))
    }

    private static func compareDraft() -> [String: Any] {
        [
            "success": true,
            "data": [
                "hasChanges": true,
                "draft": [
                    "title": "Draft title",
                    "content": [block("Draft body")],
                ],
            ],
        ]
    }

    private static func liveItem() -> [String: Any] {
        [
            "success": true,
            "data": [
                "item": item(
                    status: "published",
                    extra: ["draftRevisionId": "draft1", "updatedAt": "2026-09-28T12:00:00Z"],
                    text: "Live body"
                ),
                "_rev": "rev1",
            ],
        ]
    }

    private static func writeItem() -> [String: Any] {
        [
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
    }

    private static func publishItem() -> [String: Any] {
        [
            "success": true,
            "data": [
                "item": [
                    "id": "post1",
                    "slug": "launch",
                    "status": "published",
                    "updatedAt": "2026-09-29T12:00:00.000Z",
                    "version": 8,
                ]
            ],
        ]
    }

    private static func item(status: String, extra: [String: Any], text: String) -> [String: Any] {
        var body: [String: Any] = [
            "id": "post1",
            "slug": "launch",
            "status": status,
            "data": ["title": "Live title", "content": [block(text)]],
        ]
        for (key, value) in extra {
            body[key] = value
        }
        return body
    }

    private static func block(_ text: String) -> [String: Any] {
        [
            "_type": "block",
            "style": "normal",
            "children": [["_type": "span", "text": text]],
        ]
    }

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

extension ClientTests {
    @MainActor
    func testCollectionsWithoutRevisionsNeverAutosaveLivePosts() throws {
        let plain = try XCTUnwrap(
            EmDashClient.collection(from: .object(["slug": .string("notes"), "supports": .array([.string("drafts")])])))
        XCTAssertFalse(plain.keepsRevisions)
        let defaults = try XCTUnwrap(EmDashClient.collection(from: .object(["slug": .string("posts")])))
        XCTAssertTrue(defaults.keepsRevisions)

        let live = EditorDocument()
        live.status = "published"
        live.body = "edited"
        let state = PostState(live, keepsRevisions: false)
        XCTAssertTrue(state.writesLive)
        XCTAssertEqual(state.publishTitle, "Update Live Post")
        XCTAssertEqual(state.label, "Published, edits not live yet")
        XCTAssertFalse(PostState(live).writesLive)
    }
}

extension ClientTests {
    func testSlugs() {
        XCTAssertEqual(Slug.from("Hello, World! Café au lait"), "hello-world-cafe-au-lait")
        XCTAssertEqual(Slug.from("  --  "), "")
        XCTAssertEqual(Slug.cleaned("My  Post!"), "my-post-")
        XCTAssertEqual(Slug.cleaned("-lead"), "lead")
    }
}
