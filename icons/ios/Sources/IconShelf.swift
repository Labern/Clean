import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

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
/// the Home Screen straight away. It is kept here, copied into the folder the
/// Mac reads (`IconFolder`), and baked into the next build
/// (`design/bake_custom.sh`). The one marked `wanted` is put on as soon as a
/// build carrying it is opened.
@MainActor @Observable final class IconShelf {
    /// The folder, inside the chosen folder, that the Mac build reads icons from.
    nonisolated static let exportFolder = "Icons to bake"
    nonisolated static let side = 1024

    private(set) var icons: [CustomIcon] = []
    /// The id of the custom icon to wear once a build carries it.
    var wanted: String = UserDefaults.standard.string(forKey: "icon-wanted") ?? "" {
        didSet { UserDefaults.standard.set(wanted, forKey: "icon-wanted") }
    }
    /// The icon on the Home Screen now: an alternate set's name, or nil for the original.
    private(set) var wearing: String? = UIApplication.shared.alternateIconName
    var problem = ""
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
        wear(icon.asset)
    }

    /// Puts an icon this build carries on the Home Screen (nil: the original).
    func wear(_ asset: String?) {
        guard UIApplication.shared.alternateIconName != asset, UIApplication.shared.supportsAlternateIcons else {
            wearing = UIApplication.shared.alternateIconName
            return
        }
        UIApplication.shared.setAlternateIconName(asset) { error in
            Task { @MainActor in
                if let error { self.problem = error.localizedDescription } else { self.wearing = asset; self.problem = "" }
            }
        }
    }

    /// Copies every icon into the chosen folder and clears out ones deleted here,
    /// so it always holds exactly the icons on the phone. Quiet without a folder.
    func mirror(into place: IconFolder) {
        let keep = Set(icons.map { "\($0.id).png" })
        try? place.withFolder { root in
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

/// The folder (iCloud Drive, ideally) the phone copies icons into for the Mac
/// to bake. Picked once; kept as a bookmark so the app can keep writing to it.
@MainActor @Observable final class IconFolder {
    static let bookmarkKey = "icon-folder"
    private(set) var name: String = ""
    var problem: String = ""

    var isSet: Bool { UserDefaults.standard.data(forKey: Self.bookmarkKey) != nil }

    init() {
        name = (try? resolve())?.lastPathComponent ?? ""
    }

    func choose(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            name = url.lastPathComponent
            problem = ""
        } catch {
            problem = error.localizedDescription
        }
    }

    func forget() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        name = ""
    }

    private func resolve() throws -> URL {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { throw CocoaError(.fileNoSuchFile) }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }
        return url
    }

    /// Runs `body` with the chosen folder open. Throws when none is chosen or it has gone.
    func withFolder<T>(_ body: (URL) throws -> T) throws -> T {
        let folder = try resolve()
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        return try body(folder)
    }
}
