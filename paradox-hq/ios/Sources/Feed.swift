import Foundation
import SwiftData
import Observation

// The feed is one JSON file of projects and their Focus lines. Any Claude
// session can edit it; the app pulls it and merges. The copy in the bundle
// seeds the first launch, so both travel the same path.
//
// Merging only ever adds: new projects, new lines, ticks. It never unticks
// a line, never deletes one, and never touches projects made on the phone.

nonisolated struct Feed: Decodable, Sendable {
    var projects: [FeedProject]
}

nonisolated struct FeedProject: Decodable, Sendable {
    var id: String
    var name: String
    var summary: String?
    var stage: String?
    var symbol: String?
    var tint: String?
    var link: String?
    var items: [FeedItem]?
}

nonisolated struct FeedItem: Decodable, Sendable {
    var id: String
    var title: String
    var notes: String?
    var done: Bool?
    var children: [FeedItem]?
}

nonisolated struct FeedOutcome: Equatable, Sendable {
    var projects = 0
    var items = 0
    var ticked = 0

    var summary: String {
        var parts: [String] = []
        if projects > 0 { parts.append(projects == 1 ? "1 new project" : "\(projects) new projects") }
        if items > 0 { parts.append(items == 1 ? "1 new line" : "\(items) new lines") }
        if ticked > 0 { parts.append("\(ticked) ticked") }
        return parts.isEmpty ? "Nothing new" : parts.joined(separator: ", ")
    }
}

nonisolated struct FeedError: Error, LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

extension Feed {
    nonisolated static func decode(_ data: Data) throws -> Feed {
        try JSONDecoder().decode(Feed.self, from: data)
    }

    nonisolated static func bundled() -> Feed? {
        guard let url = Bundle.main.url(forResource: "feed", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }

    nonisolated static func hex(_ text: String?) -> Int? {
        guard let text else { return nil }
        return Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "# ")), radix: 16)
    }

    nonisolated static func fetch(_ address: String, token: String?) async throws -> Feed {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https" else {
            throw FeedError(message: "The address needs to start with https://")
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        // GitHub's contents API returns the raw file when asked this way, which is
        // how a file in a private repo is read with a token.
        request.setValue("application/vnd.github.raw+json, application/json;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw FeedError(message: "The feed returned \(code).") }
        do {
            return try decode(data)
        } catch {
            throw FeedError(message: "The feed isn't in the expected format.")
        }
    }

    @MainActor @discardableResult
    func apply(to context: ModelContext, now: Date = .now) -> FeedOutcome {
        var outcome = FeedOutcome()
        let existing = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        var known: [String: Project] = [:]
        for project in existing where !project.remoteID.isEmpty { known[project.remoteID] = project }
        var order = (existing.map(\.order).max() ?? -1) + 1

        for incoming in projects {
            let project: Project
            if let found = known[incoming.id] {
                project = found
                project.name = incoming.name
                if let summary = incoming.summary { project.summary = summary }
                if let stage = incoming.stage { project.stage = stage }
                if let link = incoming.link { project.link = link }
            } else {
                project = Project(name: incoming.name,
                                  summary: incoming.summary ?? "",
                                  stage: incoming.stage ?? "",
                                  symbol: incoming.symbol ?? "square.stack.3d.up",
                                  tint: Feed.hex(incoming.tint) ?? 0xA78BFA,
                                  link: incoming.link ?? "",
                                  order: order)
                project.remoteID = incoming.id
                context.insert(project)
                known[incoming.id] = project
                order += 1
                outcome.projects += 1
            }
            Feed.merge(incoming.items ?? [], siblings: project.items, project: project, parent: nil,
                       context: context, now: now, outcome: &outcome)
        }
        try? context.save()
        return outcome
    }

    @MainActor
    private static func merge(_ incoming: [FeedItem], siblings: [FocusItem], project: Project?, parent: FocusItem?,
                              context: ModelContext, now: Date, outcome: inout FeedOutcome) {
        var known: [String: FocusItem] = [:]
        for item in siblings where !item.remoteID.isEmpty { known[item.remoteID] = item }
        var order = (siblings.map(\.order).max() ?? -1) + 1

        for line in incoming {
            let item: FocusItem
            if let found = known[line.id] {
                item = found
                if item.title != line.title { item.title = line.title }
                if item.notes.isEmpty, let notes = line.notes { item.notes = notes }
                if line.done == true, !item.done {
                    item.done = true
                    item.completed = now
                    outcome.ticked += 1
                }
            } else {
                item = FocusItem(title: line.title, notes: line.notes ?? "", done: line.done ?? false, order: order)
                item.remoteID = line.id
                context.insert(item)
                if let parent { item.parent = parent } else { item.project = project }
                known[line.id] = item
                order += 1
                outcome.items += 1
            }
            merge(line.children ?? [], siblings: item.children, project: nil, parent: item,
                  context: context, now: now, outcome: &outcome)
        }
    }
}

enum Seed {
    /// First launch: the bundled feed becomes the starting projects.
    static func run(_ context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Project>())) ?? 0
        if existing == 0, let feed = Feed.bundled() {
            feed.apply(to: context)
        }
        personal(context)
    }

    /// Labern's own list: made once, kept first.
    @discardableResult
    static func personal(_ context: ModelContext) -> Project {
        let all = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        if let mine = all.first(where: \.isPersonal) { return mine }
        let mine = Project(name: "Me", summary: "Your own list.", symbol: "person",
                           tint: 0xFFFFFF, order: (all.map(\.order).min() ?? 0) - 1)
        mine.isPersonal = true
        context.insert(mine)
        try? context.save()
        return mine
    }

    /// A few notes for the cloud build to photograph. Only ever runs when asked
    /// for by launch argument, and only into an empty notebook.
    static func sampleNotes(_ context: ModelContext, now: Date = .now) {
        guard UserDefaults.standard.bool(forKey: "sampleNotes"),
              ((try? context.fetchCount(FetchDescriptor<Note>())) ?? 0) == 0 else { return }
        let texts = [
            "Focus pricing\nAnnual at £45 reads better next to £5 a month. Keep £99 as the anchor.",
            "Launch film\nOpen on the menu bar going quiet. No voiceover.",
            "Ideas for HQ\nRelease count per week as a graph.\nNotes from the Mac.",
            "Call with the accountant\nVAT threshold, year end, what to keep.",
            "Things to read",
        ]
        let focus = ((try? context.fetch(FetchDescriptor<Project>())) ?? []).first { $0.remoteID == "focus" }
        for (index, text) in texts.enumerated() {
            let made = now.addingTimeInterval(-Double(index) * 2.6 * 86_400 - 3600)
            let note = Note(text: text, project: index < 2 ? focus : nil, created: made)
            note.pinned = index == 0
            context.insert(note)
        }
        try? context.save()
    }
}

// MARK: - Sending the phone's work back

/// Where a feed file sits on GitHub, read out of whichever link was pasted.
nonisolated struct FeedAddress: Equatable, Sendable {
    let owner: String
    let repo: String
    let path: String
    let ref: String?

    /// Understands the three shapes a GitHub file link comes in: the page
    /// (github.com/…/blob/…), the raw file, and the API address.
    static func github(_ text: String) -> FeedAddress? {
        guard let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host?.lowercased() else { return nil }
        let bits = parts.path.split(separator: "/").map(String.init)
        switch host {
        case "api.github.com":
            guard bits.count >= 5, bits[0] == "repos", bits[3] == "contents" else { return nil }
            let ref = parts.queryItems?.first { $0.name == "ref" }?.value
            return FeedAddress(owner: bits[1], repo: bits[2], path: bits[4...].joined(separator: "/"), ref: ref)
        case "github.com", "www.github.com":
            guard bits.count >= 5, bits[2] == "blob" else { return nil }
            return FeedAddress(owner: bits[0], repo: bits[1], path: bits[4...].joined(separator: "/"), ref: bits[3])
        case "raw.githubusercontent.com":
            if bits.count >= 6, bits[2] == "refs", bits[3] == "heads" {
                return FeedAddress(owner: bits[0], repo: bits[1], path: bits[5...].joined(separator: "/"), ref: bits[4])
            }
            guard bits.count >= 4 else { return nil }
            return FeedAddress(owner: bits[0], repo: bits[1], path: bits[3...].joined(separator: "/"), ref: bits[2])
        default:
            return nil
        }
    }

    var api: URL? {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "api.github.com"
        parts.path = "/repos/\(owner)/\(repo)/contents/\(path)"
        if let ref { parts.queryItems = [URLQueryItem(name: "ref", value: ref)] }
        return parts.url
    }
}

nonisolated struct GitHubFile: Sendable {
    let data: Data
    let sha: String
}

nonisolated enum GitHub {
    nonisolated private struct Contents: Decodable {
        let content: String
        let sha: String
    }

    private static func prepare(_ address: FeedAddress, token: String?) throws -> URLRequest {
        guard let url = address.api else { throw FeedError(message: "That GitHub address doesn't read as a file.") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static func get(_ address: FeedAddress, token: String?) async throws -> GitHubFile {
        let (data, response) = try await URLSession.shared.data(for: try prepare(address, token: token))
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw FeedError(message: code == 404 ? "GitHub can't see that file. A private repo needs a token." : "GitHub returned \(code).")
        }
        guard let contents = try? JSONDecoder().decode(Contents.self, from: data),
              let file = Data(base64Encoded: contents.content, options: .ignoreUnknownCharacters) else {
            throw FeedError(message: "GitHub's answer wasn't a file.")
        }
        return GitHubFile(data: file, sha: contents.sha)
    }

    static func put(_ address: FeedAddress, token: String, data: Data, sha: String, message: String) async throws {
        var request = try prepare(address, token: token)
        request.httpMethod = "PUT"
        var body: [String: String] = ["message": message, "content": data.base64EncodedString(), "sha": sha]
        if let ref = address.ref { body["branch"] = ref }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 || code == 201 else {
            throw FeedError(message: code == 403 || code == 404 ? "the token can't write to the repo" : "GitHub returned \(code)")
        }
    }
}

/// A line made on the phone, on its way into the feed.
nonisolated struct NewLine: Equatable, Sendable {
    var id: String
    var title: String
    var notes = ""
    var done = false
    var children: [NewLine] = []

    var count: Int { 1 + children.reduce(0) { $0 + $1.count } }

    var json: [String: Any] {
        var line: [String: Any] = ["id": id, "title": title]
        if !notes.isEmpty { line["notes"] = notes }
        if done { line["done"] = true }
        if !children.isEmpty { line["children"] = children.map(\.json) }
        return line
    }
}

/// What the phone has that the feed might not: ticks, and lines added here.
nonisolated struct Outgoing: Equatable, Sendable {
    var ticks: Set<String> = []
    /// Project id → new top-level lines.
    var lines: [String: [NewLine]] = [:]
    /// Line id → new sub-items under it.
    var subs: [String: [NewLine]] = [:]
}

nonisolated struct PatchResult: Sendable {
    let data: Data
    let ticked: Int
    let added: Int
}

nonisolated enum FeedPatch {
    /// Writes the phone's ticks and new lines into the feed file. Like pulling,
    /// it only adds and ticks; whatever else is in the file is left as it was.
    static func apply(_ data: Data, _ outgoing: Outgoing) throws -> PatchResult {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var projects = root["projects"] as? [[String: Any]] else {
            throw FeedError(message: "The feed isn't in the expected format.")
        }
        var ticked = 0
        var added = 0
        for index in projects.indices {
            let had = projects[index]["items"] != nil
            var items = patch(projects[index]["items"] as? [[String: Any]] ?? [], outgoing, &ticked, &added)
            if let id = projects[index]["id"] as? String, let new = outgoing.lines[id] {
                let have = Set(items.compactMap { $0["id"] as? String })
                for line in new where !have.contains(line.id) {
                    items.append(line.json)
                    added += line.count
                }
            }
            if had || !items.isEmpty { projects[index]["items"] = items }
        }
        root["projects"] = projects
        let out = try JSONSerialization.data(withJSONObject: root,
                                             options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return PatchResult(data: out, ticked: ticked, added: added)
    }

    private static func patch(_ items: [[String: Any]], _ outgoing: Outgoing,
                              _ ticked: inout Int, _ added: inout Int) -> [[String: Any]] {
        var result: [[String: Any]] = []
        for original in items {
            var item = original
            let id = item["id"] as? String ?? ""
            if outgoing.ticks.contains(id), (item["done"] as? Bool) != true {
                item["done"] = true
                ticked += 1
            }
            var children = patch(item["children"] as? [[String: Any]] ?? [], outgoing, &ticked, &added)
            if let new = outgoing.subs[id] {
                let have = Set(children.compactMap { $0["id"] as? String })
                for line in new where !have.contains(line.id) {
                    children.append(line.json)
                    added += line.count
                }
            }
            if !children.isEmpty { item["children"] = children }
            result.append(item)
        }
        return result
    }
}

/// Gathers what the phone has to send, and the ids its new lines will take.
enum Outbox {
    struct Plan {
        var outgoing = Outgoing()
        var naming: [(item: FocusItem, id: String)] = []
    }

    static func plan(_ context: ModelContext) -> Plan {
        var plan = Plan()
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        for project in projects where !project.remoteID.isEmpty && !project.isPersonal {
            for item in project.sortedItems {
                if item.remoteID.isEmpty {
                    let new = make(item, &plan)
                    plan.outgoing.lines[project.remoteID, default: []].append(new)
                    continue
                }
                if item.done { plan.outgoing.ticks.insert(item.remoteID) }
                for child in item.sortedChildren {
                    if child.remoteID.isEmpty {
                        let new = make(child, &plan)
                        plan.outgoing.subs[item.remoteID, default: []].append(new)
                    } else if child.done {
                        plan.outgoing.ticks.insert(child.remoteID)
                    }
                }
            }
        }
        return plan
    }

    private static func make(_ item: FocusItem, _ plan: inout Plan) -> NewLine {
        let id = "phone-" + UUID().uuidString.prefix(8).lowercased()
        plan.naming.append((item, id))
        var children: [NewLine] = []
        for child in item.sortedChildren {
            children.append(make(child, &plan))
        }
        return NewLine(id: id, title: item.title, notes: item.notes, done: item.done, children: children)
    }
}

/// Keeps the phone and the Claude feed in step: pulls what Claude added, then
/// sends back what was ticked or added here.
@Observable final class FeedSync {
    static let tokenName = "feed-token"

    var address: String = UserDefaults.standard.string(forKey: "feed") ?? "" {
        didSet { UserDefaults.standard.set(address, forKey: "feed") }
    }
    var busy = false
    var status = ""
    var failed = false

    var isSet: Bool { !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func pull(into context: ModelContext) async {
        guard isSet, !busy else { return }
        busy = true
        defer { busy = false }
        let token = Keychain.get(Self.tokenName)
        do {
            guard let github = FeedAddress.github(address) else {
                // Not on GitHub: it can be read, but there's nowhere to write back to.
                let feed = try await Feed.fetch(address, token: token)
                status = feed.apply(to: context).summary
                failed = false
                return
            }
            let file = try await GitHub.get(github, token: token)
            let feed: Feed
            do {
                feed = try Feed.decode(file.data)
            } catch {
                throw FeedError(message: "The feed isn't in the expected format.")
            }
            var said = feed.apply(to: context).summary
            failed = false

            if let token, !token.isEmpty {
                let plan = Outbox.plan(context)
                let patched = try FeedPatch.apply(file.data, plan.outgoing)
                if patched.ticked + patched.added > 0 {
                    do {
                        try await GitHub.put(github, token: token, data: patched.data, sha: file.sha,
                                             message: "PARADOX: \(Self.sent(patched))")
                        for (item, id) in plan.naming { item.remoteID = id }
                        try? context.save()
                        said += ". Sent \(Self.sent(patched))"
                    } catch {
                        said += ". Couldn't send back: \(error.localizedDescription)"
                    }
                }
            }
            status = said
        } catch {
            status = error.localizedDescription
            failed = true
        }
    }

    private static func sent(_ patched: PatchResult) -> String {
        var parts: [String] = []
        if patched.ticked > 0 { parts.append(patched.ticked == 1 ? "1 tick" : "\(patched.ticked) ticks") }
        if patched.added > 0 { parts.append(patched.added == 1 ? "1 new line" : "\(patched.added) new lines") }
        return parts.joined(separator: ", ")
    }
}

/// Is the website up, and how fast did it answer.
@Observable final class SiteMonitor {
    nonisolated enum State: Equatable, Sendable {
        case unknown
        case checking
        case up(Int)
        case down(String)
    }

    var address: String = UserDefaults.standard.string(forKey: "site") ?? "https://paradoxica.uk/focus" {
        didSet { UserDefaults.standard.set(address, forKey: "site") }
    }
    var state: State = .unknown

    var host: String {
        URL(string: address)?.host() ?? address
    }

    var isDown: Bool {
        if case .down = state { return true }
        return false
    }

    func check() async {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            state = .unknown
            return
        }
        state = .checking
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        let started = Date()
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            state = (200..<400).contains(code) ? .up(ms) : .down("Returned \(code)")
        } catch {
            state = .down(error.localizedDescription)
        }
    }
}
