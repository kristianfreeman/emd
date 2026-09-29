import AppKit

extension Notification.Name {
    /// Posted on the main thread with the image's URL as the object, once it has loaded or failed.
    static let inlineImageSettled = Notification.Name("InlineImages.settled")
}

/// Pictures for image lines in the editor. Each URL is fetched once; decoded images are evicted under pressure.
/// Main thread only.
final class InlineImages {
    nonisolated(unsafe) static let shared = InlineImages()

    private let images: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.totalCostLimit = 256 << 20
        return cache
    }()
    private var loading: Set<URL> = []
    private var failed: Set<URL> = []

    func image(_ url: URL) -> NSImage? {
        images.object(forKey: url as NSURL)
    }

    /// Pixel size, which is what the `=WxH` suffix records.
    func pixelSize(_ url: URL) -> NSSize? {
        guard let rep = image(url)?.representations.first, rep.pixelsWide > 0 else { return nil }
        return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }

    func request(_ url: URL) {
        guard image(url) == nil, !loading.contains(url), !failed.contains(url) else { return }
        loading.insert(url)
        Task { @MainActor in
            let image = await Self.fetch(url)
            self.loading.remove(url)
            if let image {
                let rep = image.representations.first
                self.images.setObject(
                    image, forKey: url as NSURL, cost: (rep?.pixelsWide ?? 1) * (rep?.pixelsHigh ?? 1) * 4)
            } else {
                self.failed.insert(url)
            }
            NotificationCenter.default.post(name: .inlineImageSettled, object: url)
        }
    }

    private static func fetch(_ url: URL) async -> NSImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: url) else { return nil }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }
        return NSImage(data: data)
    }
}
