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

/// A grid of icons; tap one and the Home Screen icon changes. Icons made in
/// the designer sit after the built-in ones.
struct AppIconPicker: View {
    @Environment(IconShelf.self) private var shelf
    @Environment(Backups.self) private var backups
    @State private var current: String? = UIApplication.shared.alternateIconName
    @State private var problem = ""
    @State private var designing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                ForEach(AppIconChoice.all) { choice in
                    Button { choose(choice) } label: {
                        tile(Image(choice.preview), title: choice.title, selected: current == choice.asset && shelf.wanted.isEmpty)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(choice.title) icon")
                    .accessibilityAddTraits(current == choice.asset ? .isSelected : [])
                }
                ForEach(shelf.icons) { icon in
                    let installed = shelf.isInstalled(icon)
                    let selected = installed ? current == icon.asset : shelf.wanted == icon.id
                    Button { choose(icon) } label: {
                        tile(Image(uiImage: shelf.picture(icon) ?? UIImage()),
                             title: installed ? "Yours" : "Next install", selected: selected)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        ShareLink(item: shelf.file(icon)) { Label("Share", systemImage: "square.and.arrow.up") }
                        Button("Delete", systemImage: "trash", role: .destructive) { delete(icon) }
                    }
                    .accessibilityLabel("Your icon, \(icon.title)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Button { designing = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Create custom app icon")
                    Spacer()
                }
                .foregroundStyle(Ink.head)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !problem.isEmpty {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(Ink.hazard)
            }
        }
        .padding(14)
        .sensoryFeedback(.selection, trigger: current)
        .sensoryFeedback(.selection, trigger: shelf.wanted)
        .fullScreenCover(isPresented: $designing) { IconDesigner() }
        .onAppear { shelf.mirror(into: backups) }
    }

    private func tile(_ image: Image, title: String, selected: Bool) -> some View {
        VStack(spacing: 6) {
            image
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(selected ? Ink.head : Ink.line, lineWidth: selected ? 2 : 1)
                }
            Text(title)
                .font(.caption2)
                .foregroundStyle(selected ? Ink.head : Ink.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func choose(_ choice: AppIconChoice) {
        shelf.wanted = ""
        wear(choice.asset)
    }

    /// An icon this build carries goes on now. One it doesn't is remembered and
    /// goes on by itself the first time a build that carries it is opened.
    private func choose(_ icon: CustomIcon) {
        if shelf.isInstalled(icon) {
            shelf.wanted = ""
            wear(icon.asset)
        } else {
            shelf.wanted = shelf.wanted == icon.id ? "" : icon.id
        }
    }

    private func delete(_ icon: CustomIcon) {
        if current == icon.asset { wear(nil) }
        shelf.remove(icon)
        shelf.mirror(into: backups)
    }

    private func wear(_ asset: String?) {
        guard current != asset, UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(asset) { error in
            Task { @MainActor in
                if let error { problem = error.localizedDescription } else { current = asset; problem = "" }
            }
        }
    }
}
