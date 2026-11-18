import SwiftUI
import UIKit
import WebKit

// The designer, lifted out of PARADOX HQ. The artboard is the logo playground
// (`Resources/IconDesigner/designer.html`); SwiftUI draws the controls.

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
    @Environment(IconFolder.self) private var place
    @Environment(\.theme) private var theme
    @State private var board = DesignerBoard()
    @State private var saving = false
    @State private var landed = 0
    @State private var hits = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(theme.body)
                Spacer()
                Button {
                    saving = true
                    board.ask("save()")
                } label: {
                    Text("Save")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.onHead)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 36)
                        .background(theme.head, in: Capsule())
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
                    .overlay { shape.strokeBorder(theme.line, lineWidth: 1) }
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
                    .foregroundStyle(theme.hazard)
                    .padding(.bottom, 8)
            }
            controls
        }
        .background(theme.ground)
        .sensoryFeedback(.selection, trigger: board.ticks)
        .sensoryFeedback(.selection, trigger: board.index)
        .sensoryFeedback(.selection, trigger: board.ground)
        .sensoryFeedback(.selection, trigger: board.count)
        .sensoryFeedback(.success, trigger: landed)
        .onAppear {
            board.saved = { png, title, recipe in
                do {
                    try shelf.add(png: png, title: title, recipe: recipe)
                    shelf.mirror(into: place)
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
                        .foregroundStyle(theme.head)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(board.total == 0 ? " " : "\(board.index + 1) of \(board.total)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(theme.muted)
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
                            .overlay { Circle().strokeBorder(theme.line, lineWidth: 1) }
                            .padding(4)
                            .overlay {
                                Circle().strokeBorder(board.ground == index ? theme.head : Color.clear, lineWidth: 2)
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
                    .foregroundStyle(theme.head)
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
                .foregroundStyle(theme.body)
                .frame(width: 44, height: 44)
                .background(theme.surface2, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }
}
