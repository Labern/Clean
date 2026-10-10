import SwiftUI
import UIKit

// Colours are traditional Japanese pigments (日本の伝統色), one per spine,
// chosen to sit beside the ★★★★★ × パラドックス mark. Text tints are lifted
// in dark mode and deepened in light mode so titles keep their contrast.

extension UIColor {
    nonisolated convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { @Sendable trait in trait.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

enum Ink {
    /// Ground with a violet bias, after the PARADOX lavender.
    static let ground = Color.adaptive(light: 0xFAF9FC, dark: 0x0B0A10)
    static let surface = Color.adaptive(light: 0xEFEDF4, dark: 0x17151F)
    static let surface2 = Color.adaptive(light: 0xE2DFEA, dark: 0x262232)
    static let hairline = Color(uiColor: UIColor { @Sendable trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.10) : UIColor(white: 0, alpha: 0.10)
    })
    /// 菫 sumire in light, 藤紫 fujimurasaki in dark.
    static let fuji = Color.adaptive(light: 0x7058A3, dark: 0xA59ACA)
    static let night = Color(hex: 0x0B0A10)
}

enum Mark {
    /// Hiragino Mincho ships with iOS; it carries the lockup's stars and kana.
    static func mincho(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "HiraMinProN-W6" : "HiraMinProN-W3", size: size)
    }
}

enum Spine: Int, CaseIterable, Identifiable {
    case home, tesla, ring, spotify, diary

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .tesla: "Tesla"
        case .ring: "Ring"
        case .spotify: "Spotify"
        case .diary: "Diary"
        }
    }

    var katakana: String {
        switch self {
        case .home: "パラドックス"
        case .tesla: "テスラ"
        case .ring: "リング"
        case .spotify: "スポティファイ"
        case .diary: "ダイアリー"
        }
    }

    /// The pigment's name, set small at the head of each spine.
    var pigment: String {
        switch self {
        case .home: "藤紫"
        case .tesla: "紅緋"
        case .ring: "群青"
        case .spotify: "常磐"
        case .diary: "山吹"
        }
    }

    var fill: Color {
        switch self {
        case .home: Ink.ground
        case .tesla: Color(hex: 0xE83929)   // 紅緋 benihi
        case .ring: Color(hex: 0x4C6CB3)    // 群青 gunjō
        case .spotify: Color(hex: 0x007B43) // 常磐 tokiwa
        case .diary: Color(hex: 0xF8B500)   // 山吹 yamabuki
        }
    }

    var onFill: Color {
        switch self {
        case .home: Color.primary
        case .tesla, .diary: Ink.night
        case .ring, .spotify: Color.white
        }
    }

    var tint: Color {
        switch self {
        case .home: Ink.fuji
        case .tesla: Color.adaptive(light: 0xD8301F, dark: 0xEF5A48)
        case .ring: Color.adaptive(light: 0x4C6CB3, dark: 0x8FA6DD)
        case .spotify: Color.adaptive(light: 0x007B43, dark: 0x68BE8D) // 若竹 in dark
        case .diary: Color.adaptive(light: 0xA86A00, dark: 0xF8B500)
        }
    }
}

enum Days {
    static func count(to date: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: date)).day ?? 0
    }

    static func short(_ n: Int) -> String {
        switch n {
        case ..<0: "\(-n)d late"
        case 0: "Today"
        default: "\(n)d"
        }
    }

    static func phrase(_ title: String, _ date: Date) -> String {
        let n = count(to: date)
        switch n {
        case ..<0: return "\(title) overdue"
        case 0: return "\(title) today"
        case 1: return "\(title) tomorrow"
        default: return "\(title) in \(n) days"
        }
    }
}

enum Ago {
    /// "now", "48m", "2h", "3d": short enough for a narrow tile.
    static func short(_ date: Date, from now: Date = .now) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        switch s {
        case ..<60: return "now"
        case ..<3600: return "\(s / 60)m"
        case ..<86_400: return "\(s / 3600)h"
        default: return "\(s / 86_400)d"
        }
    }
}

enum Launcher {
    /// Opens an app by URL scheme, falling back to the web if the app isn't installed.
    static func open(_ primary: String, fallback: String?, with openURL: OpenURLAction) {
        guard let url = URL(string: primary) else { return }
        openURL(url) { accepted in
            if !accepted, let fallback, let web = URL(string: fallback) {
                openURL(web)
            }
        }
    }
}
