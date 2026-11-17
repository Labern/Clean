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
            .foregroundStyle(.white)
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
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Ink.muted)
                        .monospacedDigit()
                }
            }
            Rectangle()
                .fill(.white)
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
            Text(title)
                .font(.footnote.weight(.semibold))
            Spacer(minLength: 8)
            if !trailing.isEmpty {
                Text(trailing)
                    .font(.footnote)
                    .monospacedDigit()
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
            .font(.caption.weight(.semibold))
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

/// A row with a title, a line under it, and something on the right.
struct InfoRow<Trailing: View>: View {
    var symbol: String = ""
    var symbolColor: Color = Ink.muted
    let title: String
    var detail: String = ""
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            if !symbol.isEmpty {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
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
                        .font(.caption)
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
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Ink.body)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Ink.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The round tick used on every Focus line.
struct Tick: View {
    let done: Bool
    var color: Color = .white
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(done ? Color.clear : Ink.idle, lineWidth: 1.5)
            if done {
                Circle().fill(color)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(.black)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// A thin bar of how much of a project is done.
struct Meter: View {
    let done: Int
    let total: Int
    var color: Color = .white

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
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Ink.body)
                    Text("Connect Stripe to see your own.")
                        .font(.caption)
                        .foregroundStyle(Ink.muted)
                }
                Spacer(minLength: 8)
                Text("Connect")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 34)
                    .background(.white, in: Capsule())
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
