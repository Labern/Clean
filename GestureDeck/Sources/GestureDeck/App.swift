import SwiftUI
import AppKit

// NB: deliberately not named main.swift — that would conflict with @main.
@main
struct GestureDeckApp: App {
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverView().environmentObject(state)
        } label: {
            Image(systemName: state.config.enabled ? "hand.raised.fill" : "hand.raised.slash.fill")
        }
        .menuBarExtraStyle(.window)

        Window("GestureDeck", id: "gestures") {
            GesturesWindow().environmentObject(state)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 580, height: 760)
    }
}

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var config: Config {
        didSet {
            config.save()
            applyConfig()
        }
    }
    @Published var lastEvent = "no triggers yet"
    @Published var livePose: String?

    let engine = GestureEngine()
    private var lastFired: [String: Date] = [:]
    private let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private init() {
        config = Config.load()
        engine.onGesture = { [weak self] g in self?.trigger(g) }
        engine.onPose = { [weak self] label in self?.livePose = label }
        applyConfig()
    }

    private func applyConfig() {
        engine.holdFrames = max(2, Int(config.holdSeconds * 15))
        if config.enabled { engine.start() } else { engine.stop() }
    }

    private func trigger(_ gesture: Gesture) {
        guard config.enabled,
              let action = config.actions[gesture.rawValue],
              action.enabled, action.kind != .none, !action.value.isEmpty else { return }
        let now = Date()
        if let last = lastFired[gesture.rawValue],
           now.timeIntervalSince(last) < config.cooldownSeconds { return }
        lastFired[gesture.rawValue] = now

        if config.soundOn { NSSound(named: config.soundName)?.play() }
        ActionRunner.run(action)
        lastEvent = "\(gesture.icon) \(gesture.title) → \(action.summary)  ·  \(timeFmt.string(from: now))"
    }

    func test(_ gesture: Gesture) {
        guard let action = config.actions[gesture.rawValue],
              action.kind != .none, !action.value.isEmpty else { return }
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
