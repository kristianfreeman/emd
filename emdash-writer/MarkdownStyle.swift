import AppKit

enum MarkdownFonts {
    static func sized(_ font: NSFont, _ size: CGFloat) -> NSFont {
        NSFont(descriptor: font.fontDescriptor, size: size) ?? .systemFont(ofSize: size)
    }

    static func bold(_ font: NSFont) -> NSFont {
        faced(font, trait: .bold, weight: .bold) ?? .systemFont(ofSize: font.pointSize, weight: .bold)
    }

    static func italic(_ font: NSFont) -> NSFont {
        faced(font, trait: .italic, weight: nil)
            ?? NSFontManager.shared.convert(.systemFont(ofSize: font.pointSize), toHaveTrait: .italicFontMask)
    }

    static func mono(_ size: CGFloat) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static func faced(_ font: NSFont, trait: NSFontDescriptor.SymbolicTraits, weight: NSFont.Weight?)
        -> NSFont?
    {
        if let weighted = weighted(font, trait: trait, weight: weight) { return weighted }
        return converted(font, trait: trait)
    }

    private static func weighted(_ font: NSFont, trait: NSFontDescriptor.SymbolicTraits, weight: NSFont.Weight?)
        -> NSFont?
    {
        guard let weight else { return nil }
        let described = font.fontDescriptor.addingAttributes([
            .traits: [
                NSFontDescriptor.TraitKey.symbolic: trait.rawValue,
                NSFontDescriptor.TraitKey.weight: weight.rawValue,
            ]
        ])
        guard let next = NSFont(descriptor: described, size: font.pointSize), heavier(next, than: font) else {
            return nil
        }
        return next
    }

    private static func heavier(_ next: NSFont, than font: NSFont) -> Bool {
        NSFontManager.shared.weight(of: next) > NSFontManager.shared.weight(of: font) + 1
    }

    private static func converted(_ font: NSFont, trait: NSFontDescriptor.SymbolicTraits) -> NSFont? {
        let mask: NSFontTraitMask = trait == .bold ? .boldFontMask : .italicFontMask
        let converted = NSFontManager.shared.convert(font, toHaveTrait: mask)
        if changed(converted, from: font) { return converted }
        return symbolic(font, trait: trait)
    }

    private static func changed(_ converted: NSFont, from font: NSFont) -> Bool {
        converted.fontName != font.fontName
            || NSFontManager.shared.traits(of: converted) != NSFontManager.shared.traits(of: font)
    }

    private static func symbolic(_ font: NSFont, trait: NSFontDescriptor.SymbolicTraits) -> NSFont? {
        let described = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait))
        guard let next = NSFont(descriptor: described, size: font.pointSize), next.fontName != font.fontName else {
            return nil
        }
        return next
    }
}

struct MarkdownRun: Equatable {
    enum Kind: Equatable {
        case bold
        case italic
        case code
        case link
    }

    var kind: Kind
    var inner: NSRange
    var markers: [NSRange]
}

enum MarkdownRuns {
    private static let pattern =
        #"\*\*(.+?)\*\*|__(.+?)__|(?<!\*)\*(?!\*)(.+?)\*(?!\*)|(?<!_)_(?!_)(.+?)_(?!_)|`([^`]+)`|\[([^\]]+)\]\(([^)\s]+)\)"#
    private static let expression = try? NSRegularExpression(pattern: pattern)

    static func inline(in line: String) -> [MarkdownRun] {
        guard let expression else { return [] }
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        return expression.matches(in: line, range: full).compactMap(classified)
    }

    private static func classified(_ match: NSTextCheckingResult) -> MarkdownRun? {
        if let run = emphasis(match) { return run }
        return codeOrLink(match)
    }

    private static func emphasis(_ match: NSTextCheckingResult) -> MarkdownRun? {
        if let run = captured(match, group: 1, kind: .bold) { return run }
        if let run = captured(match, group: 2, kind: .bold) { return run }
        if let run = captured(match, group: 3, kind: .italic) { return run }
        return captured(match, group: 4, kind: .italic)
    }

    private static func codeOrLink(_ match: NSTextCheckingResult) -> MarkdownRun? {
        if let run = captured(match, group: 5, kind: .code) { return run }
        return captured(match, group: 6, kind: .link)
    }

    private static func captured(_ match: NSTextCheckingResult, group: Int, kind: MarkdownRun.Kind) -> MarkdownRun? {
        guard match.range(at: group).location != NSNotFound else { return nil }
        return run(kind, match: match, inner: group)
    }

    private static func run(_ kind: MarkdownRun.Kind, match: NSTextCheckingResult, inner: Int) -> MarkdownRun {
        let innerRange = match.range(at: inner)
        let lead = NSRange(location: match.range.location, length: max(0, innerRange.location - match.range.location))
        let tailStart = innerRange.location + innerRange.length
        let tail = NSRange(location: tailStart, length: max(0, match.range.location + match.range.length - tailStart))
        return MarkdownRun(kind: kind, inner: innerRange, markers: [lead, tail].filter { $0.length > 0 })
    }
}
