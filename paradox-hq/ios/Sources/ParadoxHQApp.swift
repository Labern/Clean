import SwiftUI
import UIKit
import SwiftData
import Combine

@main
struct ParadoxHQApp: App {
    // Made in `init`, after a fresh install has had its settings put back, so
    // each one starts from the restored values.
    @State private var money: MoneyStore
    @State private var lock: AppLock
    @State private var feed: FeedSync
    @State private var site: SiteMonitor
    @State private var backups: Backups
    @State private var vault: Vault
    @State private var shelf: IconShelf
    @State private var profile: Profile
    @State private var work: WorkStore
    @State private var cloud: CloudSync
    @AppStorage("appearance") private var appearance: Appearance = .dark
    @AppStorage("typeface") private var typeface: Typeface = .system
    @AppStorage(Palette.accentKey) private var accent = 0
    @AppStorage(Palette.secondKey) private var second = 0
    @AppStorage(Palette.buttonsKey) private var colouredButtons = false
    private let container: ModelContainer

    init() {
        Face.load()
        // The system's own spinner on pull to refresh is hidden: the five stars turn in its place.
        UIRefreshControl.appearance().tintColor = .clear
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Project.self, FocusItem.self, Deadline.self, Note.self)
        } catch {
            fatalError("The store couldn't be opened: \(error)")
        }
        // A fresh install with a copy in the Keychain: everything comes back before anything else runs.
        Vault.recoverIfFresh(container.mainContext)
        self.container = container
        _money = State(initialValue: MoneyStore())
        _lock = State(initialValue: AppLock())
        _feed = State(initialValue: FeedSync())
        _site = State(initialValue: SiteMonitor())
        _backups = State(initialValue: Backups())
        _vault = State(initialValue: Vault())
        _shelf = State(initialValue: IconShelf())
        _profile = State(initialValue: Profile())
        _work = State(initialValue: WorkStore())
        _cloud = State(initialValue: CloudSync())
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
                .environment(vault)
                .environment(shelf)
                .environment(profile)
                .environment(work)
                .environment(cloud)
                .preferredColorScheme(appearance.scheme)
                // Text with no font of its own follows the typeface too; a change redraws everything.
                .font(Face.style(.body))
                // The same for the colours chosen in Settings.
                .id("\(typeface.rawValue) \(accent) \(second) \(colouredButtons)")
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
    @Environment(Vault.self) private var vault
    @Environment(IconShelf.self) private var shelf
    @Environment(WorkStore.self) private var work
    @Environment(CloudSync.self) private var cloud
    @Environment(Profile.self) private var profile
    @Environment(\.scenePhase) private var phase
    @Environment(\.modelContext) private var context
    /// The dashboard's sign-in, shown by itself once, the first time a build that can sync is opened.
    @State private var signingIn = false
    @AppStorage("cloud-asked") private var askedToSignIn = false

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
        .sheet(isPresented: $signingIn) { CloudSignIn() }
        // Anything saved on the phone is sent on a moment later.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in cloud.kick() }
        .onChange(of: lock.locked) { _, locked in
            // Once in, and only the first time: sign in to the dashboard. After that it stays signed in.
            if !locked, cloud.available, !cloud.signedIn, !askedToSignIn {
                askedToSignIn = true
                signingIn = true
            }
        }
        .task {
            // Face ID can only be asked for while the app is in front; before that
            // it fails and would show "Try again" instead of the prompt.
            if phase == .active { await lock.unlock() }
        }
        .task {
            // An icon made in the designer goes on the first time a build carrying it opens.
            // iOS refuses an icon change until the app is active; if it isn't yet, the
            // change below puts it on the moment it is.
            if phase == .active { shelf.adopt() }
            cloud.start(context, profile: profile)
            if !lock.locked, cloud.available, !cloud.signedIn, !askedToSignIn {
                askedToSignIn = true
                signingIn = true
            }
            await refresh()
        }
        .onChange(of: phase) { _, new in
            lock.changed(to: new)
            if new == .background {
                cloud.pause()
                Background.schedule()
                // Every time you leave the app, a copy is kept on the phone and in the
                // Keychain, and another goes to the backup folder.
                try? context.save()
                vault.save(context)
                backups.write(context)
                shelf.mirror(into: backups)
                // Ticks made since the last refresh change what the widgets show.
                Task { await Bridge.publish(money: money, site: site, context: context) }
            }
            guard new == .active else { return }
            shelf.adopt()
            cloud.start(context, profile: profile)
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
        await work.refresh()
    }
}

enum Screen: String, Hashable {
    case today, projects, notes, money, company
}

struct RootView: View {
    @State private var screen: Screen = RootView.opening()

    var body: some View {
        TabView(selection: $screen) {
            // The front page. It was "Today"; the tab's value keeps that name for launch arguments.
            Tab("Work", systemImage: "star.fill", value: Screen.today) {
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
        case "project", "cards": .projects
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
