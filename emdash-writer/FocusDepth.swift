import AppKit
import CoreImage

/// How far focus mode pushes back the lines around the caret. Each stop goes further than the last.
enum FocusDepth: Int, CaseIterable, Identifiable {
    case muted
    case dim
    case faint
    case blurred
    case hazy

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .muted: "Muted"
        case .dim: "Dim"
        case .faint: "Faint"
        case .blurred: "Blurred"
        case .hazy: "Blurred and dim"
        }
    }

    /// Share of the muted ink that gives way to the paper.
    var fade: CGFloat {
        switch self {
        case .muted, .blurred: 0
        case .dim: 0.35
        case .faint: 0.62
        case .hazy: 0.45
        }
    }

    /// Blur radius as a share of the font size.
    var blur: CGFloat {
        switch self {
        case .blurred: 0.14
        case .hazy: 0.18
        default: 0
        }
    }

    func ink(muted: NSColor, paper: NSColor) -> NSColor {
        guard fade > 0 else { return muted }
        return muted.blended(withFraction: fade, of: paper) ?? muted
    }

    func blurRadius(fontSize: CGFloat) -> CGFloat {
        blur * fontSize
    }
}

extension NSAttributedString.Key {
    /// A `CGFloat` blur radius in points. `FocusLayoutManager` draws these glyphs out of focus.
    static let focusBlur = NSAttributedString.Key("emdash.focusBlur")
}

/// Draws runs that carry `.focusBlur` through a Gaussian blur. Everything else draws as usual.
final class FocusLayoutManager: NSLayoutManager {
    /// About 60 blurred lines at 2x. Past that, lines re-render as they scroll back in.
    private let blurred: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 64 << 20
        return cache
    }()

    // swiftlint:disable:next function_parameter_count
    override func showCGGlyphs(
        _ glyphs: UnsafePointer<CGGlyph>,
        positions: UnsafePointer<CGPoint>,
        count: Int,
        font: NSFont,
        textMatrix: CGAffineTransform,
        attributes: [NSAttributedString.Key: Any] = [:],
        in context: CGContext
    ) {
        let run = GlyphRun(glyphs: glyphs, positions: positions, count: count, font: font, textMatrix: textMatrix)
        guard let radius = attributes[.focusBlur] as? CGFloat, radius > 0, count > 0 else {
            showPlain(run, attributes: attributes, in: context)
            return
        }
        drawBlurred(run, radius: radius, attributes: attributes, in: context)
    }

    private func showPlain(_ run: GlyphRun, attributes: [NSAttributedString.Key: Any], in context: CGContext) {
        super.showCGGlyphs(
            run.glyphs,
            positions: run.positions,
            count: run.count,
            font: run.font,
            textMatrix: run.textMatrix,
            attributes: attributes,
            in: context
        )
    }

    private func drawBlurred(
        _ run: GlyphRun,
        radius: CGFloat,
        attributes: [NSAttributedString.Key: Any],
        in context: CGContext
    ) {
        let scale = max(1, abs(context.userSpaceToDeviceSpaceTransform.d))
        let frame = run.bounds(padding: radius * 3)
        let key = run.cacheKey(radius: radius, scale: scale, attributes: attributes) as NSString
        let image = blurred.object(forKey: key) ?? render(run, frame: frame, blur: (radius, scale), attributes)
        guard let image else { return }
        blurred.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        place(image, in: frame, context: context)
    }

    private func render(
        _ run: GlyphRun,
        frame: CGRect,
        blur: (radius: CGFloat, scale: CGFloat),
        _ attributes: [NSAttributedString.Key: Any]
    ) -> CGImage? {
        guard let sharp = run.bitmap(frame: frame, scale: blur.scale, attributes: attributes) else { return nil }
        return Self.gaussian(sharp, radius: blur.radius * blur.scale)
    }

    /// The bitmap is upright in CG terms, so it flips once to land in the flipped text view.
    private func place(_ image: CGImage, in frame: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: frame.minX, y: frame.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: frame.size))
        context.restoreGState()
    }

    private static let imaging = CIContext(options: [.cacheIntermediates: false])

    private static func gaussian(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: radius / 2).cropped(to: input.extent)
        return imaging.createCGImage(output, from: input.extent)
    }
}

private struct GlyphRun {
    var glyphs: UnsafePointer<CGGlyph>
    var positions: UnsafePointer<CGPoint>
    var count: Int
    var font: NSFont
    var textMatrix: CGAffineTransform

    /// Positions are baselines in the flipped view, so ascent sits above and descent below.
    /// Core Text reads positions in text space, which is why `bitmap` maps them back through the text matrix.
    func bounds(padding: CGFloat) -> CGRect {
        let xs = (0..<count).map { positions[$0].x }
        let baseline = positions[0].y
        let minX = (xs.min() ?? 0) - padding
        let maxX = (xs.max() ?? 0) + font.pointSize * 1.2 + padding
        let top = baseline - font.ascender - padding
        let bottom = baseline - font.descender + padding
        return CGRect(x: minX, y: top, width: maxX - minX, height: bottom - top)
    }

    func bitmap(
        frame: CGRect,
        scale: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGImage? {
        guard let context = Self.canvas(frame.size, scale: scale) else { return nil }
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -frame.minX, y: -frame.maxY)
        context.setFillColor(ink(attributes))
        context.textMatrix = textMatrix
        let toText = textMatrix.inverted()
        let placed = (0..<count).map { positions[$0].applying(toText) }
        CTFontDrawGlyphs(font, glyphs, placed, count, context)
        return context.makeImage()
    }

    private static func canvas(_ size: CGSize, scale: CGFloat) -> CGContext? {
        CGContext(
            data: nil,
            width: Int(ceil(size.width * scale)),
            height: Int(ceil(size.height * scale)),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private func ink(_ attributes: [NSAttributedString.Key: Any]) -> CGColor {
        let color = attributes[.foregroundColor] as? NSColor ?? .textColor
        return (color.usingColorSpace(.sRGB) ?? color).cgColor
    }

    func cacheKey(radius: CGFloat, scale: CGFloat, attributes: [NSAttributedString.Key: Any]) -> String {
        let origin = positions[0]
        var parts = (0..<count).map { "\(glyphs[$0])@\(positions[$0].x - origin.x)" }
        parts.append("\(font.fontName)|\(font.pointSize)|\(radius)|\(scale)")
        parts.append("\(ink(attributes))")
        return parts.joined(separator: ",")
    }
}
