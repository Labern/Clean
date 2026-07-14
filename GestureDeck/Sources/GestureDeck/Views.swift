import SwiftUI
import AVFoundation
import ServiceManagement

// ── theme ────────────────────────────────────────────────────────────────

extension Color {
    static let gdTeal = Color(red: 0.369, green: 0.918, blue: 0.831)    // #5eead4
    static let gdViolet = Color(red: 0.655, green: 0.545, blue: 0.980)  // #a78bfa
    static let gdPink = Color(red: 0.957, green: 0.447, blue: 0.714)    // #f472b6
    static let gdBgTop = Color(red: 0.118, green: 0.106, blue: 0.294)   // #1e1b4b
    static let gdBgBottom = Color(red: 0.008, green: 0.024, blue: 0.090)
    static let gdMuted = Color(red: 0.392, green: 0.455, blue: 0.545)   // #64748b
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12)))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct GradientTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(.headline, design: .monospaced).weight(.bold))
            .foregroundStyle(LinearGradient(colors: [.gdTeal, .gdViolet, .gdPink],
                                            startPoint: .leading, endPoint: .trailing))
    }
}

// ── menu bar popover ─────────────────────────────────────────────────────

struct PopoverView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                GradientTitle(text: "🖐 GESTUREDECK")
                Spacer()
                Circle()
                    .fill(state.engine.isWatching ? Color.gdTeal : Color.gdMuted)
                    .frame(width: 8, height: 8)
                Text(state.engine.statusText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.gdMuted)
            }

            Toggle("Listening", isOn: $state.config.enabled)
                .toggleStyle(.switch)
                .tint(.gdTeal)

            Toggle("Sound on trigger", isOn: $state.config.soundOn)
                .toggleStyle(.switch)
                .tint(.gdViolet)

            VStack(alignment: .leading, spacing: 4) {
                Text("SEEING").font(.system(size: 9, design: .monospaced)).foregroundColor(.gdMuted)
                Text(state.livePose ?? "—")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.gdViolet)
                Text("LAST TRIGGER").font(.system(size: 9, design: .monospaced)).foregroundColor(.gdMuted)
                    .padding(.top, 4)
                Text(state.lastEvent)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.gdTeal)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.black.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Button {
                    state.showMainWindow()
                } label: {
                    Label("Gestures…", systemImage: "hand.point.up.left")
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .foregroundColor(.gdMuted)
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(LinearGradient(colors: [.gdBgTop, .gdBgBottom],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .preferredColorScheme(.dark)
    }
}

// ── configuration window ─────────────────────────────────────────────────

struct GesturesWindow: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private static let installedApps: [String] = {
        var names = Set<String>()
        for dir in ["/Applications", "/System/Applications", "/Applications/Utilities"] {
            (try? FileManager.default.contentsOfDirectory(atPath: dir))?.forEach {
                if $0.hasSuffix(".app") { names.insert(String($0.dropLast(4))) }
            }
        }
        return names.sorted()
    }()

    var body: some View {
        // wide, low layout: camera + behavior on the left, gestures on the right
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    GradientTitle(text: "🖐 GESTUREDECK")
                    Spacer()
                    Text(state.livePose ?? state.engine.statusText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.gdViolet)
                        .lineLimit(1)
                }

                CameraPreview(session: state.engine.session)
                    .frame(width: 400, height: 300)   // native 4:3, nothing cropped
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gdTeal.opacity(0.3)))

                Card {
                    Text("BEHAVIOR")
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(.gdMuted)
                    Toggle("Play a sound when a gesture triggers", isOn: $state.config.soundOn)
                        .toggleStyle(.switch).tint(.gdViolet)
                    HStack {
                        Picker("Sound", selection: $state.config.soundName) {
                            ForEach(Config.soundChoices, id: \.self) { Text($0) }
                        }
                        .frame(width: 220)
                        Button("Preview") { state.previewSound() }
                        Spacer()
                    }
                    HStack {
                        Text("Hold \(String(format: "%.2fs", state.config.holdSeconds))")
                            .font(.system(.caption, design: .monospaced))
                        Slider(value: $state.config.holdSeconds, in: 0.05...0.6).frame(width: 180)
                        Spacer()
                        Text(state.config.cooldownSeconds > 0
                             ? "Cooldown \(String(format: "%.1fs", state.config.cooldownSeconds))"
                             : "Cooldown off")
                            .font(.system(.caption, design: .monospaced))
                        Slider(value: $state.config.cooldownSeconds, in: 0...5).frame(width: 140)
                    }
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .toggleStyle(.switch).tint(.gdTeal)
                        .onChange(of: launchAtLogin) { on in
                            do {
                                if on { try SMAppService.mainApp.register() }
                                else { try SMAppService.mainApp.unregister() }
                            } catch {
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                }

                Spacer(minLength: 0)

                Text("config: ~/Library/Application Support/GestureDeck/config.json")
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(.gdMuted)
            }
            .frame(width: 400)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Card {
                        Text("ONE HAND")
                            .font(.system(size: 10, design: .monospaced)).foregroundColor(.gdMuted)
                        ForEach(Gesture.allCases.filter { !$0.isTwoHanded }) { g in
                            GestureRow(gesture: g, action: state.binding(for: g),
                                       apps: Self.installedApps) { state.test(g) }
                        }
                    }

                    Card {
                        Text("BOTH HANDS")
                            .font(.system(size: 10, design: .monospaced)).foregroundColor(.gdMuted)
                        ForEach(Gesture.allCases.filter { $0.isTwoHanded }) { g in
                            GestureRow(gesture: g, action: state.binding(for: g),
                                       apps: Self.installedApps) { state.test(g) }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 1100, height: 640)
        .background(LinearGradient(colors: [.gdBgTop, .gdBgBottom],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .preferredColorScheme(.dark)
        // let non-view code (menu button, open-palm gesture) reopen this window
        .onAppear { state.openWindowAction = { openWindow(id: "main") } }
    }
}

private struct GestureRow: View {
    let gesture: Gesture
    @Binding var action: GestureAction
    let apps: [String]
    let onTest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(gesture.icon).font(.system(size: 28)).frame(width: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text(gesture.title).font(.system(size: 15, design: .monospaced).weight(.semibold))
                    Text(gesture.hint).font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gdMuted)
                }
                Spacer()
                Toggle("", isOn: $action.enabled).toggleStyle(.switch).tint(.gdTeal)
                    .labelsHidden()
            }
            HStack(spacing: 8) {
                Picker("", selection: $action.kind) {
                    ForEach(ActionKind.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 140)

                switch action.kind {
                case .none:
                    Text("does nothing").font(.system(.caption, design: .monospaced))
                        .foregroundColor(.gdMuted)
                case .deck:
                    Text("brings GestureDeck to the front")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.gdMuted)
                case .playPause:
                    Text("toggles play / pause (Spotify, Music, video…)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.gdMuted)
                case .play:
                    Text("plays music (Spotify / Apple Music)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.gdMuted)
                case .pause:
                    Text("pauses music (Spotify / Apple Music)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.gdMuted)
                case .app:
                    Picker("", selection: $action.value) {
                        if !apps.contains(action.value) && !action.value.isEmpty {
                            Text(action.value).tag(action.value)
                        }
                        Text("choose app…").tag("")
                        ForEach(apps, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                case .url:
                    TextField("https://…", text: $action.value)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                case .shell:
                    TextField("shell command", text: $action.value)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                }

                if action.kind != .none {
                    Button("Test") { onTest() }.font(.caption)
                }
            }
            .padding(.leading, 50)
            .opacity(action.enabled ? 1 : 0.4)
            Divider().overlay(Color.white.opacity(0.06))
        }
    }
}

// ── live camera preview ──────────────────────────────────────────────────

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.backgroundColor = NSColor.black.cgColor
        if let conn = layer.connection, conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = true
        }
        view.layer = layer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
