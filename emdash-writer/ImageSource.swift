import AppKit
import UniformTypeIdentifiers

/// An image on its way into a post: a file from Finder or the open panel, or pixels from the pasteboard.
enum ImageSource {
    case file(URL)
    case pixels(Data, name: String)

    var name: String {
        switch self {
        case .file(let url): url.deletingPathExtension().lastPathComponent
        case .pixels(_, let name): name
        }
    }

    /// Image files first. Raw pixels only when there is no text, so copying a web page still pastes words.
    static func from(_ pasteboard: NSPasteboard) -> [ImageSource] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        if !files.isEmpty { return files.map(ImageSource.file) }
        guard pasteboard.string(forType: .string) == nil else { return [] }
        guard let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) else { return [] }
        return [.pixels(data, name: "Pasted image")]
    }
}

/// Bytes the site accepts: PNG, JPEG, GIF, or WebP. Anything else, like HEIC or TIFF, is converted.
struct PreparedImage {
    var data: Data
    var filename: String
    var mimeType: String

    private static let accepted: [(UTType, String)] = [
        (.png, "image/png"), (.jpeg, "image/jpeg"), (.gif, "image/gif"), (.webP, "image/webp"),
    ]

    static func prepare(_ source: ImageSource) throws -> PreparedImage {
        switch source {
        case .file(let url): try file(url, name: source.name)
        case .pixels(let data, let name): try converted(data, name: name)
        }
    }

    private static func file(_ url: URL, name: String) throws -> PreparedImage {
        let data = try Data(contentsOf: url)
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        guard let mime = accepted.first(where: { type.conforms(to: $0.0) })?.1 else {
            return try converted(data, name: name)
        }
        return PreparedImage(data: data, filename: url.lastPathComponent, mimeType: mime)
    }

    /// Photos become JPEG. Pixels with transparency, like screenshots of windows, stay PNG.
    private static func converted(_ data: Data, name: String) throws -> PreparedImage {
        guard let rep = NSBitmapImageRep(data: data) ?? NSImage(data: data).flatMap(bitmap) else {
            throw APIError(status: 0, code: "NOT_AN_IMAGE", message: "That file is not an image Emd can read.")
        }
        if rep.hasAlpha, let png = rep.representation(using: .png, properties: [:]) {
            return PreparedImage(data: png, filename: "\(name).png", mimeType: "image/png")
        }
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88]) else {
            throw APIError(status: 0, code: "NOT_AN_IMAGE", message: "Emd could not convert that image.")
        }
        return PreparedImage(data: jpeg, filename: "\(name).jpg", mimeType: "image/jpeg")
    }

    private static func bitmap(_ image: NSImage) -> NSBitmapImageRep? {
        guard let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }
}
