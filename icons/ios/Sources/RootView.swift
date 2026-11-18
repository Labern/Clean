import SwiftUI
import UIKit

/// Your icons. The app's own icon first, then every one you've made; tap one to
/// wear it on the Home Screen. Hold one to share its 1024px picture or delete it.
struct RootView: View {
    @Environment(IconShelf.self) private var shelf
    @Environment(IconFolder.self) private var place
    @Environment(\.theme) private var theme
    @State private var designing = Launch.screen == "designer"
    @State private var picking = false

    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 140), spacing: 18)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LazyVGrid(columns: columns, spacing: 22) {
                        Button { wear(nil) } label: {
                            tile(Image("IconPreview-main"), title: "Original",
                                 selected: shelf.wearing == nil && shelf.wanted.isEmpty)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Original icon")
                        .accessibilityAddTraits(shelf.wearing == nil ? .isSelected : [])

                        ForEach(shelf.icons) { icon in
                            let installed = shelf.isInstalled(icon)
                            let selected = installed ? shelf.wearing == icon.asset : shelf.wanted == icon.id
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

                        Button { designing = true } label: { newTile }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Design an icon")
                    }

                    if let note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(theme.muted)
                    }
                    if !shelf.problem.isEmpty || !place.problem.isEmpty {
                        Text(shelf.problem.isEmpty ? place.problem : shelf.problem)
                            .font(.footnote)
                            .foregroundStyle(theme.hazard)
                    }
                }
                .padding(20)
            }
            .background(theme.ground)
            .navigationTitle("Icons")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(place.isSet ? "Folder for the Mac: \(place.name)" : "Choose a folder for the Mac…",
                               systemImage: "folder") { picking = true }
                        if place.isSet {
                            Button("Stop copying to \(place.name)", systemImage: "folder.badge.minus") { place.forget() }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .sensoryFeedback(.selection, trigger: shelf.wearing)
        .sensoryFeedback(.selection, trigger: shelf.wanted)
        .fullScreenCover(isPresented: $designing) { IconDesigner() }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                place.choose(url)
                shelf.mirror(into: place)
            }
        }
        .onAppear { shelf.mirror(into: place) }
    }

    /// One line under the grid, only when an icon is waiting for a build.
    private var note: String? {
        guard !shelf.wanted.isEmpty else { return nil }
        return place.isSet
            ? "It goes on the first time the next build opens. The Mac bakes it from “\(IconShelf.exportFolder)” in \(place.name)."
            : "It goes on the first time the next build opens. Choose a folder for the Mac under •••."
    }

    private func tile(_ image: Image, title: String, selected: Bool) -> some View {
        VStack(spacing: 8) {
            image
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .clipShape(shape)
                .overlay { shape.strokeBorder(selected ? theme.head : theme.line, lineWidth: selected ? 2.5 : 1) }
            Text(title)
                .font(.caption)
                .foregroundStyle(selected ? theme.head : theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var newTile: some View {
        VStack(spacing: 8) {
            shape
                .fill(theme.surface)
                .aspectRatio(1, contentMode: .fit)
                .overlay { shape.strokeBorder(theme.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])) }
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(theme.body)
                }
            Text("New")
                .font(.caption)
                .foregroundStyle(theme.muted)
        }
    }

    /// The same squircle the Home Screen cuts, so a tile reads as the icon it will be.
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
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
        if shelf.wearing == icon.asset { wear(nil) }
        shelf.remove(icon)
        shelf.mirror(into: place)
    }

    private func wear(_ asset: String?) {
        if asset == nil { shelf.wanted = "" }
        shelf.wear(asset)
    }
}
