import SwiftUI
import SwiftData

struct SpotifyPage: View {
    @Query(sort: \Pin.order) private var pins: [Pin]
    @State private var adding = false
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    var body: some View {
        let moods = pins.filter { $0.isMood }
        let saved = pins.filter { !$0.isMood }
        let recent = pins
            .filter { $0.lastOpened != nil }
            .max { ($0.lastOpened ?? .distantPast) < ($1.lastOpened ?? .distantPast) }

        PageScaffold(spine: .spotify,
                     eyebrow: recent == nil ? "\(pins.count) pinned" : "Last played",
                     title: "Spotify",
                     subtitle: recent.map { "\($0.title), \($0.subtitle)" } ?? "") {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Moods")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(moods) { pin in
                            Button { play(pin) } label: { MoodTile(pin: pin) }
                                .buttonStyle(PressStyle())
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Pinned", trailing: "\(saved.count)")
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(saved.enumerated()), id: \.element.id) { index, pin in
                                if index > 0 { Hairline(inset: 66) }
                                Button { play(pin) } label: { PinRow(pin: pin) }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button("Unpin", systemImage: "pin.slash", role: .destructive) {
                                            withAnimation { context.delete(pin) }
                                        }
                                    }
                            }
                        }
                    }
                }
                TodoCard(spine: .spotify, inlineAdd: true)
            }
        } reach: {
            Button { adding = true } label: {
                Label("Pin a link", systemImage: "link")
            }
            .buttonStyle(QuietStyle())
            if let drive = moods.first {
                Button { play(drive) } label: {
                    Label("Play \(drive.title)", systemImage: "play.fill")
                }
                .buttonStyle(ProminentStyle(spine: .spotify))
            }
        }
        .sheet(isPresented: $adding) {
            PinFromLink()
                .presentationDetents([.medium, .large])
        }
    }

    private func play(_ pin: Pin) {
        pin.lastOpened = .now
        Launcher.open(pin.uri, fallback: SpotifyLink.web(pin.uri), with: openURL)
    }
}

/// Generated cover art: two related pigments and a symbol. No network needed.
struct Artwork: View {
    let hue: Double
    var symbol: String? = nil
    var corner: CGFloat = 10

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(LinearGradient(colors: [
                Color(hue: hue, saturation: 0.55, brightness: 0.88),
                Color(hue: (hue + 0.07).truncatingRemainder(dividingBy: 1), saturation: 0.85, brightness: 0.42),
            ], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
    }
}

struct MoodTile: View {
    let pin: Pin

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Image(systemName: pin.symbol)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 12)
            Text(pin.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(pin.subtitle)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background { Artwork(hue: pin.hue, corner: 16) }
        .accessibilityElement(children: .combine)
    }
}

struct PinRow: View {
    let pin: Pin

    var body: some View {
        HStack(spacing: 12) {
            Artwork(hue: pin.hue, symbol: pin.symbol)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(pin.title).lineLimit(1)
                Text("\(SpotifyLink.kind(of: pin.uri)) · \(pin.subtitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

enum SpotifyLink {
    static let kinds = ["album", "playlist", "track", "artist", "show", "episode"]

    /// Accepts `spotify:album:ID` or `https://open.spotify.com/intl-en/album/ID?si=…`.
    static func uri(from text: String) -> String? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("spotify:") { return s }
        guard let url = URL(string: s), let host = url.host, host.hasSuffix("spotify.com") else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" && !$0.hasPrefix("intl-") }
        guard parts.count >= 2, kinds.contains(parts[0]) else { return nil }
        return "spotify:\(parts[0]):\(parts[1])"
    }

    static func kind(of uri: String) -> String {
        let parts = uri.split(separator: ":")
        guard parts.count >= 2 else { return "Link" }
        return parts[1] == "search" ? "Search" : String(parts[1]).capitalized
    }

    static func web(_ uri: String) -> String {
        let parts = uri.split(separator: ":").map(String.init)
        guard parts.count >= 3 else { return "https://open.spotify.com" }
        if parts[1] == "search" {
            return "https://open.spotify.com/search/" + parts[2...].joined(separator: ":")
        }
        return "https://open.spotify.com/\(parts[1])/\(parts[2])"
    }
}

struct PinFromLink: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Pin.order) private var pins: [Pin]
    @State private var link = ""
    @State private var title = ""
    @State private var subtitle = ""

    private var uri: String? { SpotifyLink.uri(from: link) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("open.spotify.com/…", text: $link)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } footer: {
                    if !link.isEmpty && uri == nil {
                        Text("Use a Spotify album, playlist, track, artist or show link.")
                    }
                }
                Section {
                    TextField("Title", text: $title)
                    TextField("Artist or note", text: $subtitle)
                }
            }
            .navigationTitle("Pin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pin", action: save)
                        .disabled(uri == nil || title.isEmpty)
                }
            }
        }
    }

    private func save() {
        guard let uri else { return }
        let next = (pins.map(\.order).max() ?? 0) + 1
        context.insert(Pin(title: title,
                           subtitle: subtitle.isEmpty ? SpotifyLink.kind(of: uri) : subtitle,
                           uri: uri, symbol: "music.note",
                           hue: Double.random(in: 0...1), isMood: false, order: next))
        dismiss()
    }
}
