import SwiftUI
import UIKit

// The palette is the Focus site's: black ground, off-black surfaces, white and
// greys, one hazard red. Violet and green are the two colours of the Focus icon.

extension Color {
    nonisolated init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// Every colour in the app, each with a dark and a light value. Views use only
/// these, never `.white` or `.black`, so switching appearance can never leave
/// white text on a white surface (tested in `InkTests`).
enum Ink {
    static let ground = dynamic(0x000000, 0xF2F2F2)
    static let surface = dynamic(0x1A1A1A, 0xFFFFFF)
    static let surface2 = dynamic(0x232323, 0xE8E8E8)
    static let line = dynamic(0x2A2A2A, 0xDCDCDC)
    /// Headings, big figures, the mark.
    static let head = dynamic(0xFFFFFF, 0x262626)
    static let body = dynamic(0xEEEEEE, 0x333333)
    static let muted = dynamic(0x8E8E8E, 0x7A7A7A)
    static let idle = dynamic(0x4A4A4A, 0xB8B8B8)
    /// The accent: violet, unless another is chosen in Settings (`Palette`).
    static var violet: Color {
        Palette.accent.map { dynamic($0, Palette.deep($0)) } ?? dynamic(0xA78BFA, 0x7457DB)
    }
    /// The second colour, for what is done and what is live: green, unless another is chosen.
    static var ok: Color {
        Palette.second.map { dynamic($0, Palette.deep($0)) } ?? dynamic(0x5FD7AF, 0x16916B)
    }
    static let hazard = dynamic(0xED4E3B, 0xD13A27)
    static let amber = dynamic(0xFFD27A, 0xA86A00)
    /// The one solid button on a screen, and the words on it. White (dark in
    /// the light appearance) unless Settings says buttons take the accent.
    static var button: Color {
        Palette.buttonColour.map { dynamic($0, Palette.deep($0)) } ?? dynamic(0xFFFFFF, 0x262626)
    }
    static var buttonInk: Color {
        Palette.buttonColour.map { dynamic(Palette.ink(on: $0), Palette.ink(on: Palette.deep($0))) } ?? dynamic(0x000000, 0xFFFFFF)
    }
    /// What is drawn on a filled tick: always the opposite of the heading ink.
    static let onHead = dynamic(0x000000, 0xFFFFFF)

    nonisolated static func dynamic(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .light ? light : dark)
        })
    }

    /// A project's colour. White means "no colour", which is the heading ink,
    /// so it stays visible in light mode.
    static func tint(_ hex: Int) -> Color {
        hex == 0xFFFFFF ? head : Color(hex: UInt32(hex))
    }
}

/// The colours that can be changed in Settings. The choices are Focus's own:
/// its nine hues and its two-tone presets, name for name. Nothing chosen means
/// the app looks exactly as it always has.
nonisolated enum Palette {
    static let accentKey = "colour-accent"
    static let secondKey = "colour-second"
    static let buttonsKey = "colour-buttons"

    /// Focus's icon hues.
    static let hues: [UInt32] = [0xFF5F5F, 0xFFAF5F, 0xFFD75F, 0x5FD787, 0x5FD7AF, 0x5FAFFF, 0xA78BFA, 0xFF87FF, 0xD0D0D0]

    /// Focus's presets: a name and its two colours. The first is this app's default.
    static let presets: [(name: String, accent: UInt32, second: UInt32)] = [
        ("Purple & Green", 0xA78BFA, 0x5FD7AF), ("Pink & Teal", 0xFF87FF, 0x87D7D7),
        ("Violet & Gold", 0xAF87FF, 0xFFD75F), ("Teal & Pink", 0x87D7D7, 0xFF87FF),
        ("All Purple", 0xA78BFA, 0xA78BFA),
        ("UNIT 01", 0x7851A9, 0x8FD14F), ("Asuka", 0xE3262F, 0xF28C28), ("Rei", 0x5B8DEF, 0xE8343C),
        ("Shinji", 0x3E6FD6, 0xF1F3F6), ("Misato", 0x8A6CC0, 0xD7263D), ("Kaworu", 0xD8D8DE, 0xD3203B),
        ("Pen Pen", 0x6F86B8, 0xF6C445),
    ]

    static var accent: UInt32? { chosen(accentKey) }
    static var second: UInt32? { chosen(secondKey) }
    /// True when the solid buttons take the accent instead of white.
    static var colouredButtons: Bool { UserDefaults.standard.bool(forKey: buttonsKey) }
    static var buttonColour: UInt32? { colouredButtons ? (accent ?? 0xA78BFA) : nil }

    private static func chosen(_ key: String) -> UInt32? {
        (UserDefaults.standard.object(forKey: key) as? Int).flatMap { UInt32(exactly: $0) }
    }

    static func set(accent: UInt32?, second: UInt32?) {
        store(accent == 0xA78BFA ? nil : accent, accentKey)
        store(second == 0x5FD7AF ? nil : second, secondKey)
    }

    private static func store(_ value: UInt32?, _ key: String) {
        if let value { UserDefaults.standard.set(Int(value), forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
    }

    /// The same colour for the light appearance: deepened until it reads on white.
    static func deep(_ hex: UInt32) -> UInt32 {
        var (r, g, b) = (Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF))
        var tries = 0
        while luminance(r, g, b) > 0.22, tries < 12 {
            (r, g, b) = (r * 0.88, g * 0.88, b * 0.88)
            tries += 1
        }
        return (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
    }

    /// Black or white, whichever reads better on `hex`. (0.179 is where the two
    /// are equally good, so the answer always clears 4.5 to 1.)
    static func ink(on hex: UInt32) -> UInt32 {
        luminance(Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF)) > 0.179 ? 0x000000 : 0xFFFFFF
    }

    /// Relative luminance (WCAG) of an sRGB colour given as 0…255 channels.
    static func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func channel(_ value: Double) -> Double {
            let c = value / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }
}

extension UIColor {
    nonisolated convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// Light, dark, or whatever the phone is set to.
enum Appearance: String, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var scheme: ColorScheme? {
        switch self {
        case .auto: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

nonisolated enum Money {
    /// Amounts are held in minor units (pence), the way Stripe sends them.
    static func string(_ minor: Int, currency: String = "gbp", pennies: Bool = false,
                       locale: Locale = .current) -> String {
        let value = Decimal(minor) / 100
        return value.formatted(
            .currency(code: currency.uppercased())
            .precision(.fractionLength(pennies ? 2 : 0))
            .locale(locale))
    }
}

nonisolated enum Days {
    static func count(to date: Date, from now: Date = .now, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    static func short(_ n: Int) -> String {
        switch n {
        case ..<0: "\(-n)d late"
        case 0: "Today"
        default: "\(n)d"
        }
    }
}

/// Launch arguments, used by the cloud build to open a given screen unlocked:
/// `-unlocked YES -screen money`.
nonisolated enum Launch {
    static var unlocked: Bool { UserDefaults.standard.bool(forKey: "unlocked") }
    static var screen: String { UserDefaults.standard.string(forKey: "screen") ?? "" }
}
