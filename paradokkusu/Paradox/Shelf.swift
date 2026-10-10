import SwiftUI
import SwiftData

/// The whole app: the home spine (the mark) and four coloured spines.
/// One spine is open; the others fold to 44pt strips on the thumb side.
struct ShelfView: View {
    @State private var open: Spine
    @State private var calendar = CalendarStore()
    @Query private var todos: [Todo]
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        // `-openSpine N` on launch opens a given spine (used for screenshots).
        let start = UserDefaults.standard.integer(forKey: "openSpine")
        _open = State(initialValue: Spine(rawValue: start) ?? .home)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Spine.allCases) { spine in
                if spine == .home {
                    LockupStrip { select(.home) }
                }
                if spine == open {
                    page(for: spine)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .transition(.opacity)
                } else if spine != .home {
                    SpineStrip(spine: spine, badge: badge(for: spine)) { select(spine) }
                }
            }
        }
        .background(Ink.ground.ignoresSafeArea())
        .environment(calendar)
        .sensoryFeedback(.selection, trigger: open)
        .simultaneousGesture(swipe)
        .task {
            Seed.run(context)
            calendar.load(day: .now)
        }
    }

    @ViewBuilder private func page(for spine: Spine) -> some View {
        switch spine {
        case .home: HomePage(open: select)
        case .tesla: TeslaPage()
        case .ring: RingPage()
        case .spotify: SpotifyPage()
        case .diary: DiaryPage()
        }
    }

    private func badge(for spine: Spine) -> Int {
        todos.filter { $0.spineRaw == spine.rawValue && !$0.done }.count
    }

    private func select(_ spine: Spine) {
        guard spine != open else { return }
        if reduceMotion {
            open = spine
        } else {
            withAnimation(.spring(duration: 0.45, bounce: 0.12)) { open = spine }
        }
    }

    /// A horizontal swipe walks along the shelf. Rows stay tap-only.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 80, abs(dx) > abs(dy) * 2 else { return }
                if let next = Spine(rawValue: open.rawValue + (dx < 0 ? 1 : -1)) {
                    select(next)
                }
            }
    }
}

// MARK: - Strips

/// Kana set one character per line, as in the vertical lockup.
struct VerticalKana: View {
    let text: String
    var size: CGFloat
    var spacing: CGFloat = 0.25

    var body: some View {
        VStack(spacing: size * spacing) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                let s = String(character)
                Text(s)
                    .font(Mark.mincho(size))
                    .rotationEffect(s == "ー" ? .degrees(90) : .zero)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// The home spine: ★★★★★ × パラドックス, stars arriving one by one on launch.
struct LockupStrip: View {
    let action: () -> Void
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                VStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { i in
                        Text("★")
                            .font(Mark.mincho(19))
                            .scaleEffect(shown ? 1 : 0.2)
                            .opacity(shown ? 1 : 0)
                            .animation(reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.55).delay(0.15 + Double(i) * 0.08), value: shown)
                    }
                }
                Text("×")
                    .font(Mark.mincho(13))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
                VerticalKana(text: "パラドックス", size: 14, spacing: 0.32)
                Spacer(minLength: 0)
            }
            .padding(.top, 18)
            .frame(width: 44)
            .frame(maxHeight: .infinity)
            .foregroundStyle(.primary)
            .background(Ink.ground.ignoresSafeArea())
            .overlay(alignment: .trailing) {
                Rectangle().fill(Ink.hairline).frame(width: 1).ignoresSafeArea()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Home")
        .onAppear { shown = true }
    }
}

/// A coloured spine: pigment name at the head, title low where the thumb is.
struct SpineStrip: View {
    let spine: Spine
    let badge: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                VerticalKana(text: spine.pigment, size: 11, spacing: 0.2)
                    .foregroundStyle(spine.onFill.opacity(0.55))
                    .padding(.top, 18)
                bands.padding(.top, 14)
                Spacer(minLength: 12)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(spine.onFill.opacity(0.7))
                        .padding(.bottom, 12)
                }
                Text(spine.title.uppercased())
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(2)
                    .fixedSize()
                    .foregroundStyle(spine.onFill)
                    .rotationEffect(.degrees(90))
                    .frame(width: 44, height: 112)
                    .padding(.bottom, 20)
            }
            .frame(width: 44)
            .frame(maxHeight: .infinity)
            .background {
                ZStack {
                    spine.fill
                    // Book-spine shading: a turned edge on each side, light across the curve.
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.22), location: 0),
                        .init(color: .white.opacity(0.10), location: 0.32),
                        .init(color: .clear, location: 0.62),
                        .init(color: .black.opacity(0.16), location: 1),
                    ], startPoint: .leading, endPoint: .trailing)
                }
                .ignoresSafeArea()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(spine.title)
        .accessibilityValue(badge > 0 ? "\(badge) to do" : "")
    }

    /// Two thin bands, like the raised cords on a bound spine.
    private var bands: some View {
        VStack(spacing: 3) {
            Rectangle().frame(height: 1)
            Rectangle().frame(height: 1)
        }
        .foregroundStyle(spine.onFill.opacity(0.28))
        .padding(.horizontal, 9)
    }
}
