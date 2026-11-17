import SwiftUI

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

enum Ink {
    static let ground = Color.black
    static let surface = Color(hex: 0x1A1A1A)
    static let surface2 = Color(hex: 0x232323)
    static let line = Color(hex: 0x2A2A2A)
    static let body = Color(hex: 0xEEEEEE)
    static let muted = Color(hex: 0x8E8E8E)
    static let idle = Color(hex: 0x4A4A4A)
    static let violet = Color(hex: 0xA78BFA)
    static let ok = Color(hex: 0x5FD7AF)
    static let hazard = Color(hex: 0xED4E3B)
    static let amber = Color(hex: 0xFFD27A)
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
