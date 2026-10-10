import SwiftUI
import SwiftData

@main
struct ParadoxApp: App {
    var body: some Scene {
        WindowGroup {
            ShelfView()
        }
        .modelContainer(for: [Todo.self, Deadline.self, Charge.self, Camera.self, Pin.self, Entry.self])
    }
}
