import SwiftUI
import AppKit
import ServiceManagement

// NB: deliberately not named main.swift — that would conflict with @main.
@main
struct GestureDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
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
        // launch at login, always — no toggle hunting
        if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
        WindowManager.shared.show()
    }
}

/// One AppKit-managed config window. A plain NSWindow (not a SwiftUI Window
/// scene) so a menu-bar app can reliably open it at launch, bring it to the
/// front, and have every control receive clicks immediately.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 860),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            w.title = "GestureDeck"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(
                rootView: GesturesWindow().environmentObject(AppState.shared))
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

    let engine = GestureEngine()
    private var lastFired: [String: Date] = [:]
    private var saveWork: DispatchWorkItem?
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
        if config.enabled { engine.start() }
    }

    // typing in a URL/command field mutates config on every keystroke —
    // coalesce disk writes instead of hitting the file each time
    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [config] in config.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
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
            set: { self.config.actions[gesture.rawValue] = $0 }
        )
    }
}
