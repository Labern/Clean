import SwiftUI
import AppKit
import Combine
import ServiceManagement

// NB: deliberately not named main.swift — that would conflict with @main.
@main
struct GestureDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        // A real Window scene is what makes this a genuine app: a Dock icon,
        // a ⌘-Tab app-switcher entry, and a standard menu with ⌘Q to quit.
        // (A MenuBarExtra-only app has no window scene, so macOS runs it as a
        // background accessory — no Dock icon, not in ⌘-Tab, impossible to
        // quit normally. That was the whole problem.)
        Window("GestureDeck", id: "main") {
            GesturesWindow().environmentObject(state)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1100, height: 700)

        // The menu-bar item stays too — quick toggle without opening the window.
        MenuBarExtra {
            PopoverView().environmentObject(state)
        } label: {
            Image(systemName: state.config.enabled ? "hand.raised.fill" : "hand.raised.slash.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Regular app: Dock + ⌘-Tab. The Window scene already forces this, but
        // assert it and bring ourselves to the front on launch.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // launch at login, always — no toggle hunting
        if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
    }

    // Dock-icon click with no open window → reopen the config window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppState.shared.showMainWindow() }
        return true
    }

    // Flush any pending settings write before we exit — belt and suspenders.
    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.saveNow()
    }
}

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var config: Config {
        didSet {
            engine.holdFrames = max(2, Int(config.holdSeconds * 30))
            if config.enabled != oldValue.enabled {
                config.enabled ? engine.start() : engine.stop()
            }
            scheduleSave()
        }
    }
    @Published var lastEvent = "no triggers yet"
    @Published var livePose: String?

    /// Set by the config window once it appears — lets non-view code (the menu
    /// button, the open-palm gesture) reopen the SwiftUI window even after it
    /// has been closed.
    var openWindowAction: (() -> Void)?

    let engine = GestureEngine()
    private var lastFired: [String: Date] = [:]
    private var saveWork: DispatchWorkItem?
    private var bag = Set<AnyCancellable>()
    private let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private init() {
        config = Config.load()
        engine.holdFrames = max(2, Int(config.holdSeconds * 30))
        engine.onGesture = { [weak self] g, isRepeat in self?.trigger(g, isRepeat: isRepeat) }
        engine.onPose = { [weak self] label in self?.livePose = label }
        // views observe AppState, not the engine — forward its changes so
        // the status text / watching dot actually refresh in the UI
        engine.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
        if config.enabled { engine.start() }
    }

    /// Bring GestureDeck's window to the front, reopening it if it was closed.
    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let open = openWindowAction {
            open()
        } else if let w = NSApp.windows.first(where: { $0.title == "GestureDeck" }) {
            w.makeKeyAndOrderFront(nil)
        }
    }

    // typing in a URL/command field mutates config on every keystroke —
    // coalesce disk writes instead of hitting the file each time
    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [config] in config.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Write settings to disk right now (cancels any debounced write). Called
    /// the instant a gesture mapping changes so nothing is ever lost.
    func saveNow() {
        saveWork?.cancel()
        config.save()
    }

    private func trigger(_ gesture: Gesture, isRepeat: Bool = false) {
        guard config.enabled,
              let action = config.actions[gesture.rawValue],
              action.enabled, action.kind != .none,
              !(action.kind.needsValue && action.value.isEmpty),
              !isRepeat || action.repeats else { return }
        let now = Date()
        if config.cooldownSeconds > 0,
           let last = lastFired[gesture.rawValue],
           now.timeIntervalSince(last) < config.cooldownSeconds { return }
        lastFired[gesture.rawValue] = now

        if config.soundOn { NSSound(named: config.soundName)?.play() }
        ActionRunner.run(action)
        lastEvent = "\(gesture.icon) \(gesture.title) → \(action.summary)  ·  \(timeFmt.string(from: now))"
    }

    func test(_ gesture: Gesture) {
        guard let action = config.actions[gesture.rawValue],
              action.kind != .none,
              !(action.kind.needsValue && action.value.isEmpty) else { return }
        if config.soundOn { NSSound(named: config.soundName)?.play() }
        ActionRunner.run(action)
    }

    func previewSound() {
        NSSound(named: config.soundName)?.play()
    }

    func binding(for gesture: Gesture) -> Binding<GestureAction> {
        Binding(
            get: { self.config.actions[gesture.rawValue] ?? GestureAction() },
            set: {
                var v = $0
                let cur = self.config.actions[gesture.rawValue]
                // Only a REAL change counts as a user edit (SwiftUI fires the
                // setter with an identical value on appear — ignore those). A
                // genuine edit is flagged userSet so future default-map updates
                // never overwrite it, and is persisted immediately.
                let changed = cur == nil || cur!.kind != v.kind || cur!.value != v.value
                    || cur!.enabled != v.enabled || cur!.repeats != v.repeats
                if changed {
                    v.userSet = true
                    self.config.actions[gesture.rawValue] = v
                    self.saveNow()
                }
            }
        )
    }
}
