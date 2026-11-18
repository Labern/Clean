import SwiftUI

@main
struct IconsApp: App {
    @State private var shelf = IconShelf()
    @State private var place = IconFolder()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(shelf)
                .environment(place)
                .theme(.standard)   // swap to `.paradox` to re-theme the whole app
                // An icon made in the designer goes on the first time a build carrying it opens.
                // iOS refuses an icon change until the app is active, so it waits for that.
                .onChange(of: phase, initial: true) { _, new in
                    if new == .active { shelf.adopt() }
                    if new == .background { shelf.mirror(into: place) }
                }
        }
    }
}

/// Launch arguments for screenshots: `-screen designer` opens straight on the artboard.
enum Launch {
    static var screen: String { UserDefaults.standard.string(forKey: "screen") ?? "" }
}
