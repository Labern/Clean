import SwiftUI

/// Company › Settings › Colours. Focus's own customisation, brought over: its
/// two-tone presets and its nine hues, for this app's accent and second colour,
/// and whether the solid buttons take the accent. Default leaves everything as it was.
struct ColourSettings: View {
    @AppStorage(Palette.accentKey) private var accent = 0
    @AppStorage(Palette.secondKey) private var second = 0
    @AppStorage(Palette.buttonsKey) private var colouredButtons = false

    /// What is in use now, defaults filled in.
    private var pair: (accent: UInt32, second: UInt32) {
        (Palette.accent ?? 0xA78BFA, Palette.second ?? 0x5FD7AF)
    }

    var body: some View {
        // Reading the stored values makes the view follow them.
        let _ = (accent, second)
        VStack(alignment: .leading, spacing: 14) {
            Text("Colours")
                .font(Face.style(.subheadline))
                .foregroundStyle(Ink.body)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(Palette.presets.enumerated()), id: \.offset) { index, preset in
                        let on = pair.accent == preset.accent && pair.second == preset.second
                        Button {
                            withAnimation(.snappy) { Palette.set(accent: preset.accent, second: preset.second) }
                        } label: {
                            VStack(spacing: 6) {
                                // Focus draws its two tones as a ring and a dot; so does this.
                                ZStack {
                                    Circle().strokeBorder(Color(hex: preset.accent), lineWidth: 6)
                                    Circle().fill(Color(hex: preset.second)).frame(width: 14, height: 14)
                                }
                                .frame(width: 40, height: 40)
                                .padding(4)
                                .overlay { Circle().strokeBorder(on ? Ink.head : Color.clear, lineWidth: 2) }
                                Text(index == 0 ? "Default" : preset.name)
                                    .font(Face.style(.caption2))
                                    .foregroundStyle(on ? Ink.head : Ink.muted)
                                    .lineLimit(1)
                            }
                            .frame(minWidth: 56)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(index == 0 ? "Default colours" : preset.name)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 14)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -14)

            hues("Accent", chosen: pair.accent) { Palette.set(accent: $0, second: pair.second) }
            hues("Second", chosen: pair.second) { Palette.set(accent: pair.accent, second: $0) }

            HStack(spacing: 12) {
                Text("Buttons")
                    .font(Face.style(.subheadline))
                    .foregroundStyle(Ink.body)
                Picker("Buttons", selection: $colouredButtons) {
                    Text("White").tag(false)
                    Text("Accent").tag(true)
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(14)
        .sensoryFeedback(.selection, trigger: accent)
        .sensoryFeedback(.selection, trigger: second)
        .sensoryFeedback(.selection, trigger: colouredButtons)
    }

    /// One row of Focus's nine hues.
    private func hues(_ name: String, chosen: UInt32, pick: @escaping (UInt32) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(Face.style(.caption, .semibold))
                .foregroundStyle(Ink.muted)
            HStack(spacing: 0) {
                ForEach(Palette.hues, id: \.self) { hue in
                    Button {
                        withAnimation(.snappy) { pick(hue) }
                    } label: {
                        Circle()
                            .fill(Color(hex: hue))
                            .frame(width: 24, height: 24)
                            .padding(4)
                            .overlay { Circle().strokeBorder(chosen == hue ? Ink.head : Color.clear, lineWidth: 2) }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(name) colour \((Palette.hues.firstIndex(of: hue) ?? 0) + 1)")
                    .accessibilityAddTraits(chosen == hue ? .isSelected : [])
                }
            }
        }
    }
}
