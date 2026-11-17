import SwiftUI
import SwiftData

@main
struct ParadoxHQApp: App {
    @State private var money = MoneyStore()
    @State private var lock = AppLock()
    @State private var feed = FeedSync()
    @State private var site = SiteMonitor()
    @State private var backups = Backups()
    @State private var shelf = IconShelf()
    @AppStorage("appearance") private var appearance: Appearance = .auto
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Project.self, FocusItem.self, Deadline.self, Note.self)
        } catch {
            fatalError("The store couldn't be opened: \(error)")
        }
        Seed.run(container.mainContext)
        if !Launch.unlocked { Starter.run(container.mainContext) }
        Seed.sampleNotes(container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            Gate()
                .environment(money)
                .environment(lock)
                .environment(feed)
                .environment(site)
                .environment(backups)
                .environment(shelf)
                .preferredColorScheme(appearance.scheme)
                .tint(Ink.violet)
        }
        .modelContainer(container)
        .backgroundTask(.appRefresh(Background.id)) {
            await Background.run()
        }
    }
}

/// Holds the app behind the lock, and refreshes everything on the way in.
struct Gate: View {
    @Environment(AppLock.self) private var lock
    @Environment(MoneyStore.self) private var money
    @Environment(FeedSync.self) private var feed
    @Environment(SiteMonitor.self) private var site
    @Environment(Backups.self) private var backups
    @Environment(IconShelf.self) private var shelf
    @Environment(\.scenePhase) private var phase
    @Environment(\.modelContext) private var context

    var body: some View {
        ZStack {
            if Launch.screen == "widgets" {
                WidgetGallery()
            } else if Launch.screen == "designer" {
                IconDesigner()
            } else {
                RootView()
            }
            if lock.locked || Launch.screen == "lock" {
                LockView()
                    .transition(.opacity)
            } else if phase != .active {
                LockView(cover: true)
            }
        }
        .animation(.easeOut(duration: 0.25), value: lock.locked)
        .task {
            // Face ID can only be asked for while the app is in front; before that
            // it fails and would show "Try again" instead of the prompt.
            if phase == .active { await lock.unlock() }
        }
        .task {
            // An icon made in the designer goes on the first time a build carrying it opens.
            shelf.adopt()
            await refresh()
        }
        .onChange(of: phase) { _, new in
            lock.changed(to: new)
            if new == .background {
                Background.schedule()
                // Every time you leave the app, a copy goes to the backup folder.
                try? context.save()
                backups.write(context)
                shelf.mirror(into: backups)
                // Ticks made since the last refresh change what the widgets show.
                Task { await Bridge.publish(money: money, site: site, context: context) }
            }
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
        await Bridge.publish(money: money, site: site, context: context)
    }
}

enum Screen: String, Hashable {
    case today, projects, notes, money, company
}

struct RootView: View {
    @State private var screen: Screen = RootView.opening()

    var body: some View {
        TabView(selection: $screen) {
            Tab("Today", systemImage: "star.fill", value: Screen.today) {
                TodayView()
            }
            Tab("To-do", systemImage: "checklist", value: Screen.projects) {
                ProjectsView()
            }
            Tab("Notes", systemImage: "note.text", value: Screen.notes) {
                NotesView()
            }
            Tab("Money", systemImage: "chart.bar.fill", value: Screen.money) {
                MoneyView()
            }
            Tab("Company", systemImage: "building.columns.fill", value: Screen.company) {
                CompanyView()
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

extension RootView {
    /// The tab to open on, which a launch argument can choose.
    static func opening() -> Screen {
        switch Launch.screen {
        case "project": .projects
        case "note": .notes
        default: Screen(rawValue: Launch.screen) ?? .today
        }
    }
}

/// The widgets drawn at their real sizes, so the cloud build can photograph them.
/// Reached only with the launch argument `-screen widgets`.
struct WidgetGallery: View {
    var body: some View {
        let snapshot = WidgetSnapshot.sample
        ScrollView {
            VStack(spacing: 22) {
                WidgetSmall(snapshot: snapshot)
                    .padding(16)
                    .frame(width: 170, height: 170)
                    .background(.black, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                WidgetMedium(snapshot: snapshot)
                    .padding(16)
                    .frame(width: 364, height: 170)
                    .background(.black, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                HStack(spacing: 16) {
                    WidgetLockRect(snapshot: snapshot)
                        .padding(8)
                        .frame(width: 172, height: 76)
                        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    WidgetLockCircle(snapshot: snapshot)
                        .frame(width: 76, height: 76)
                        .background(.white.opacity(0.14), in: Circle())
                }
                .foregroundStyle(.white)
            }
            .padding(.top, 70)
            .frame(maxWidth: .infinity)
        }
        .background(Color(hex: 0x2B2440))
    }
}
