import Foundation
import SwiftData
import Observation

// A copy of everything typed on the phone (projects and their lines at every
// depth, notes, deadlines), written as one JSON file into a folder you pick,
// normally in iCloud Drive, so it outlives the app being deleted.
//
// This is the safety net for builds signed without a paid Apple Developer
// account. With one, the store itself syncs through iCloud (see CLAUDE.md,
// "iCloud"), and this stays on as a second copy.

/// The whole notebook as plain values.
nonisolated struct BackupFile: Codable, Equatable {
    static let currentVersion = 1

    var version = BackupFile.currentVersion
    var made: Date
    var projects: [ProjectCopy]
    var notes: [NoteCopy]
    var deadlines: [DeadlineCopy]

    struct ProjectCopy: Codable, Equatable {
        var remoteID: String
        var name: String
        var summary: String
        var stage: String
        var symbol: String
        var tint: Int
        var link: String
        var order: Int
        var created: Date
        var isPersonal: Bool
        var items: [ItemCopy]
    }

    struct ItemCopy: Codable, Equatable {
        var remoteID: String
        var title: String
        var notes: String
        var done: Bool
        var completed: Date?
        var order: Int
        var created: Date
        var collapsed: Bool
        var due: Date?
        var children: [ItemCopy]
    }

    struct NoteCopy: Codable, Equatable {
        var text: String
        var created: Date
        var edited: Date
        var pinned: Bool
        /// Which project it was filed under, by its place in `projects`.
        var project: Int?
    }

    struct DeadlineCopy: Codable, Equatable {
        var title: String
        var who: String
        var date: Date
        var everyMonths: Int
    }

    var lineCount: Int {
        func count(_ items: [ItemCopy]) -> Int { items.reduce(0) { $0 + 1 + count($1.children) } }
        return projects.reduce(0) { $0 + count($1.items) }
    }

    /// "4 projects, 37 lines, 12 notes"
    var summary: String {
        func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        return [plural(projects.count, "project"), plural(lineCount, "line"), plural(notes.count, "note")]
            .joined(separator: ", ")
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, to in
            var single = to.singleValueContainer()
            try single.encode(date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true)
                .timeZone(separator: .omitted)))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { from in
            let text = try from.singleValueContainer().decode(String.self)
            let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            if let date = try? fractional.parse(text) { return date }
            if let date = try? Date.ISO8601FormatStyle().parse(text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: from.codingPath, debugDescription: "Not a date: \(text)"))
        }
        return decoder
    }

    func data() throws -> Data { try Self.encoder().encode(self) }

    static func read(_ data: Data) throws -> BackupFile {
        let snapshot = try decoder().decode(BackupFile.self, from: data)
        guard snapshot.version <= currentVersion else { throw BackupError.tooNew }
        return snapshot
    }
}

enum BackupError: LocalizedError {
    case tooNew
    case noFolder
    case folderGone

    var errorDescription: String? {
        switch self {
        case .tooNew: "This backup was made by a newer version of PARADOX."
        case .noFolder: "No backup folder chosen."
        case .folderGone: "The backup folder can't be reached. Choose it again."
        }
    }
}

extension BackupFile {
    /// Reads everything out of the store.
    @MainActor
    static func take(_ context: ModelContext, now: Date = .now) -> BackupFile {
        let projects = ((try? context.fetch(FetchDescriptor<Project>())) ?? [])
            .sorted { ($0.order, $0.created) < ($1.order, $1.created) }
        let notes = ((try? context.fetch(FetchDescriptor<Note>())) ?? []).sorted { $0.created < $1.created }
        let deadlines = ((try? context.fetch(FetchDescriptor<Deadline>())) ?? []).sorted { $0.date < $1.date }

        func copy(_ item: FocusItem) -> ItemCopy {
            ItemCopy(remoteID: item.remoteID, title: item.title, notes: item.notes, done: item.done,
                     completed: item.completed, order: item.order, created: item.created,
                     collapsed: item.collapsed, due: item.due, children: item.sortedChildren.map(copy))
        }

        return BackupFile(
            made: now,
            projects: projects.map { project in
                ProjectCopy(remoteID: project.remoteID, name: project.name, summary: project.summary,
                            stage: project.stage, symbol: project.symbol, tint: project.tint, link: project.link,
                            order: project.order, created: project.created, isPersonal: project.isPersonal,
                            items: project.sortedItems.map(copy))
            },
            notes: notes.map { note in
                NoteCopy(text: note.text, created: note.created, edited: note.edited, pinned: note.pinned,
                         project: note.project.flatMap { owner in projects.firstIndex { $0 === owner } })
            },
            deadlines: deadlines.map {
                DeadlineCopy(title: $0.title, who: $0.who, date: $0.date, everyMonths: $0.everyMonths)
            })
    }

    /// Replaces everything in the store with this backup.
    @MainActor
    func restore(into context: ModelContext) throws {
        for project in try context.fetch(FetchDescriptor<Project>()) { context.delete(project) }
        for item in try context.fetch(FetchDescriptor<FocusItem>()) { context.delete(item) }
        for note in try context.fetch(FetchDescriptor<Note>()) { context.delete(note) }
        for deadline in try context.fetch(FetchDescriptor<Deadline>()) { context.delete(deadline) }

        func make(_ copy: ItemCopy) -> FocusItem {
            let item = FocusItem(title: copy.title, notes: copy.notes, done: copy.done, order: copy.order)
            context.insert(item)
            item.remoteID = copy.remoteID
            item.completed = copy.completed
            item.created = copy.created
            item.collapsed = copy.collapsed
            item.due = copy.due
            for child in copy.children { make(child).parent = item }
            return item
        }

        var made: [Project] = []
        for copy in projects {
            let project = Project(name: copy.name, summary: copy.summary, stage: copy.stage, symbol: copy.symbol,
                                  tint: copy.tint, link: copy.link, order: copy.order)
            context.insert(project)
            project.remoteID = copy.remoteID
            project.created = copy.created
            project.isPersonal = copy.isPersonal
            for line in copy.items { make(line).project = project }
            made.append(project)
        }
        for copy in notes {
            let note = Note(text: copy.text, created: copy.created)
            context.insert(note)
            note.edited = copy.edited
            note.pinned = copy.pinned
            if let index = copy.project, made.indices.contains(index) { note.project = made[index] }
        }
        for copy in deadlines {
            context.insert(Deadline(title: copy.title, who: copy.who, date: copy.date, everyMonths: copy.everyMonths))
        }
        try context.save()
    }
}

/// Where backups go, and the writing of them.
@MainActor @Observable final class Backups {
    static let bookmarkKey = "backup-folder"
    /// How many dated backups to keep in the folder.
    static let keep = 30

    private(set) var folderName: String = ""
    private(set) var last: Date? = UserDefaults.standard.object(forKey: "backup-last") as? Date {
        didSet { UserDefaults.standard.set(last, forKey: "backup-last") }
    }
    private(set) var lastSummary: String = UserDefaults.standard.string(forKey: "backup-summary") ?? "" {
        didSet { UserDefaults.standard.set(lastSummary, forKey: "backup-summary") }
    }
    var problem: String = ""

    var isSet: Bool { UserDefaults.standard.data(forKey: Self.bookmarkKey) != nil }

    init() {
        folderName = (try? resolveFolder())?.lastPathComponent ?? ""
    }

    /// Remembers a folder the person picked, so the app can keep writing to it.
    func choose(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            folderName = url.lastPathComponent
            problem = ""
        } catch {
            problem = error.localizedDescription
        }
    }

    func forget() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        folderName = ""
    }

    private func resolveFolder() throws -> URL {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { throw BackupError.noFolder }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }
        return url
    }

    /// Runs `body` with the chosen folder open. Throws when none is chosen or it has gone.
    func withFolder<T>(_ body: (URL) throws -> T) throws -> T {
        let folder = try resolveFolder()
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        return try body(folder)
    }

    /// "PARADOX 2026-11-17.json": one file a day, so the folder holds a month of history.
    nonisolated static func fileName(for date: Date, label: String = "", calendar: Calendar = .current) -> String {
        let day = date.formatted(.iso8601.year().month().day().timeZone(separator: .omitted))
        let stamp = label.isEmpty ? day : "\(day) \(label)"
        return "PARADOX \(stamp).json"
    }

    /// Of the dated backups in a folder, the ones beyond the newest `keep` to remove.
    nonisolated static func surplus(_ names: [String], keep: Int) -> [String] {
        let dated = names.filter { $0.hasPrefix("PARADOX ") && $0.hasSuffix(".json") && !$0.contains("before restore") }
            .sorted(by: >)
        return Array(dated.dropFirst(keep))
    }

    /// Writes a backup now. Quiet when no folder is chosen.
    @discardableResult
    func write(_ context: ModelContext, label: String = "", now: Date = .now) -> Bool {
        guard isSet else { return false }
        do {
            let folder = try resolveFolder()
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            let snapshot = BackupFile.take(context, now: now)
            let data = try snapshot.data()
            let target = folder.appending(path: Self.fileName(for: now, label: label))

            var failure: Error? = nil
            var coordinated: NSError? = nil
            NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinated) { url in
                do { try data.write(to: url, options: .atomic) } catch { failure = error }
            }
            if let error = failure ?? coordinated { throw error }

            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
            for name in Self.surplus(names, keep: Self.keep) {
                try? FileManager.default.removeItem(at: folder.appending(path: name))
            }
            last = now
            lastSummary = snapshot.summary
            problem = ""
            return true
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? BackupError.folderGone.localizedDescription
            return false
        }
    }

    /// Reads a backup file the person picked.
    func open(_ url: URL) throws -> BackupFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var data: Data? = nil
        var failure: Error? = nil
        var coordinated: NSError? = nil
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinated) { url in
            do { data = try Data(contentsOf: url) } catch { failure = error }
        }
        if let error = failure ?? coordinated { throw error }
        return try BackupFile.read(data ?? Data())
    }

    /// Puts a backup back. What's on the phone now is saved first, so a restore can be undone.
    func restore(_ snapshot: BackupFile, into context: ModelContext) throws {
        write(context, label: "before restore")
        try snapshot.restore(into: context)
        Seed.personal(context)
        write(context)
    }
}
