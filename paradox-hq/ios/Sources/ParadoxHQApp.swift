import SwiftUI
import SwiftData

@main
struct ParadoxHQApp: App {
    @State private var money = MoneyStore()
    @State private var lock = AppLock()
    @State private var feed = FeedSync()
    @State private var site = SiteMonitor()
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Project.self, FocusItem.self, Deadline.self)
        } catch {
            fatalError("The store couldn't be opened: \(error)")
        }
        Seed.run(container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            Gate()
                .environment(money)
                .environment(lock)
                .environment(feed)
                .environment(site)
                .preferredColorScheme(.dark)
                .tint(Ink.violet)
        }
        .modelContainer(container)
    }
}

/// Holds the app behind the lock, and refreshes everything on the way in.
struct Gate: View {
    @Environment(AppLock.self) private var lock
    @Environment(MoneyStore.self) private var money
    @Environment(FeedSync.self) private var feed
    @Environment(SiteMonitor.self) private var site
    @Environment(\.scenePhase) private var phase
    @Environment(\.modelContext) private var context

    var body: some View {
        ZStack {
            RootView()
            if lock.locked || Launch.screen == "lock" {
                LockView()
                    .transition(.opacity)
            } else if phase != .active {
                LockView(cover: true)
            }
        }
        .animation(.easeOut(duration: 0.25), value: lock.locked)
        .task {
            await lock.unlock()
        }
        .task {
            await refresh()
        }
        .onChange(of: phase) { _, new in
            lock.changed(to: new)
            guard new == .active else { return }
            Task {
                // After a refusal the lock waits for a tap, so cancelling
                // Face ID doesn't bring the prompt straight back.
                if !lock.refused { await lock.unlock() }
                await refresh()
            }
        }
    }

    private func refresh() async {
        await money.refresh()
        await feed.pull(into: context)
        await site.check()
    }
}

enum Screen: String, Hashable {
    case today, money, projects, company
}

struct RootView: View {
    @State private var screen: Screen = Launch.screen == "project" ? .projects : Screen(rawValue: Launch.screen) ?? .today

    var body: some View {
        TabView(selection: $screen) {
            Tab("Today", systemImage: "star.fill", value: Screen.today) {
                TodayView()
            }
            Tab("Money", systemImage: "chart.bar.fill", value: Screen.money) {
                MoneyView()
            }
            Tab("Projects", systemImage: "checklist", value: Screen.projects) {
                ProjectsView()
            }
            Tab("Company", systemImage: "building.columns.fill", value: Screen.company) {
                CompanyView()
            }
        }
    }
}
