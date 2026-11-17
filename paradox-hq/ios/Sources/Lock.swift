import SwiftUI
import LocalAuthentication
import Observation

/// Face ID (or the passcode) stands between the Home Screen and the figures.
/// The app locks at launch and again after half a minute away.
@Observable final class AppLock {
    static let away: TimeInterval = 30

    var locked: Bool
    var asking = false
    var refused = false
    private var leftAt: Date? = nil

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "lock") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "lock") }
    }

    init() {
        locked = Self.enabled && !Launch.unlocked
    }

    /// The symbol for whatever this phone unlocks with.
    var symbol: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock"
        }
    }

    func lock() {
        guard Self.enabled else { return }
        locked = true
        refused = false
    }

    func unlock() async {
        guard locked, !asking else { return }
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            // No Face ID and no passcode on this device (a fresh Simulator):
            // there is nothing to check against.
            locked = false
            return
        }
        asking = true
        let passed: Bool = await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Open PARADOX") { @Sendable success, _ in
                continuation.resume(returning: success)
            }
        }
        asking = false
        locked = !passed
        refused = !passed
    }

    func changed(to phase: ScenePhase) {
        switch phase {
        case .background:
            if leftAt == nil { leftAt = .now }
        case .active:
            if let leftAt, Date.now.timeIntervalSince(leftAt) > Self.away { lock() }
            leftAt = nil
        default:
            break
        }
    }
}

/// The mark on black. Shown while locked, and over the app in the switcher
/// so the figures never appear in a screenshot of recent apps.
struct LockView: View {
    @Environment(AppLock.self) private var lock
    @State private var arrived = false
    var cover = false

    var body: some View {
        ZStack {
            Ink.ground.ignoresSafeArea()
            VStack(spacing: 44) {
                MarkView(width: 230)
                    .opacity(arrived ? 1 : 0)
                    .offset(y: arrived ? 0 : 8)
                if !cover {
                    Button {
                        Task { await lock.unlock() }
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: lock.symbol)
                                .font(.system(size: 44, weight: .light))
                            if lock.refused {
                                Text("Try again")
                                    .font(.footnote.weight(.semibold))
                            }
                        }
                        .foregroundStyle(Ink.violet)
                        .frame(minWidth: 88, minHeight: 88)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Unlock")
                    .opacity(lock.asking ? 0.35 : 1)
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { arrived = true }
        }
    }
}
