import Foundation
import SwiftData

/// Example content for the first launch, so every spine opens in a working state.
enum Seed {
    @MainActor static func run(_ context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Todo>())) ?? 0
        guard existing == 0 else { return }

        let cal = Calendar.current
        let now = Date()
        func days(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: now) ?? now }
        func minutes(_ n: Int) -> Date { cal.date(byAdding: .minute, value: n, to: now) ?? now }

        let todos: [Todo] = [
            Todo(spine: .tesla, title: "Book the MOT", tag: "Book", done: true, created: days(-6)),
            Todo(spine: .tesla, title: "Fix the rear wiper arm", tag: "Fix", created: days(-18)),
            Todo(spine: .tesla, title: "Wash, vacuum the front mats", tag: "Wash", created: days(-3)),
            Todo(spine: .tesla, title: "Get tyre pressure caps", tag: "Get", created: days(-1)),
            Todo(spine: .ring, title: "Angle the garden cam down", tag: "Fix", created: days(-5)),
            Todo(spine: .ring, title: "Order a spare battery", tag: "Get", created: days(-2)),
            Todo(spine: .spotify, title: "Playlist for the drive to Bath", created: days(-4)),
            Todo(spine: .diary, title: "Call the agent about Tuesday", created: days(-1)),
        ]
        for t in todos { context.insert(t) }

        let deadlines: [Deadline] = [
            Deadline(title: "MOT", symbol: "checkmark.seal", date: days(23), everyMonths: 12),
            Deadline(title: "Tyres", symbol: "circle.circle", date: days(9), everyMonths: 6),
            Deadline(title: "Service", symbol: "wrench.and.screwdriver", date: days(68), everyMonths: 24),
            Deadline(title: "Insurance", symbol: "shield", date: days(112), everyMonths: 12),
        ]
        for d in deadlines { context.insert(d) }

        for k in 0..<16 {
            let supercharger = k % 4 == 1
            let kWh = Double([38, 22, 41, 30, 47, 26, 35, 52][k % 8])
            context.insert(Charge(date: days(-k * 4), kWh: kWh,
                                  pencePerKWh: supercharger ? 52 : 7.5,
                                  place: supercharger ? "Supercharger" : "Home"))
        }

        let cameras: [Camera] = [
            Camera(name: "Front door", battery: 0.82, batteryChanged: days(-40), lastMotion: minutes(-130), order: 0),
            Camera(name: "Drive", battery: 0.61, batteryChanged: days(-62), lastMotion: minutes(-48), order: 1),
            Camera(name: "Garden", battery: 0.44, batteryChanged: days(-95), lastMotion: minutes(-600), order: 2),
            Camera(name: "Side gate", battery: 0.18, batteryChanged: days(-150), lastMotion: minutes(-1500), order: 3),
        ]
        for c in cameras { context.insert(c) }

        let pins: [Pin] = [
            Pin(title: "Driving ★★★★★", subtitle: "The car playlist", uri: "spotify:search:driving", symbol: "car.fill", hue: 0.01, isMood: true, order: 0),
            Pin(title: "Focus", subtitle: "Writing, no lyrics", uri: "spotify:search:deep%20focus", symbol: "pencil.line", hue: 0.62, isMood: true, order: 1),
            Pin(title: "Gym", subtitle: "Fast and loud", uri: "spotify:search:workout", symbol: "figure.strengthtraining.traditional", hue: 0.36, isMood: true, order: 2),
            Pin(title: "Wind down", subtitle: "After 22:00", uri: "spotify:search:night%20jazz", symbol: "moon.stars.fill", hue: 0.74, isMood: true, order: 3),
            Pin(title: "Kind of Blue", subtitle: "Miles Davis", uri: "spotify:search:kind%20of%20blue", symbol: "music.note", hue: 0.6, isMood: false, order: 4),
            Pin(title: "In Rainbows", subtitle: "Radiohead", uri: "spotify:search:in%20rainbows", symbol: "music.note", hue: 0.08, isMood: false, order: 5),
            Pin(title: "Discover Weekly", subtitle: "Playlist", uri: "spotify:search:discover%20weekly", symbol: "sparkles", hue: 0.85, isMood: false, order: 6),
        ]
        for p in pins { context.insert(p) }

        let entries: [Entry] = [
            Entry(day: cal.startOfDay(for: days(-1)), text: "Long day on set. Good notes from the read-through.", stars: 4),
            Entry(day: cal.startOfDay(for: days(-2)), text: "Drove to the coast and back. Kind of Blue the whole way.", stars: 5),
            Entry(day: cal.startOfDay(for: days(-3)), text: "Quiet. Wrote two scenes.", stars: 3),
        ]
        for e in entries { context.insert(e) }

        try? context.save()
    }
}
