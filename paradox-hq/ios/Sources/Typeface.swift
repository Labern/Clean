import SwiftUI
import UIKit
import CoreText

/// The typeface the app is set in. Chosen in Company › Settings.
enum Typeface: String, CaseIterable, Identifiable {
    case system, graphik

    var id: String { rawValue }
    var title: String { self == .system ? "SF Pro" : "Graphik" }
}

/// Every font in the app comes from here, so one setting changes them all.
///
/// Graphik is a licensed typeface and this repo is public, so its files are
/// never committed: they sit on the Mac in `Resources/Private` and a build made
/// there carries them. A build without them is simply set in SF Pro.
enum Face {
    static let family = "Graphik"
    private(set) static var hasGraphik = false

    /// Registers every font file the build carries. Called once, as the app starts.
    static func load() {
        for kind in ["otf", "ttf"] {
            for file in Bundle.main.urls(forResourcesWithExtension: kind, subdirectory: nil) ?? [] {
                CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
            }
        }
        hasGraphik = !UIFont.fontNames(forFamilyName: family).isEmpty
    }

    /// True when the app is to be set in Graphik and this build has it.
    static var on: Bool {
        hasGraphik && UserDefaults.standard.string(forKey: "typeface") == Typeface.graphik.rawValue
    }

    /// A fixed size, in the app's typeface.
    static func at(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        on ? Font(cut(size, weight) as CTFont) : .system(size: size, weight: weight)
    }

    /// One of the system's text styles, in the app's typeface.
    static func style(_ style: Font.TextStyle, _ weight: Font.Weight? = nil) -> Font {
        guard on else {
            let font = Font.system(style)
            return weight.map { font.weight($0) } ?? font
        }
        let size = UIFont.preferredFont(forTextStyle: text(style)).pointSize
        return Font(cut(size, weight ?? (style == .headline ? .semibold : .regular)) as CTFont)
    }

    /// Graphik whatever the setting says (the word beside the mark is always in it).
    static func graphik(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        hasGraphik ? Font(cut(size, weight) as CTFont) : .system(size: size, weight: weight)
    }

    /// How far below its baseline that word's line box reaches, to sit it on a baseline exactly.
    static func graphikDescent(_ size: CGFloat) -> CGFloat {
        let font = hasGraphik ? cut(size, .regular) : UIFont.systemFont(ofSize: size)
        return abs(font.descender)
    }

    private static func cut(_ size: CGFloat, _ weight: Font.Weight) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [UIFontDescriptor.TraitKey.weight: heavy(weight).rawValue],
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func heavy(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }

    private static func text(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}
