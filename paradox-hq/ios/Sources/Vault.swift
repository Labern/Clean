import Foundation
import SwiftData

// The safety net. Everything typed into the app is copied, without being
// asked, to four places:
//
// 1. On the phone, in Application Support/Backups: a copy each time the app is
//    left, if anything changed. Every copy from the last day is kept, then one
//    a day for 60 days. This is what undoes a mistake.
// 2. In the Keychain: the newest copy, compressed, in two slots written in
//    turn, plus a third that changes slowly (it is not replaced by a store
//    under half its size for a week). iOS keeps Keychain items when an app is
//    deleted, so a fresh install finds the newest and puts everything back by
//    itself, settings and profile photo included; the older ones land in the
//    list of copies. This is what survives deleting the app.
// 3. The folder chosen in Company › Backup (`Backups`), when one is chosen.
// 4. The Mac: each install copies the Backups folder off the phone
//    (the install routine does it; see CLAUDE.md). This survives losing the phone.
//
// The phone's own iCloud or computer backup carries 1 and 2 as well, so a new
// phone set up from the old one finds everything already there.
//
// A copy is the whole store (projects, lines at every depth, notes, deadlines)
// and the app's settings (profile, layout, colours and the rest).
//
// Rules it keeps, so it can't make things worse:
// - a copy is read back and checked before it counts, and before anything older is removed;
// - the Keychain has two slots, written in turn, so a failed write never destroys the good copy;
// - an empty store is never saved over a copy that has something in it;
// - putting a copy back first saves what is there now.

/// The app's own settings, as kept in a backup.
nonisolated enum SavedSettings {
    /// Not settings: launch arguments, this phone's folder bookmark (it means
    /// nothing after a reinstall), and Apple's own keys.
    static func belongs(_ key: String) -> Bool {
        // Launch arguments, this phone's folder bookmark, and clocks that tick on
        // every launch (they would make every copy look new).
        let skipped = ["unlocked", "screen", "sampleNotes", "backup-folder", "vault-restored",
                       "lock-last-seen", "backup-last", "backup-summary"]
        return !skipped.contains(key) && !key.hasPrefix("Apple") && !key.hasPrefix("NS") && !key.hasPrefix("com.apple")
            && !key.hasPrefix("AK") && !key.hasPrefix("PK") && !key.hasPrefix("WebKit") && !key.hasPrefix("INNext")
    }

    /// The settings to keep out of everything stored: the app's own, and nothing bulky.
    static func kept(_ all: [String: Any]) -> [String: Any] {
        all.filter { belongs($0.key) && (($0.value as? Data)?.count ?? 0) <= 64_000 }
    }

    /// Every setting the app has stored, as one property list.
    static func snapshot(_ defaults: UserDefaults = .standard) -> Data? {
        guard let name = Bundle.main.bundleIdentifier, let all = defaults.persistentDomain(forName: name) else { return nil }
        let mine = kept(all)
        guard !mine.isEmpty else { return nil }
        // XML keeps keys in order, so the same settings always make the same bytes.
        return try? PropertyListSerialization.data(fromPropertyList: mine, format: .xml, options: 0)
    }

    /// Puts settings back. Ones not in the copy are left as they are.
    static func apply(_ data: Data?, to defaults: UserDefaults = .standard) {
        guard let data, let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return }
        for (key, value) in list where belongs(key) { defaults.set(value, forKey: key) }
    }
}

@MainActor @Observable final class Vault {
    nonisolated static let slots = ["vault-0", "vault-1"]
    nonisolated static let pointer = "vault-latest"
    /// A third, slower copy. It is only replaced by one at least half its size,
    /// or after a week, so a store that has suddenly lost most of its contents
    /// (a bad restore, a wipe) cannot push the last full copy out within days.
    nonisolated static let anchor = "vault-anchor"

    /// One copy on the phone.
    nonisolated struct Copy: Identifiable, Hashable, Sendable {
        var name: String
        var made: Date
        var id: String { name }
    }

    private(set) var copies: [Copy] = []
    private(set) var problem = ""
    /// Set when this launch put everything back from the Keychain after a fresh install.
    private(set) var recovered: Date? = UserDefaults.standard.object(forKey: "vault-restored") as? Date
    @ObservationIgnored private let folder: URL
    @ObservationIgnored private let usesKeychain: Bool
    @ObservationIgnored private var last: BackupFile? = nil

    /// Tests pass a folder of their own and leave the Keychain alone.
    init(folder: URL = Vault.home, usesKeychain: Bool = true) {
        self.folder = folder
        self.usesKeychain = usesKeychain
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        copies = Self.list(folder)
    }

    nonisolated static var home: URL { URL.applicationSupportDirectory.appending(path: "Backups") }

    var latest: Date? { copies.first?.made }

    // MARK: Saving

    /// Saves a copy if anything has changed since the last one. Called every time the app is left.
    @discardableResult
    func save(_ context: ModelContext, now: Date = .now) -> Bool {
        guard !Launch.unlocked else { return false }
        try? context.save()
        let taken = BackupFile.take(context, now: now, withSettings: usesKeychain)
        // Nothing to save.
        if taken.isEmpty { return false }
        // A file keeps times to the millisecond and the store is finer than that,
        // so everything is compared as it reads back from a file, never as taken.
        guard let data = try? taken.data(), let file = try? BackupFile.read(data) else {
            problem = "A backup couldn't be written on this phone."
            return false
        }
        // Nothing new since the last copy (this launch's, or the newest on disk).
        if last == nil, let newest = copies.first { last = try? open(newest) }
        if let last, last.same(as: file) {
            // Nothing new, but the Keychain must never be left without a copy.
            if usesKeychain, Self.kept() == nil { Self.keep(data) }
            return false
        }
        do {
            // 1. On the phone.
            let target = folder.appending(path: Self.name(for: now))
            try data.write(to: target, options: .atomic)
            // The file's own date is the copy's date, whatever clock wrote it.
            try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: target.path(percentEncoded: false))
            guard let back = try? BackupFile.read(Data(contentsOf: target)), back.same(as: file) else {
                try? FileManager.default.removeItem(at: target)
                throw BackupError.folderGone
            }
            // 2. In the Keychain. A failure here leaves the phone's copy standing.
            problem = !usesKeychain || Self.keep(data) ? "" : "The copy that survives deleting the app couldn't be written."
            if usesKeychain { Self.keepPhoto() }
            last = file
            // Only now, with a good new copy in hand, are older ones thinned out.
            let all = Self.list(folder)
            for name in Self.surplus(all, now: now) { try? FileManager.default.removeItem(at: folder.appending(path: name)) }
            copies = Self.list(folder)
            return true
        } catch {
            problem = "A backup couldn't be written on this phone."
            return false
        }
    }

    /// Reads a copy kept on the phone.
    func open(_ copy: Copy) throws -> BackupFile {
        try BackupFile.read(Data(contentsOf: folder.appending(path: copy.name)))
    }

    /// Puts a copy back: projects, lines, notes and deadlines. Settings stay as
    /// they are. What is there now is saved first, so it can be undone.
    func restore(_ file: BackupFile, into context: ModelContext, now: Date = .now) throws {
        last = nil
        save(context, now: now)
        try file.restore(into: context)
        Seed.personal(context)
        try? context.save()
        last = nil
        save(context, now: now.addingTimeInterval(1))
    }

    // MARK: Surviving a deleted app

    /// On a fresh install with nothing in the store, puts everything back from
    /// the Keychain. Runs before anything is seeded. True when it did.
    @discardableResult
    static func recoverIfFresh(_ context: ModelContext) -> Bool {
        guard !Launch.unlocked else { return false }
        let empty = [(try? context.fetchCount(FetchDescriptor<Project>())) ?? 0,
                     (try? context.fetchCount(FetchDescriptor<FocusItem>())) ?? 0,
                     (try? context.fetchCount(FetchDescriptor<Note>())) ?? 0,
                     (try? context.fetchCount(FetchDescriptor<Deadline>())) ?? 0].allSatisfy { $0 == 0 }
        guard empty, let file = kept(), !file.isEmpty else { return false }
        do {
            // Settings first: the starter list's "already done" mark is among them.
            try file.restore(into: context, settings: true)
            try context.save()
            UserDefaults.standard.set(true, forKey: Starter.key)
            UserDefaults.standard.set(Date.now, forKey: "vault-restored")
            restorePhoto()
            // The older Keychain copies go onto the phone as files, so if the newest
            // turns out to be missing something, the fuller one is a tap away.
            try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            for older in keptAll().dropFirst() where !older.isEmpty && !older.same(as: file) {
                let target = home.appending(path: name(for: older.made))
                guard let data = try? older.data(), (try? data.write(to: target, options: .atomic)) != nil else { continue }
                try? FileManager.default.setAttributes([.modificationDate: older.made], ofItemAtPath: target.path(percentEncoded: false))
            }
            return true
        } catch {
            return false
        }
    }

    // The profile photo is a file, so it goes too: once, and again only when it changes.
    nonisolated static let photoSlot = "vault-photo"
    nonisolated static var photoFile: URL { URL.applicationSupportDirectory.appending(path: "Profile/photo.jpg") }

    nonisolated static func keepPhoto() {
        guard let data = try? Data(contentsOf: photoFile) else { return }
        guard data.count <= 1_500_000, Keychain.data(photoSlot) != data else { return }
        Keychain.setData(data, for: photoSlot, travels: true)
    }

    nonisolated static func restorePhoto() {
        guard !FileManager.default.fileExists(atPath: photoFile.path(percentEncoded: false)),
              let data = Keychain.data(photoSlot) else { return }
        try? FileManager.default.createDirectory(at: photoFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: photoFile, options: .atomic)
    }

    /// Writes the newest copy into the Keychain slot not holding the current
    /// one, checks it, and only then points at it.
    @discardableResult
    nonisolated static func keep(_ data: Data) -> Bool {
        // Never let an empty store replace a copy that has something in it.
        if let incoming = try? BackupFile.read(data), incoming.isEmpty, let held = kept(), !held.isEmpty { return false }
        guard let packed = try? (data as NSData).compressed(using: .zlib) as Data else { return false }
        let current = Keychain.get(pointer)
        let slot = slots.first { $0 != current } ?? slots[0]
        guard Keychain.setData(packed, for: slot, travels: true), let back = Keychain.data(slot), back == packed else { return false }
        guard Keychain.set(slot, for: pointer) else { return false }
        if let incoming = try? BackupFile.read(data), replacesAnchor(incoming, held: unpack(Keychain.data(anchor)), now: incoming.made) {
            Keychain.setData(packed, for: anchor, travels: true)
        }
        return true
    }

    /// Whether a new copy should take the slow slot's place.
    nonisolated static func replacesAnchor(_ incoming: BackupFile, held: BackupFile?, now: Date) -> Bool {
        guard let held else { return !incoming.isEmpty }
        if incoming.isEmpty { return false }
        return incoming.weight * 2 >= held.weight || now.timeIntervalSince(held.made) > 7 * 86_400
    }

    private nonisolated static func unpack(_ packed: Data?) -> BackupFile? {
        guard let packed, let data = try? (packed as NSData).decompressed(using: .zlib) as Data else { return nil }
        return try? BackupFile.read(data)
    }

    /// The copies in the Keychain, newest first: the slot pointed at, the other
    /// slot, then the slow one. Any that can't be read are passed over.
    nonisolated static func keptAll() -> [BackupFile] {
        let current = Keychain.get(pointer)
        let order = [current].compactMap { $0 } + slots.filter { $0 != current } + [anchor]
        return order.compactMap { unpack(Keychain.data($0)) }
    }

    /// The newest copy in the Keychain that can be read.
    nonisolated static func kept() -> BackupFile? { keptAll().first }

    // MARK: Pure parts, tested

    /// "PARADOX 2026-11-18 015902.json"
    nonisolated static func name(for date: Date, calendar: Calendar = .current) -> String {
        let p = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "PARADOX %04d-%02d-%02d %02d%02d%02d.json",
                      p.year ?? 0, p.month ?? 0, p.day ?? 0, p.hour ?? 0, p.minute ?? 0, p.second ?? 0)
    }

    /// The copies in a folder, newest first.
    nonisolated static func list(_ folder: URL) -> [Copy] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasPrefix("PARADOX ") && $0.hasSuffix(".json") }.compactMap { name in
            let made = (try? FileManager.default.attributesOfItem(atPath: folder.appending(path: name).path(percentEncoded: false)))?[.modificationDate] as? Date
            return made.map { Copy(name: name, made: $0) }
        }
        .sorted { $0.made > $1.made }
    }

    /// The copies to remove: everything from the last day is kept (up to 48),
    /// then the newest of each day for 60 days. The newest copy is never removed.
    nonisolated static func surplus(_ copies: [Copy], now: Date, calendar: Calendar = .current) -> [String] {
        let sorted = copies.sorted { $0.made > $1.made }
        var keep = Set<String>()
        var days = Set<Date>()
        var recent = 0
        for copy in sorted {
            let age = now.timeIntervalSince(copy.made)
            if age < 86_400 {
                if recent < 48 { keep.insert(copy.name) }
                recent += 1
            } else if age < 60 * 86_400, days.insert(calendar.startOfDay(for: copy.made)).inserted {
                keep.insert(copy.name)
            }
        }
        if let newest = sorted.first { keep.insert(newest.name) }
        return sorted.map(\.name).filter { !keep.contains($0) }
    }
}

nonisolated extension BackupFile {
    /// Nothing in it worth keeping: no lines, no notes, no deadlines.
    var isEmpty: Bool { lineCount == 0 && notes.isEmpty && deadlines.isEmpty }

    /// How much is in it, for telling a full copy from a nearly empty one.
    var weight: Int { lineCount + notes.count + deadlines.count }

    /// The same contents, whenever they were taken.
    func same(as other: BackupFile) -> Bool {
        projects == other.projects && notes == other.notes && deadlines == other.deadlines && settings == other.settings
    }
}
