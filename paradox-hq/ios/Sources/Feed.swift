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
        guard existing == 0, let feed = Feed.bundled() else { return }
        feed.apply(to: context)
    }
}

/// Pulls the Claude feed from wherever it's hosted.
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
        do {
            let feed = try await Feed.fetch(address, token: Keychain.get(Self.tokenName))
            let outcome = feed.apply(to: context)
            status = outcome.summary
            failed = false
        } catch {
            status = error.localizedDescription
            failed = true
        }
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
