import SwiftUI

extension Color {
    static let bgDeep = Color(red: 0.059, green: 0.047, blue: 0.161)   // #0f0c29
    static let bgMid  = Color(red: 0.188, green: 0.169, blue: 0.388)   // #302b63
    static let accentTeal   = Color(red: 0.369, green: 0.918, blue: 0.831) // #5eead4
    static let accentViolet = Color(red: 0.655, green: 0.545, blue: 0.980) // #a78bfa
    static let accentPink   = Color(red: 0.957, green: 0.447, blue: 0.714) // #f472b6
}

@main
struct StrataApp: App {
    var body: some Scene {
        WindowGroup("Strata") {
            HeatmapView()
                .frame(minWidth: 860, minHeight: 580)
                .onAppear { resizeWindowTo90Percent() }
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
    }
}

/// Resize the main window to 90% of the primary screen on first launch.
private func resizeWindowTo90Percent() {
    guard let screen = NSScreen.main else { return }
    let visible = screen.visibleFrame          // excludes menu bar + Dock
    let w = visible.width  * 0.90
    let h = visible.height * 0.90
    let x = visible.minX + (visible.width  - w) / 2
    let y = visible.minY + (visible.height - h) / 2
    DispatchQueue.main.async {
        NSApp.windows.first?.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true, animate: false)
    }
}
