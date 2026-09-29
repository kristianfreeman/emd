import AppKit
import XCTest

@testable import EmDashWriter

final class ImageTests: XCTestCase {
    func testSiteMediaLineCarriesLibraryIDAndSize() {
        let line = "![A dog](/_emdash/api/media/file/01HXKDOG.jpg =1200x800)"
        let block = PortableText.fromMarkdown(line + "\n").first?.object
        XCTAssertEqual(block?["asset"]?.object?["_ref"], .string("01HXKDOG"))
        XCTAssertEqual(block?["asset"]?.object?["url"], .string("/_emdash/api/media/file/01HXKDOG.jpg"))
        XCTAssertEqual(block?["width"], .number(1200))
        XCTAssertEqual(block?["height"], .number(800))
        XCTAssertEqual(PortableText.toMarkdown(block.map { [.object($0)] } ?? []), line + "\n")
    }

    func testAdminInsertedImageReadsAsALine() {
        let block: [String: JSONValue] = [
            "_type": .string("image"), "_key": .string("k"), "alt": .string("Cover"),
            "asset": .object(["_ref": .string("01HXK"), "url": .string("/_emdash/api/media/file/01HXK.png")]),
            "width": .number(640), "height": .number(480),
        ]
        let markdown = PortableText.toMarkdown([.object(block)])
        XCTAssertEqual(markdown, "![Cover](/_emdash/api/media/file/01HXK.png =640x480)\n")
    }

    func testUploadingLinesNeverReachTheSite() {
        let markdown = "Before\n\n![Uploading photo…](uploading:1234)\n\nAfter\n"
        let blocks = PortableText.fromMarkdown(markdown)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertFalse(blocks.contains { $0.object?["_type"] == .string("image") })
    }

    func testUploadedMediaBecomesALine() {
        let media = UploadedMedia(id: "01A", url: "/_emdash/api/media/file/01A.webp", width: 10, height: 20)
        XCTAssertEqual(PortableText.imageLine(media: media, alt: ""), "![](/_emdash/api/media/file/01A.webp =10x20)")
        let unsized = UploadedMedia(id: "01B", url: "/_emdash/api/media/file/01B.gif")
        XCTAssertEqual(PortableText.imageLine(media: unsized, alt: "x"), "![x](/_emdash/api/media/file/01B.gif)")
    }

    func testMultipartBodyAndResponse() throws {
        let file = PreparedImage(data: Data([1, 2, 3]), filename: "a\"b.png", mimeType: "image/png")
        let body = String(decoding: EmDashClient.multipart(file, boundary: "B"), as: UTF8.self)
        XCTAssertTrue(body.hasPrefix("--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a'b.png\"\r\n"))
        XCTAssertTrue(body.contains("Content-Type: image/png\r\n\r\n"))
        XCTAssertTrue(body.hasSuffix("\r\n--B--\r\n"))
        let json: JSONValue = .object([
            "item": .object([
                "id": .string("01C"), "url": .string("/_emdash/api/media/file/01C.png"),
                "width": .number(3), "height": .number(4),
            ])
        ])
        XCTAssertEqual(
            try EmDashClient.media(from: json),
            UploadedMedia(id: "01C", url: "/_emdash/api/media/file/01C.png", width: 3, height: 4))
    }

    func testPreparationPassesAcceptedTypesAndConvertsTheRest() throws {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 3,
            hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        let tiff = try XCTUnwrap(rep?.tiffRepresentation)
        let converted = try PreparedImage.prepare(.pixels(tiff, name: "Shot"))
        XCTAssertEqual(converted.mimeType, "image/jpeg")
        XCTAssertEqual(converted.filename, "Shot.jpg")

        let png = try XCTUnwrap(rep?.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appending(path: "emd-test-\(UUID().uuidString).png")
        try png.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let passed = try PreparedImage.prepare(.file(url))
        XCTAssertEqual(passed.mimeType, "image/png")
        XCTAssertEqual(passed.data, png)
    }
}
