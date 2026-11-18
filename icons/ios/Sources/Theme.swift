import SwiftUI
import UIKit

// The palette is PARADOX HQ's (the Focus site's): black ground, off-black
// surfaces, white and greys, one hazard red. Every colour has a dark and a light
// value, so switching appearance can never leave white on white (tested).

extension Color {
    nonisolated init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// Design tokens: one struct resolved at the root and swapped to re-theme the
/// whole app. Views read colours only from `@Environment(\.theme)`.
struct Theme: Sendable {
    var ground: Color
    var surface: Color
    var surface2: Color
    var line: Color
    /// Headings, the selected ring, the main button.
    var head: Color
    var body: Color
    var muted: Color
    /// What is written on `head` (the button's words).
    var onHead: Color
    var hazard: Color

    static let standard = Theme(
        ground: dynamic(0x000000, 0xF2F2F2),
        surface: dynamic(0x1A1A1A, 0xFFFFFF),
        surface2: dynamic(0x232323, 0xE8E8E8),
        line: dynamic(0x2A2A2A, 0xDCDCDC),
        head: dynamic(0xFFFFFF, 0x262626),
        body: dynamic(0xEEEEEE, 0x333333),
        muted: dynamic(0x8E8E8E, 0x7A7A7A),
        onHead: dynamic(0x000000, 0xFFFFFF),
        hazard: dynamic(0xED4E3B, 0xD13A27)
    )

    /// PARADOX terminal palette: violet and teal on purple-black, either appearance.
    static let paradox = Theme(
        ground: Color(hex: 0x0E0B1A),
        surface: Color(hex: 0x171331),
        surface2: Color(hex: 0x2A2350),
        line: Color(hex: 0x2A2350),
        head: Color(hex: 0x87D7D7),
        body: Color(hex: 0xCFCAE6),
        muted: Color(hex: 0x8787AF),
        onHead: Color(hex: 0x0E0B1A),
        hazard: Color(hex: 0xFF87FF)
    )

    nonisolated static func dynamic(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .light ? light : dark)
        })
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

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.standard
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension View {
    func theme(_ theme: Theme) -> some View {
        environment(\.theme, theme).tint(theme.head)
    }
}
