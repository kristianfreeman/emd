import AppKit
import SwiftUI

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum WriterFont: String, CaseIterable, Identifiable {
    case geistSans
    case geistMono
    case system
    case newYork
    case sfMono
    case charter
    case georgia

    var id: String { rawValue }

    var label: String {
        switch self {
        case .geistSans: "Geist Sans"
        case .geistMono: "Geist Mono"
        case .system: "System"
        case .newYork: "New York"
        case .sfMono: "SF Mono"
        case .charter: "Charter"
        case .georgia: "Georgia"
        }
    }

    func nsFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let named: String?
        switch self {
        case .geistSans:
            named = weight.rawValue >= NSFont.Weight.medium.rawValue ? "Geist-Medium" : "Geist-Regular"
        case .geistMono:
            named = weight.rawValue >= NSFont.Weight.medium.rawValue ? "GeistMono-Medium" : "GeistMono-Regular"
        case .system:
            return .systemFont(ofSize: size, weight: weight)
        case .newYork:
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            if let descriptor = base.fontDescriptor.withDesign(.serif) {
                return NSFont(descriptor: descriptor, size: size) ?? base
            }
            return base
        case .sfMono:
            return .monospacedSystemFont(ofSize: size, weight: weight)
        case .charter:
            named = "Charter"
        case .georgia:
            named = "Georgia"
        }
        if let named, let font = NSFont(name: named, size: size) {
            return font
        }
        return .systemFont(ofSize: size, weight: weight)
    }

    func font(size: CGFloat) -> Font {
        Font(nsFont(size: size))
    }
}

struct Palette {
    var paper: Color
    var sidebar: Color
    var ink: Color
    var muted: Color
    var hairline: Color
    var accent: Color
    var alert: Color

    var nsPaper: NSColor { NSColor(paper) }
    var nsInk: NSColor { NSColor(ink) }
    var nsMuted: NSColor { NSColor(muted) }
    var nsAccent: NSColor { NSColor(accent) }

    static func resolve(_ scheme: ColorScheme) -> Palette {
        switch scheme {
        case .dark:
            Palette(
                paper: Color(red: 0.106, green: 0.106, blue: 0.102),
                sidebar: Color(red: 0.078, green: 0.078, blue: 0.075),
                ink: Color(red: 0.925, green: 0.918, blue: 0.894),
                muted: Color(red: 0.557, green: 0.545, blue: 0.518),
                hairline: Color(red: 0.173, green: 0.173, blue: 0.165),
                accent: Color(red: 0.557, green: 0.706, blue: 0.847),
                alert: Color(red: 0.910, green: 0.478, blue: 0.420)
            )
        default:
            Palette(
                paper: Color(red: 0.969, green: 0.965, blue: 0.953),
                sidebar: Color(red: 0.937, green: 0.933, blue: 0.914),
                ink: Color(red: 0.110, green: 0.110, blue: 0.102),
                muted: Color(red: 0.553, green: 0.541, blue: 0.510),
                hairline: Color(red: 0.886, green: 0.878, blue: 0.847),
                accent: Color(red: 0.184, green: 0.365, blue: 0.549),
                alert: Color(red: 0.620, green: 0.180, blue: 0.145)
            )
        }
    }
}

enum FontBook {
    static func register() {
        for name in ["Geist-Variable", "GeistMono-Variable"] {
            let url = Bundle.main.url(forResource: name, withExtension: "ttf")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Resources/Fonts")
            guard let url else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
