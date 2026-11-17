import SwiftUI
import UIKit

/// The icons the app can wear on the Home Screen. `asset` is the alternate icon
/// set's name (nil for the main one); `preview` is an image set of the same art
/// for drawing the choice in Settings.
struct AppIconChoice: Identifiable, Hashable {
    let title: String
    let asset: String?
    let preview: String
    var id: String { asset ?? "main" }

    static let all: [AppIconChoice] = [
        AppIconChoice(title: "Classic", asset: nil, preview: "IconPreview-main"),
        AppIconChoice(title: "Light", asset: "AppIcon-Light", preview: "IconPreview-Light"),
        AppIconChoice(title: "Bold", asset: "AppIcon-Bold", preview: "IconPreview-Bold"),
        AppIconChoice(title: "Bracket", asset: "AppIcon-Bracket", preview: "IconPreview-Bracket"),
        AppIconChoice(title: "Diagonal", asset: "AppIcon-Diagonal", preview: "IconPreview-Diagonal"),
        AppIconChoice(title: "Diagonal 7", asset: "AppIcon-Diagonal7", preview: "IconPreview-Diagonal7"),
        AppIconChoice(title: "Diagonal light", asset: "AppIcon-DiagonalLight", preview: "IconPreview-DiagonalLight"),
        AppIconChoice(title: "Kana", asset: "AppIcon-Kana", preview: "IconPreview-Kana"),
        AppIconChoice(title: "Original", asset: "AppIcon-Original", preview: "IconPreview-Original"),
    ]
}

/// A grid of icons; tap one and the Home Screen icon changes.
struct AppIconPicker: View {
    @State private var current: String? = UIApplication.shared.alternateIconName
    @State private var problem = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                ForEach(AppIconChoice.all) { choice in
                    Button { choose(choice) } label: {
                        VStack(spacing: 6) {
                            Image(choice.preview)
                                .resizable()
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(current == choice.asset ? Ink.head : Ink.line,
                                                      lineWidth: current == choice.asset ? 2 : 1)
                                }
                            Text(choice.title)
                                .font(.caption2)
                                .foregroundStyle(current == choice.asset ? Ink.head : Ink.muted)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(choice.title) icon")
                    .accessibilityAddTraits(current == choice.asset ? .isSelected : [])
                }
            }
            if !problem.isEmpty {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(Ink.hazard)
            }
        }
        .padding(14)
        .sensoryFeedback(.selection, trigger: current)
    }

    private func choose(_ choice: AppIconChoice) {
        guard current != choice.asset, UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(choice.asset) { error in
            Task { @MainActor in
                if let error { problem = error.localizedDescription } else { current = choice.asset; problem = "" }
            }
        }
    }
}
