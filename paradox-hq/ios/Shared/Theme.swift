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
    static let violet = dynamic(0xA78BFA, 0x7457DB)
    static let ok = dynamic(0x5FD7AF, 0x16916B)
    static let hazard = dynamic(0xED4E3B, 0xD13A27)
    static let amber = dynamic(0xFFD27A, 0xA86A00)
    /// The one solid button on a screen, and the words on it.
    static let button = dynamic(0xFFFFFF, 0x262626)
    static let buttonInk = dynamic(0x000000, 0xFFFFFF)

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
