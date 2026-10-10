import SwiftUI
import SwiftData

@main
struct __APP__App: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: Item.self)
    }
}
