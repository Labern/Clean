import SwiftUI
import UIKit
import WebKit
import ImageIO
import UniformTypeIdentifiers

// The icon designer. Self-contained on purpose: this file, `Resources/IconDesigner`
// and the bake script are everything a spin-off app needs.

/// An icon made in the designer: a 1024px picture, plus the recipe that drew it.
nonisolated struct CustomIcon: Codable, Identifiable, Hashable {
    /// Eight letters and digits. Also the picture's file name and the end of its asset name.
    var id: String
    var title: String
    var created: Date
    /// The designer's own state as JSON, so the icon can be reopened and redrawn.
    var recipe: String

    /// The alternate icon set a build carries this icon as.
    var asset: String { "AppIcon-Custom-\(id)" }
}

/// The icons made on this phone.
///
/// iOS only lets an app wear icons it was built with, so a new one can't go on
/// the Home Screen straight away. It is kept here, copied into the backup
/// folder, and baked into the next build (`design/icons/bake_custom.sh`). The
/// one marked `wanted` is put on as soon as a build carrying it is opened.
@MainActor @Observable final class IconShelf {
    /// The folder, inside the backup folder, that the Mac build reads icons from.
    nonisolated static let exportFolder = "PARADOX icons"
    nonisolated static let side = 1024

    private(set) var icons: [CustomIcon] = []
    /// The id of the custom icon to wear once a build carries it.
    var wanted: String = UserDefaults.standard.string(forKey: "icon-wanted") ?? "" {
        didSet { UserDefaults.standard.set(wanted, forKey: "icon-wanted") }
    }
    @ObservationIgnored private let folder: URL
    @ObservationIgnored private var pictures: [String: UIImage] = [:]

    init(folder: URL = URL.applicationSupportDirectory.appending(path: "Icons")) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: folder.appending(path: "icons.json")),
           let saved = try? JSONDecoder().decode([CustomIcon].self, from: data) {
            icons = saved
        }
    }

    func file(_ icon: CustomIcon) -> URL { folder.appending(path: "\(icon.id).png") }

    func picture(_ icon: CustomIcon) -> UIImage? {
        if let held = pictures[icon.id] { return held }
        let loaded = UIImage(contentsOfFile: file(icon).path(percentEncoded: false))
        pictures[icon.id] = loaded
        return loaded
    }

    @discardableResult
    func add(png: Data, title: String, recipe: String, now: Date = .now) throws -> CustomIcon {
        let icon = CustomIcon(id: Self.newID(), title: title, created: now, recipe: recipe)
        try png.write(to: file(icon), options: .atomic)
        icons.append(icon)
        try save()
        return icon
    }

    func remove(_ icon: CustomIcon) {
        icons.removeAll { $0.id == icon.id }
        pictures[icon.id] = nil
        try? FileManager.default.removeItem(at: file(icon))
        if wanted == icon.id { wanted = "" }
        try? save()
    }

    private func save() throws {
        try JSONEncoder().encode(icons).write(to: folder.appending(path: "icons.json"), options: .atomic)
    }

    /// True when this build was made with the icon inside it, so iOS will wear it.
    func isInstalled(_ icon: CustomIcon) -> Bool { Self.installed().contains(icon.asset) }

    /// Puts the wanted icon on once a build carries it. Called as the app opens.
    func adopt() {
        guard let icon = icons.first(where: { $0.id == wanted }), isInstalled(icon),
              UIApplication.shared.supportsAlternateIcons else { return }
        wanted = ""
        guard UIApplication.shared.alternateIconName != icon.asset else { return }
        UIApplication.shared.setAlternateIconName(icon.asset) { _ in }
    }

    /// Copies every icon into the backup folder and clears out ones deleted here,
    /// so the folder always holds exactly the icons on the phone. Quiet without a folder.
    func mirror(into backups: Backups) {
        let keep = Set(icons.map { "\($0.id).png" })
        try? backups.withFolder { root in
            let target = root.appending(path: Self.exportFolder)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            for icon in icons {
                let copy = target.appending(path: "\(icon.id).png")
                guard !FileManager.default.fileExists(atPath: copy.path(percentEncoded: false)),
                      let data = try? Data(contentsOf: file(icon)) else { continue }
                var coordinated: NSError? = nil
                NSFileCoordinator().coordinate(writingItemAt: copy, options: .forReplacing, error: &coordinated) { url in
                    try? data.write(to: url, options: .atomic)
                }
            }
            let there = (try? FileManager.default.contentsOfDirectory(atPath: target.path(percentEncoded: false))) ?? []
            for name in Self.strays(in: there, keeping: keep) {
                try? FileManager.default.removeItem(at: target.appending(path: name))
            }
        }
    }

    // MARK: Pure parts, tested

    /// The alternate icons a build's Info.plist lists.
    nonisolated static func installed(in info: [String: Any]? = Bundle.main.infoDictionary) -> Set<String> {
        let icons = info?["CFBundleIcons"] as? [String: Any]
        let alternates = icons?["CFBundleAlternateIcons"] as? [String: Any]
        return Set((alternates ?? [:]).keys)
    }

    /// Pictures in the export folder that no longer belong to an icon on the phone.
    nonisolated static func strays(in names: [String], keeping keep: Set<String>) -> [String] {
        names.filter { $0.hasSuffix(".png") && !keep.contains($0) }
    }

    nonisolated static func newID() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(8))
    }

    /// The picture out of the page's "data:image/png;base64,…" answer.
    nonisolated static func decode(dataURL: String) -> Data? {
        guard let comma = dataURL.firstIndex(of: ","), dataURL.hasPrefix("data:image/png;base64") else { return nil }
        return Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...]))
    }

    /// Redraws a picture as an exact 1024px square with no alpha channel at all,
    /// which is the only kind of PNG an app icon may be. (UIKit's opaque renderer
    /// still writes one, so this goes through a bitmap that has nowhere to keep it.)
    nonisolated static func flatten(_ png: Data) -> Data? {
        guard let provider = CGDataProvider(data: png as CFData),
              let picture = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: true,
                                    intent: .defaultIntent),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let bitmap = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let whole = CGRect(x: 0, y: 0, width: side, height: side)
        bitmap.interpolationQuality = .high
        bitmap.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        bitmap.fill(whole)
        bitmap.draw(picture, in: whole)
        let out = NSMutableData()
        guard let flat = bitmap.makeImage(),
              let file = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(file, flat, nil)
        return CGImageDestinationFinalize(file) ? out as Data : nil
    }
}

/// The artboard: a web view running the logo playground's own drawing code
/// (`Resources/IconDesigner/designer.html`). The app asks through `window.D`
/// and the page answers through the "designer" message handler.
@MainActor @Observable final class DesignerBoard: NSObject, WKScriptMessageHandler {
    private(set) var label = ""
    private(set) var index = 0
    private(set) var total = 0
    private(set) var ground = 0
    private(set) var count = 1
    private(set) var moved = false
    private(set) var grounds: [Color] = []
    /// Goes up each time the mark snaps to the centre or to 45°, for the haptic.
    private(set) var ticks = 0
    private(set) var problem = ""
    @ObservationIgnored var saved: ((_ png: Data, _ title: String, _ recipe: String) -> Void)?
    @ObservationIgnored private(set) lazy var web: WKWebView = make()

    private func make() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(Relay(self), name: "designer")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.pinchGestureRecognizer?.isEnabled = false
        if let page = Self.page {
            web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        } else {
            problem = "The designer is missing from this build."
        }
        return web
    }

    /// The page, wherever the build put it.
    nonisolated static var page: URL? {
        Bundle.main.url(forResource: "designer", withExtension: "html")
            ?? Bundle.main.url(forResource: "designer", withExtension: "html", subdirectory: "IconDesigner")
    }

    /// Calls one of the page's own functions, e.g. `step(1)`.
    func ask(_ call: String) {
        web.evaluateJavaScript("if (window.D) { D.\(call) }; null", completionHandler: nil)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            grounds = (body["grounds"] as? [String] ?? []).map(Self.colour)
        case "state":
            label = body["label"] as? String ?? ""
            index = body["index"] as? Int ?? 0
            total = body["total"] as? Int ?? 0
            ground = body["ground"] as? Int ?? 0
            count = body["count"] as? Int ?? 1
            moved = body["moved"] as? Bool ?? false
        case "tick":
            ticks += 1
        case "saved":
            guard let text = body["png"] as? String, let raw = IconShelf.decode(dataURL: text),
                  let png = IconShelf.flatten(raw) else {
                problem = "The icon couldn't be drawn."
                return
            }
            saved?(png, body["label"] as? String ?? "", body["recipe"] as? String ?? "")
        case "failed":
            problem = "The icon couldn't be drawn."
        default:
            break
        }
    }

    /// "#594992" as a colour.
    static func colour(_ hex: String) -> Color {
        Color(hex: UInt32(hex.dropFirst(), radix: 16) ?? 0)
    }

    /// The web view keeps its handler alive; this keeps the handler from keeping the board alive.
    private final class Relay: NSObject, WKScriptMessageHandler {
        weak var board: DesignerBoard?
        init(_ board: DesignerBoard) { self.board = board }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            board?.userContentController(controller, didReceive: message)
        }
    }
}

private struct BoardView: UIViewRepresentable {
    let board: DesignerBoard
    func makeUIView(context: Context) -> WKWebView { board.web }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

/// Make an icon: pick a mark and a ground, then move, size and spin it with your fingers.
struct IconDesigner: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(IconShelf.self) private var shelf
    @Environment(Backups.self) private var backups
    @State private var board = DesignerBoard()
    @State private var saving = false
    @State private var landed = 0
    @State private var hits = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Ink.body)
                Spacer()
                Button {
                    saving = true
                    board.ask("save()")
                } label: {
                    Text("Save")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Ink.buttonInk)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 36)
                        .background(Ink.button, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(saving || board.total == 0)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer(minLength: 12)
            GeometryReader { space in
                let side = min(space.size.width, space.size.height)
                let shape = RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                BoardView(board: board)
                    .frame(width: side, height: side)
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(Ink.line, lineWidth: 1) }
                    // Hit stop: the saved icon punches in, holds for a few frames, then lets go.
                    .keyframeAnimator(initialValue: CGFloat(1), trigger: hits) { view, scale in
                        view.scaleEffect(scale)
                    } keyframes: { _ in
                        KeyframeTrack {
                            LinearKeyframe(0.92, duration: 0.06)
                            LinearKeyframe(0.92, duration: 0.10)
                            SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal, 36)
            Spacer(minLength: 12)

            if !board.problem.isEmpty {
                Text(board.problem)
                    .font(.footnote)
                    .foregroundStyle(Ink.hazard)
                    .padding(.bottom, 8)
            }
            controls
        }
        .background(Ink.ground)
        .sensoryFeedback(.selection, trigger: board.ticks)
        .sensoryFeedback(.selection, trigger: board.index)
        .sensoryFeedback(.selection, trigger: board.ground)
        .sensoryFeedback(.selection, trigger: board.count)
        .sensoryFeedback(.success, trigger: landed)
        .onAppear {
            board.saved = { png, title, recipe in
                do {
                    try shelf.add(png: png, title: title, recipe: recipe)
                    shelf.mirror(into: backups)
                    landed += 1
                    guard !reduceMotion else { return dismiss() }
                    hits += 1
                    Task {
                        try? await Task.sleep(for: .milliseconds(380))
                        dismiss()
                    }
                } catch {
                    saving = false
                }
            }
        }
        .onChange(of: board.problem) { saving = false }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                key("chevron.left", "Previous mark") { board.ask("step(-1)") }
                VStack(spacing: 2) {
                    Text(board.label)
                        .font(.footnote.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(Ink.head)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(board.total == 0 ? " " : "\(board.index + 1) of \(board.total)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Ink.muted)
                }
                .frame(maxWidth: .infinity)
                .contentTransition(.opacity)
                key("chevron.right", "Next mark") { board.ask("step(1)") }
            }
            HStack(spacing: 12) {
                ForEach(Array(board.grounds.enumerated()), id: \.offset) { index, colour in
                    Button { board.ask("ground(\(index))") } label: {
                        Circle()
                            .fill(colour)
                            .frame(width: 30, height: 30)
                            .overlay { Circle().strokeBorder(Ink.line, lineWidth: 1) }
                            .padding(4)
                            .overlay {
                                Circle().strokeBorder(board.ground == index ? Ink.head : Color.clear, lineWidth: 2)
                            }
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ground \(index + 1)")
                    .accessibilityAddTraits(board.ground == index ? .isSelected : [])
                }
            }
            HStack(spacing: 10) {
                key("minus", "Fewer") { board.ask("count(-1)") }
                Text("×\(board.count)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Ink.head)
                    .frame(minWidth: 30)
                key("plus", "More") { board.ask("count(1)") }
                Spacer(minLength: 4)
                key("rotate.right", "Turn 45 degrees") { board.ask("turn(45)") }
                key("arrow.counterclockwise", "Reset") { board.ask("reset()") }
                    .disabled(!board.moved)
                    .opacity(board.moved ? 1 : 0.35)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private func key(_ symbol: String, _ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Ink.body)
                .frame(width: 44, height: 44)
                .background(Ink.surface2, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }
}
