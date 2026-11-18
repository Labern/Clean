import Foundation
import SwiftData
import CryptoKit

// Keeping the phone and the canonical copy the same.
//
// The phone keeps its own store (SwiftData) and works without a signal. Each
// pass reads every row from the server, reads every record here, and compares
// both with what the two last agreed on (the base), column by column:
//
//   only the server changed a column   → the phone takes it
//   the phone changed it (or both did) → the server takes the phone's
//   a record here that the server never had → it is added there
//   a row there that the phone never had    → it is added here
//   gone from one side since they agreed    → removed from the other
//
// A pass runs when the app opens, a moment after anything is saved here, and
// the moment the server says something changed (`CloudSocket`), so a tick made
// on the site lands here in about a second. The first pass after signing in
// has no base: everything on the phone goes up, everything on the server comes
// down, and the server's own "My list" and feed projects are matched to the
// phone's rather than doubled.
//
// Two rules stop a fault from destroying data: an empty phone never empties
// the server, and an empty answer from the server never empties the phone.

/// The tables the phone keeps in step, and the columns of each that it owns.
nonisolated enum CloudTable: String, CaseIterable, Sendable {
    case projects, items, notes, deadlines

    var columns: [String] {
        switch self {
        case .projects: ["id", "remote_id", "name", "summary", "stage", "symbol", "tint", "link", "order",
                         "created", "is_personal", "remote_name"]
        case .items: ["id", "project_id", "parent_id", "remote_id", "title", "notes", "done", "completed", "order",
                      "created", "collapsed", "due", "remote_title"]
        case .notes: ["id", "project_id", "text", "created", "edited", "pinned", "done", "finished"]
        case .deadlines: ["id", "title", "who", "date", "every_months"]
        }
    }

    var dates: Set<String> {
        switch self {
        case .projects: ["created"]
        case .items: ["completed", "created", "due"]
        case .notes: ["created", "edited", "finished"]
        case .deadlines: ["date"]
        }
    }

    /// A row as the server sent it, cut down to the phone's columns, with times
    /// written the phone's way, so equal things compare equal.
    func tidy(_ row: CloudRow) -> CloudRow {
        var tidy: CloudRow = [:]
        for column in columns {
            let value = row[column] ?? .null
            if dates.contains(column), let text = value.string {
                tidy[column] = .string(CloudDate.same(text))
            } else if column == "id" || column.hasSuffix("_id"), column != "remote_id", let text = value.string {
                tidy[column] = .string(text.lowercased())
            } else {
                tidy[column] = value
            }
        }
        return tidy
    }
}

/// The comparing. Pure, so it can be tested.
nonisolated enum CloudMerge {
    struct Plan: Equatable, Sendable {
        /// Whole rows the server has never had.
        var addThere: [CloudRow] = []
        /// id → the columns the phone changed.
        var changeThere: [String: CloudRow] = [:]
        var removeThere: [String] = []
        /// Whole rows, as they should now read on the phone (new ones and changed ones).
        var putHere: [CloudRow] = []
        var removeHere: [String] = []
        /// What both sides hold once this plan has been carried out.
        var base: [String: CloudRow] = [:]

        var isEmpty: Bool {
            addThere.isEmpty && changeThere.isEmpty && removeThere.isEmpty && putHere.isEmpty && removeHere.isEmpty
        }
    }

    static func id(_ row: CloudRow) -> String { row["id"]?.string ?? "" }

    static func plan(local: [CloudRow], remote: [CloudRow], base: [String: CloudRow]) -> Plan {
        var plan = Plan()
        let here = Dictionary(local.map { (id($0), $0) }, uniquingKeysWith: { first, _ in first })
        let there = Dictionary(remote.map { (id($0), $0) }, uniquingKeysWith: { first, _ in first })

        for (key, mine) in here.sorted(by: { $0.key < $1.key }) where !key.isEmpty {
            guard let theirs = there[key] else {
                // Agreed on before and now gone from the server: it was deleted there.
                if base[key] != nil { plan.removeHere.append(key) } else {
                    plan.addThere.append(mine)
                    plan.base[key] = mine
                }
                continue
            }
            var merged = mine
            var send: CloudRow = [:]
            var took = false
            for (column, value) in mine where column != "id" {
                let other = theirs[column] ?? .null
                guard value != other else { continue }
                // With nothing agreed yet (first contact) the phone leads.
                if let agreed = base[key], agreed[column] == value {
                    merged[column] = other
                    took = true
                } else {
                    send[column] = value
                }
            }
            if took { plan.putHere.append(merged) }
            if !send.isEmpty { plan.changeThere[key] = send }
            plan.base[key] = merged
        }
        for (key, theirs) in there.sorted(by: { $0.key < $1.key }) where !key.isEmpty && here[key] == nil {
            // Agreed on before and now gone from the phone: it was deleted here.
            if base[key] != nil { plan.removeThere.append(key) } else {
                plan.putHere.append(theirs)
                plan.base[key] = theirs
            }
        }
        return plan
    }

    /// A pass that would remove most of one side is a fault, not an edit.
    static func looksWrong(removing: Int, of total: Int) -> Bool {
        removing > 10 && removing * 10 > total * 6
    }
}

/// What the phone and the server last agreed on, kept between launches.
nonisolated struct CloudState: Codable, Sendable {
    /// Whose it is. Signing in as someone else starts afresh.
    var account = ""
    /// table → id → row.
    var base: [String: [String: CloudRow]] = [:]
    /// Where the profile photo sits on the server, and the mark of the photo on the phone that it matches.
    var photoPath: String? = nil
    var photoMark: String? = nil
}

@MainActor @Observable final class CloudSync {
    /// Nil in a build that carries no cloud address: everything stays on the phone.
    let config: CloudConfig?
    private(set) var email: String? = nil
    private(set) var signedIn = false
    private(set) var busy = false
    private(set) var last: Date? = nil
    /// Why the last sync didn't finish. Empty when the two are in step.
    private(set) var problem = ""
    /// Why a sign-in was refused. Kept apart from `problem`: a sync that is still
    /// under way is not a failed sign-in.
    var refusal = ""

    @ObservationIgnored private let account: CloudAccount?
    @ObservationIgnored private let api: CloudAPI?
    @ObservationIgnored private var socket: CloudSocket? = nil
    @ObservationIgnored private var context: ModelContext? = nil
    @ObservationIgnored private weak var profile: Profile? = nil
    @ObservationIgnored private var waiting: Task<Void, Never>? = nil
    @ObservationIgnored private var running = false
    @ObservationIgnored private var again = false
    @ObservationIgnored private let file: URL

    init(config: CloudConfig? = .current, file: URL = URL.applicationSupportDirectory.appending(path: "cloud-state.json")) {
        self.config = config
        self.file = file
        if let config {
            let account = CloudAccount(config: config)
            self.account = account
            self.api = CloudAPI(config: config, account: account)
            self.signedIn = account.hasRenewal
            self.email = account.email
        } else {
            self.account = nil
            self.api = nil
        }
    }

    var available: Bool { config != nil && !Launch.unlocked }

    // MARK: Signing in, once

    func signIn(email: String, password: String, new: Bool) async -> Bool {
        guard let account else { return false }
        busy = true
        defer { busy = false }
        do {
            let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if new {
                try await account.signUp(email: address, password: password)
            } else {
                try await account.signIn(email: address, password: password)
            }
            signedIn = true
            self.email = account.email ?? address
            refusal = ""
            problem = ""
            listen()
            kick(after: 0)
            return true
        } catch {
            refusal = (error as? LocalizedError)?.errorDescription ?? "Couldn't reach the dashboard."
            return false
        }
    }

    func signOut() async {
        socket?.close()
        socket = nil
        await account?.signOut()
        signedIn = false
        email = nil
        last = nil
        try? FileManager.default.removeItem(at: file)
    }

    // MARK: When to sync

    /// Called as the app opens, with the store to keep in step.
    func start(_ context: ModelContext, profile: Profile) {
        self.context = context
        self.profile = profile
        profile.onChange = { [weak self] in self?.kick() }
        guard available, signedIn else { return }
        listen()
        kick(after: 0)
    }

    /// The app went to the background: the open line is let go. It comes back with `start`.
    func pause() {
        socket?.close()
        socket = nil
    }

    private func listen() {
        guard socket == nil, let config, let account else { return }
        let socket = CloudSocket(config: config, account: account) { [weak self] in
            Task { @MainActor in self?.kick(after: 0.15) }
        }
        self.socket = socket
        socket.open()
    }

    /// Asks for a pass shortly. Several asks close together make one pass.
    func kick(after delay: TimeInterval = 0.6) {
        guard available, signedIn else { return }
        // Only the wait can be called off. The pass itself runs on its own: a save made
        // during a pass asks for another, and must not cut short the one in flight (it did,
        // and the first sync after signing in reported "Couldn't reach the dashboard").
        waiting?.cancel()
        waiting = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            Task { [weak self] in await self?.pass() }
        }
    }

    // MARK: One pass

    private func load() -> CloudState {
        guard let data = try? Data(contentsOf: file), let state = try? JSONDecoder().decode(CloudState.self, from: data) else {
            return CloudState()
        }
        return state
    }

    func pass() async {
        guard available, signedIn, let api, let account, let context else { return }
        if running {
            again = true
            return
        }
        running = true
        busy = true
        defer {
            running = false
            busy = false
            if again {
                again = false
                kick(after: 0.2)
            }
        }
        do {
            _ = try await account.token()
            let user = await account.userID ?? ""
            var state = load()
            if state.account != user { state = CloudState(account: user) }

            // Everything on the server.
            var remote: [CloudTable: [CloudRow]] = [:]
            for table in CloudTable.allCases {
                remote[table] = try await api.rows(table.rawValue).map(table.tidy)
            }
            // Every account has at least its own list. Nothing at all means a fault: change nothing.
            guard remote[.projects]?.isEmpty == false else {
                throw CloudError(code: 0, message: "The dashboard sent nothing back, so nothing was changed.")
            }

            // Everything on the phone. (Saving only when there is something to save:
            // a save announces itself, and the announcement asks for another pass.)
            if context.hasChanges { try context.save() }
            try Self.adopt(remote, base: state.base, in: context)
            let local = try Self.rows(context)
            // An empty phone never empties the server: it starts afresh and takes everything down.
            if local.values.allSatisfy(\.isEmpty) { state.base = [:] }

            var plans: [CloudTable: CloudMerge.Plan] = [:]
            for table in CloudTable.allCases {
                let plan = CloudMerge.plan(local: local[table] ?? [], remote: remote[table] ?? [],
                                           base: state.base[table.rawValue] ?? [:])
                if CloudMerge.looksWrong(removing: plan.removeHere.count, of: local[table]?.count ?? 0)
                    || CloudMerge.looksWrong(removing: plan.removeThere.count, of: remote[table]?.count ?? 0) {
                    throw CloudError(code: 0, message: "Syncing would have removed most of your \(table.rawValue), so it stopped. Nothing was changed.")
                }
                plans[table] = plan
            }

            // The server first: if anything is refused, nothing here has changed and the next pass tries again.
            for table in [CloudTable.projects, .items, .notes, .deadlines] {
                guard let plan = plans[table] else { continue }
                try await api.put(plan.addThere, in: table.rawValue)
                for (id, columns) in plan.changeThere.sorted(by: { $0.key < $1.key }) {
                    try await api.change(id, to: columns, in: table.rawValue)
                }
            }
            for table in [CloudTable.notes, .items, .deadlines, .projects] {
                guard let plan = plans[table] else { continue }
                try await api.remove(plan.removeThere, from: table.rawValue)
            }

            // Then the phone.
            if plans.values.contains(where: { !$0.putHere.isEmpty || !$0.removeHere.isEmpty }) {
                try Self.apply(plans, to: context)
                try context.save()
            }
            for table in CloudTable.allCases { state.base[table.rawValue] = plans[table]?.base ?? [:] }
            try JSONEncoder().encode(state).write(to: file, options: .atomic)

            // Who he is: name, roles, the photo and how it sits in its circle.
            try await syncProfile(api: api, user: user.lowercased(), state: &state)
            try JSONEncoder().encode(state).write(to: file, options: .atomic)
            last = .now
            problem = ""
        } catch {
            // Called off part-way (the app went to the background): not a fault, the next pass does it.
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            if (error as? CloudError)?.code == 401 {
                signedIn = account.hasRenewal
            }
            problem = (error as? CloudError)?.message ?? "No connection to the dashboard. It will sync when there is one."
        }
    }

    // MARK: The profile and its photo

    static let profileColumns = ["id", "name", "worn", "roles", "framing", "photo"]

    /// A short, stable mark of a photo's bytes, to tell whether it has changed.
    nonisolated static func mark(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// How the photo sits in its circle, to four places, so the same framing always compares equal.
    nonisolated static func framing(_ framing: Framing) -> JSONValue {
        func round(_ value: Double) -> JSONValue { .number((value * 10_000).rounded() / 10_000) }
        return .object(["x": round(framing.x), "y": round(framing.y), "zoom": round(framing.zoom)])
    }

    nonisolated static func framing(_ value: JSONValue?) -> Framing? {
        guard case .object(let parts)? = value, let x = parts["x"]?.number, let y = parts["y"]?.number,
              let zoom = parts["zoom"]?.number else { return nil }
        return Framing(x: x, y: y, zoom: zoom)
    }

    nonisolated static func strings(_ value: JSONValue?) -> [String] {
        guard case .array(let values)? = value else { return [] }
        return values.compactMap(\.string)
    }

    /// The profile row as the phone would write it. `photo` is the server's path when the
    /// phone's photo is the one already there, and a mark of its own when it has changed.
    static func profileRow(id: String, name: String, worn: [String], added: [String], framing: Framing,
                           photoMark: String?, state: CloudState) -> CloudRow {
        let photo: JSONValue
        if let photoMark {
            photo = photoMark == state.photoMark && state.photoPath != nil ? .string(state.photoPath ?? "") : .string("local:\(photoMark)")
        } else {
            photo = .null
        }
        let wearing = worn.map { JSONValue.string($0) }
        let extra = added.map { JSONValue.string($0) }
        return ["id": .string(id), "name": .string(name), "worn": .array(wearing),
                "roles": .array(extra), "framing": Self.framing(framing), "photo": photo]
    }

    private func syncProfile(api: CloudAPI, user: String, state: inout CloudState) async throws {
        guard let profile else { return }
        let table = "profiles"
        guard let sent = try await api.rows(table).first(where: { $0["id"]?.string?.lowercased() == user }) else { return }
        var remote: CloudRow = [:]
        for column in Self.profileColumns { remote[column] = sent[column] ?? .null }
        remote["id"] = .string(user)
        if let there = Self.framing(remote["framing"]) { remote["framing"] = Self.framing(there) }

        let bytes = profile.photoBytes
        let mark = bytes.map(Self.mark)
        let local = Self.profileRow(id: user, name: profile.name, worn: profile.worn, added: profile.added,
                                    framing: profile.framing, photoMark: mark, state: state)
        let plan = CloudMerge.plan(local: [local], remote: [remote], base: state.base[table] ?? [:])
        var agreed = plan.base[user] ?? local

        if var send = plan.changeThere[user] {
            if let marker = send["photo"]?.string, marker.hasPrefix("local:"), let bytes, let mark {
                // The phone's photo is new to the server: it goes up first, then the row points at it.
                let path = "\(user)/photo-\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
                try await api.upload(Profile.light(bytes), to: path, in: "profile")
                send["photo"] = .string(path)
                agreed["photo"] = .string(path)
                state.photoPath = path
                state.photoMark = mark
            } else if send["photo"] == .some(.null) {
                state.photoPath = nil
                state.photoMark = nil
            }
            try await api.change(user, to: send, in: table)
        }

        if let merged = plan.putHere.first {
            profile.take(name: merged["name"]?.string ?? profile.name, worn: Self.strings(merged["worn"]),
                         added: Self.strings(merged["roles"]), framing: Self.framing(merged["framing"]) ?? profile.framing)
            if merged["photo"] != local["photo"] {
                // Another device chose a photo: it comes down as it is.
                if let path = merged["photo"]?.string, !path.hasPrefix("local:") {
                    let data = try await api.download(path, from: "profile")
                    profile.takePhoto(data)
                    state.photoPath = path
                    state.photoMark = Self.mark(data)
                } else if merged["photo"] == .some(.null) {
                    profile.takePhoto(nil)
                    state.photoPath = nil
                    state.photoMark = nil
                }
            }
        }
        state.base[table] = [user: agreed]
    }

    // MARK: The phone's records as rows

    private static func text(_ value: String) -> JSONValue { .string(value) }
    private static func time(_ value: Date?) -> JSONValue { value.map { .string(CloudDate.write($0)) } ?? .null }
    private static func whole(_ value: Int) -> JSONValue { .number(Double(value)) }
    private static func link(_ value: String?) -> JSONValue { (value?.isEmpty == false) ? .string(value!) : .null }

    private static func newID() -> String { UUID().uuidString.lowercased() }

    /// The first time the phone meets an account, the server already holds a "My list"
    /// and may hold projects and lines from the same feed. Those are the phone's own
    /// records under the server's ids: take the ids, so nothing is doubled.
    /// Every other record without an id is given one.
    static func adopt(_ remote: [CloudTable: [CloudRow]], base: [String: [String: CloudRow]], in context: ModelContext) throws {
        let projects = try context.fetch(FetchDescriptor<Project>())
        let items = try context.fetch(FetchDescriptor<FocusItem>())
        let notes = try context.fetch(FetchDescriptor<Note>())
        let deadlines = try context.fetch(FetchDescriptor<Deadline>())

        let known = Set(projects.map(\.uid) + items.map(\.uid))
        for row in remote[.projects] ?? [] {
            let id = CloudMerge.id(row)
            guard !known.contains(id), base[CloudTable.projects.rawValue]?[id] == nil else { continue }
            let feed = row["remote_id"]?.string ?? ""
            let personal = row["is_personal"]?.bool == true
            let match = projects.first { mine in
                guard base[CloudTable.projects.rawValue]?[mine.uid] == nil else { return false }
                return personal ? mine.isPersonal : (!feed.isEmpty && mine.remoteID == feed && !mine.isPersonal)
            }
            match?.uid = id
        }
        for row in remote[.items] ?? [] {
            let id = CloudMerge.id(row)
            let feed = row["remote_id"]?.string ?? ""
            guard !feed.isEmpty, !known.contains(id), base[CloudTable.items.rawValue]?[id] == nil else { continue }
            items.first { $0.remoteID == feed && base[CloudTable.items.rawValue]?[$0.uid] == nil }?.uid = id
        }
        for project in projects where project.uid.isEmpty { project.uid = newID() }
        for item in items where item.uid.isEmpty { item.uid = newID() }
        for note in notes where note.uid.isEmpty { note.uid = newID() }
        for deadline in deadlines where deadline.uid.isEmpty { deadline.uid = newID() }
        if context.hasChanges { try context.save() }
    }

    static func row(_ project: Project) -> CloudRow {
        ["id": text(project.uid), "remote_id": text(project.remoteID), "name": text(project.name),
         "summary": text(project.summary), "stage": text(project.stage), "symbol": text(project.symbol),
         "tint": whole(project.tint), "link": text(project.link), "order": whole(project.order),
         "created": time(project.created), "is_personal": .bool(project.isPersonal), "remote_name": text(project.remoteName)]
    }

    /// The project a line belongs to, however deep it sits.
    static func home(of item: FocusItem) -> Project? {
        var line = item
        var steps = 0
        while let above = line.parent, steps < 64 {
            line = above
            steps += 1
        }
        return line.project
    }

    static func row(_ item: FocusItem) -> CloudRow? {
        guard let project = home(of: item), !project.uid.isEmpty else { return nil }
        return ["id": text(item.uid), "project_id": text(project.uid), "parent_id": link(item.parent?.uid),
                "remote_id": text(item.remoteID), "title": text(item.title), "notes": text(item.notes),
                "done": .bool(item.done), "completed": time(item.completed), "order": whole(item.order),
                "created": time(item.created), "collapsed": .bool(item.collapsed), "due": time(item.due),
                "remote_title": text(item.remoteTitle)]
    }

    static func row(_ note: Note) -> CloudRow {
        ["id": text(note.uid), "project_id": link(note.project?.uid), "text": text(note.text),
         "created": time(note.created), "edited": time(note.edited), "pinned": .bool(note.pinned),
         "done": .bool(note.done), "finished": time(note.finished)]
    }

    static func row(_ deadline: Deadline) -> CloudRow {
        ["id": text(deadline.uid), "title": text(deadline.title), "who": text(deadline.who),
         "date": time(deadline.date), "every_months": whole(deadline.everyMonths)]
    }

    static func rows(_ context: ModelContext) throws -> [CloudTable: [CloudRow]] {
        [.projects: try context.fetch(FetchDescriptor<Project>()).filter { !$0.uid.isEmpty }.map(row),
         .items: try context.fetch(FetchDescriptor<FocusItem>()).filter { !$0.uid.isEmpty }.compactMap(row),
         .notes: try context.fetch(FetchDescriptor<Note>()).filter { !$0.uid.isEmpty }.map(row),
         .deadlines: try context.fetch(FetchDescriptor<Deadline>()).filter { !$0.uid.isEmpty }.map(row)]
    }

    // MARK: The server's changes, written into the phone

    private static func date(_ value: JSONValue?) -> Date? { value?.string.flatMap(CloudDate.read) }
    private static func int(_ value: JSONValue?) -> Int? { value?.number.map { Int($0) } }

    static func apply(_ plans: [CloudTable: CloudMerge.Plan], to context: ModelContext) throws {
        var projects = Dictionary(try context.fetch(FetchDescriptor<Project>()).map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        var items = Dictionary(try context.fetch(FetchDescriptor<FocusItem>()).map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        var notes = Dictionary(try context.fetch(FetchDescriptor<Note>()).map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        var deadlines = Dictionary(try context.fetch(FetchDescriptor<Deadline>()).map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })

        for row in plans[.projects]?.putHere ?? [] {
            let id = CloudMerge.id(row)
            let project: Project
            if let have = projects[id] {
                project = have
            } else {
                project = Project(name: "")
                project.uid = id
                context.insert(project)
                projects[id] = project
            }
            project.remoteID = row["remote_id"]?.string ?? ""
            project.name = row["name"]?.string ?? ""
            project.summary = row["summary"]?.string ?? ""
            project.stage = row["stage"]?.string ?? ""
            project.symbol = row["symbol"]?.string ?? project.symbol
            project.tint = int(row["tint"]) ?? project.tint
            project.link = row["link"]?.string ?? ""
            project.order = int(row["order"]) ?? 0
            project.created = date(row["created"]) ?? project.created
            project.isPersonal = row["is_personal"]?.bool ?? false
            project.remoteName = row["remote_name"]?.string ?? ""
        }

        // Lines: every new one is made first, so a line can be put under one that arrived with it.
        let lines = plans[.items]?.putHere ?? []
        for row in lines where items[CloudMerge.id(row)] == nil {
            let made = FocusItem(title: "")
            made.uid = CloudMerge.id(row)
            context.insert(made)
            items[made.uid] = made
        }
        for row in lines {
            guard let item = items[CloudMerge.id(row)] else { continue }
            item.remoteID = row["remote_id"]?.string ?? ""
            item.title = row["title"]?.string ?? ""
            item.notes = row["notes"]?.string ?? ""
            item.done = row["done"]?.bool ?? false
            item.completed = date(row["completed"])
            item.order = int(row["order"]) ?? 0
            item.created = date(row["created"]) ?? item.created
            item.collapsed = row["collapsed"]?.bool ?? false
            item.due = date(row["due"])
            item.remoteTitle = row["remote_title"]?.string ?? ""
            // A top line belongs to its project; a line under another belongs to that line.
            if let above = row["parent_id"]?.string, let parent = items[above], parent !== item {
                item.parent = parent
                item.project = nil
            } else {
                item.parent = nil
                item.project = (row["project_id"]?.string).flatMap { projects[$0] }
            }
        }

        for row in plans[.notes]?.putHere ?? [] {
            let id = CloudMerge.id(row)
            let note: Note
            if let have = notes[id] {
                note = have
            } else {
                note = Note()
                note.uid = id
                context.insert(note)
                notes[id] = note
            }
            note.text = row["text"]?.string ?? ""
            note.created = date(row["created"]) ?? note.created
            note.edited = date(row["edited"]) ?? note.edited
            note.pinned = row["pinned"]?.bool ?? false
            note.done = row["done"]?.bool ?? false
            note.finished = date(row["finished"])
            note.project = (row["project_id"]?.string).flatMap { projects[$0] }
        }

        for row in plans[.deadlines]?.putHere ?? [] {
            let id = CloudMerge.id(row)
            let deadline: Deadline
            if let have = deadlines[id] {
                deadline = have
            } else {
                deadline = Deadline(title: "")
                deadline.uid = id
                context.insert(deadline)
                deadlines[id] = deadline
            }
            deadline.title = row["title"]?.string ?? ""
            deadline.who = row["who"]?.string ?? ""
            deadline.date = date(row["date"]) ?? deadline.date
            deadline.everyMonths = int(row["every_months"]) ?? 0
        }

        // What was deleted elsewhere goes here too. Feed ids are remembered, so the feed doesn't bring them back.
        for id in plans[.notes]?.removeHere ?? [] {
            if let note = notes[id] { context.delete(note) }
        }
        for id in plans[.deadlines]?.removeHere ?? [] {
            if let deadline = deadlines[id] { context.delete(deadline) }
        }
        let goneLines = Set(plans[.items]?.removeHere ?? [])
        for id in goneLines {
            // A line under another line that is going too goes with it.
            guard let item = items[id], !(item.parent.map { goneLines.contains($0.uid) } ?? false) else { continue }
            Tombstones.bury(item.family.map(\.remoteID))
            context.delete(item)
        }
        for id in plans[.projects]?.removeHere ?? [] {
            guard let project = projects[id], !project.isPersonal else { continue }
            Tombstones.bury([project.remoteID] + project.items.flatMap(\.family).map(\.remoteID))
            context.delete(project)
        }
    }
}
