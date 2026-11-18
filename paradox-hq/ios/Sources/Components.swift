import SwiftUI

/// ★★★★★ × PARADOX™, drawn from the logo's own outlines.
struct MarkView: View {
    var width: CGFloat = 150

    var body: some View {
        Image("Mark")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width)
            .foregroundStyle(Ink.head)
            .accessibilityLabel("Five stars times PARADOX")
    }
}

/// The Focus site's heading: large, white, with a white line under it.
struct Heading: View {
    let title: String
    var detail: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Face.at(34, .semibold))
                    .tracking(-0.8)
                    .foregroundStyle(Ink.head)
                Spacer(minLength: 8)
                if !detail.isEmpty {
                    Text(detail)
                        .font(Face.style(.subheadline))
                        .foregroundStyle(Ink.muted)
                        .monospacedDigit()
                }
            }
            Rectangle()
                .fill(Ink.head)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            // The Focus site's eyebrow: small, upper case, tracked out.
            Text(title)
                .font(Face.at(12, .semibold))
                .textCase(.uppercase)
                .tracking(0.9)
            Spacer(minLength: 8)
            if !trailing.isEmpty {
                Text(trailing)
                    .font(Face.at(12, .medium))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .foregroundStyle(Ink.muted)
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

struct Hairline: View {
    var inset: CGFloat = 14

    var body: some View {
        Rectangle()
            .fill(Ink.line)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

struct Pill: View {
    let text: String
    var color: Color = Ink.muted

    var body: some View {
        Text(text)
            .font(Face.style(.caption, .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
    }
}

/// Up or down against the period before.
struct ChangePill: View {
    let change: Double?

    var body: some View {
        if let change {
            let up = change >= 0
            Pill(text: "\(up ? "▲" : "▼") \(abs(change).formatted(.percent.precision(.fractionLength(0))))",
                 color: up ? Ink.ok : Ink.hazard)
        }
    }
}

/// A company's mark in the shape of an app icon. The art is a full square;
/// the corners are cut here, in iOS's own proportion.
struct LogoTile: View {
    let name: String
    var size: CGFloat = 32

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        Image(name)
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Ink.line, lineWidth: 1) }
            .accessibilityHidden(true)
    }
}

/// A row with a title, a line under it, and something on the right.
struct InfoRow<Trailing: View>: View {
    /// A company's tile, drawn instead of the symbol when set.
    var logo: String = ""
    var symbol: String = ""
    var symbolColor: Color = Ink.muted
    let title: String
    var detail: String = ""
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            if !logo.isEmpty {
                LogoTile(name: logo)
            } else if !symbol.isEmpty {
                Image(systemName: symbol)
                    .font(Face.at(15, .semibold))
                    .foregroundStyle(symbolColor)
                    .frame(width: 32, height: 32)
                    .background(Ink.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Ink.body)
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .font(Face.style(.caption))
                        .foregroundStyle(Ink.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

/// The one white button on a screen. On the Focus site, solid white is the reward.
struct WhiteButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Face.style(.headline))
            .foregroundStyle(Ink.buttonInk)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Ink.button, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Face.style(.subheadline, .semibold))
            .foregroundStyle(Ink.body)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Ink.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The round tick used on every Focus line. Ticking lands with hit stop:
/// it swells, freezes for a few frames at full size, then settles.
struct Tick: View {
    let done: Bool
    var color: Color = Ink.head
    var size: CGFloat = 24
    @State private var hits = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(done ? Color.clear : Ink.idle, lineWidth: 1.5)
            if done {
                Circle().fill(color)
                Image(systemName: "checkmark")
                    .font(Face.at(size * 0.46, .bold))
                    .foregroundStyle(Ink.buttonInk)
            }
        }
        .frame(width: size, height: size)
        .keyframeAnimator(initialValue: CGFloat(1), trigger: hits) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(1.42, duration: 0.06)
                LinearKeyframe(1.42, duration: 0.10)
                SpringKeyframe(1.0, duration: 0.32, spring: .bouncy)
            }
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .onChange(of: done) { _, landed in
            if landed, !reduceMotion { hits += 1 }
        }
    }
}

/// A thin bar of how much of a project is done.
struct Meter: View {
    let done: Int
    let total: Int
    var color: Color = Ink.head

    var body: some View {
        GeometryReader { proxy in
            let fraction = total > 0 ? CGFloat(done) / CGFloat(total) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.surface2)
                Capsule().fill(color).frame(width: max(0, proxy.size.width * fraction))
            }
        }
        .frame(height: 5)
        .accessibilityLabel("\(done) of \(total) done")
    }
}

/// Says plainly that the figures on screen aren't the company's yet.
struct ExampleBanner: View {
    let connect: () -> Void

    var body: some View {
        Button(action: connect) {
            HStack(spacing: 10) {
                Image(systemName: "eye")
                    .foregroundStyle(Ink.amber)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Example figures")
                        .font(Face.style(.subheadline, .semibold))
                        .foregroundStyle(Ink.body)
                    Text("Connect Stripe to see your own.")
                        .font(Face.style(.caption))
                        .foregroundStyle(Ink.muted)
                }
                Spacer(minLength: 8)
                Text("Connect")
                    .font(Face.style(.subheadline, .semibold))
                    .foregroundStyle(Ink.buttonInk)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 34)
                    .background(Ink.button, in: Capsule())
            }
            .padding(12)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Every screen sits on black with the same gutters.
    func page() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
    }
}

extension Animation {
    /// The Focus site's one curve: quick off the mark, soft landing.
    static let paradox = Animation.timingCurve(0.5, 0, 0, 0.75, duration: 0.33)
}

/// A figure set the way the Focus site sets numbers: medium weight, tracked in,
/// ticking from one value to the next instead of jumping.
struct Figure: ViewModifier {
    let size: CGFloat
    let value: Double

    func body(content: Content) -> some View {
        content
            .font(Face.at(size, .medium))
            .tracking(-size * 0.025)
            .monospacedDigit()
            .contentTransition(.numericText(value: value))
            .animation(.paradox, value: value)
    }
}

/// Cards rise into place, one after another, the first time the screen shows.
struct Rise: ViewModifier {
    let step: Int
    /// Once per launch: coming back to a tab shouldn't replay it.
    static var played = false
    @State private var shown = Rise.played
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 16)
            .onAppear {
                guard !shown else { return }
                withAnimation(.timingCurve(0.5, 0, 0, 0.75, duration: 0.6).delay(Double(step) * 0.08)) { shown = true }
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    Rise.played = true
                }
            }
    }
}

/// The Focus lens's "hunt then lock", on the mark: it pulls in, snaps out,
/// holds a squash for a beat (hit stop), and settles. Once per launch.
struct Hunt: ViewModifier {
    static var played = false
    @State private var beat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: CGSize(width: 1, height: 1), trigger: beat) { view, scale in
                view.scaleEffect(x: scale.width, y: scale.height, anchor: .leading)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(CGSize(width: 0.94, height: 0.94), duration: 0.18)
                    LinearKeyframe(CGSize(width: 1.04, height: 0.97), duration: 0.07)
                    LinearKeyframe(CGSize(width: 1.04, height: 0.97), duration: 0.09)
                    SpringKeyframe(CGSize(width: 1, height: 1), duration: 0.4, spring: .bouncy)
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: beat)
            .onAppear {
                guard !Hunt.played, !reduceMotion else { return }
                Hunt.played = true
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    beat += 1
                }
            }
    }
}

/// The ground colour runs up under the clock and fades out just below it, so
/// what scrolls up never collides with the status bar.
struct StatusBarFade: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            VStack(spacing: 0) {
                Ink.ground
                    .frame(height: 0)
                    .background(Ink.ground.ignoresSafeArea(edges: .top))
                LinearGradient(colors: [Ink.ground, Ink.ground.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 14)
            }
            .allowsHitTesting(false)
        }
    }
}

extension View {
    func statusBarFade() -> some View { modifier(StatusBarFade()) }
    func figure(_ size: CGFloat, value: Double) -> some View { modifier(Figure(size: size, value: value)) }
    func rise(_ step: Int) -> some View { modifier(Rise(step: step)) }
    func hunt() -> some View { modifier(Hunt()) }
}
