import Foundation
import SwiftUI

// The work itself: every version pushed to GitHub, read as what was done
// ("Added the icon designer", "Fixed the App button"), and how many messages
// went to Claude to get there.

/// What kind of thing a version did.
nonisolated enum WorkKind: String, Codable, CaseIterable, Sendable {
    case added, fixed, changed, styled, wrote, tested, tidied

    var title: String {
        switch self {
        case .added: "Added"
        case .fixed: "Fixed"
        case .changed: "Changed"
        case .styled: "Styled"
        case .wrote: "Wrote"
        case .tested: "Tested"
        case .tidied: "Tidied"
        }
    }

    var symbol: String {
        switch self {
        case .added: "plus"
        case .fixed: "wrench.adjustable"
        case .changed: "arrow.triangle.2.circlepath"
        case .styled: "paintbrush"
        case .wrote: "text.alignleft"
        case .tested: "checkmark.seal"
        case .tidied: "sparkles"
        }
    }
}

/// One version pushed: when, where, and what it did in plain words.
nonisolated struct WorkEntry: Codable, Identifiable, Hashable, Sendable {
    var id: String              // the commit's full hash
    var date: Date
    var repo: String            // "Labern/Clean"
    var branches: [String]
    var kind: WorkKind
    /// The product it touched, e.g. "paradox-hq". Empty when the message doesn't say.
    var project: String
    /// "the icon designer, built on the logo playground"
    var subject: String
    /// The message's own bullet points: what was added, changed, styled.
    var points: [String]
    /// Made with Claude (the message carries Claude's trailers).
    var claude: Bool
    /// On a branch that is live: the default branch or the published pages.
    var published: Bool

    /// "Added the icon designer": the kind, then the subject.
    var line: String {
        subject.isEmpty ? kind.title : "\(kind.title): \(subject)"
    }

    var link: URL? { URL(string: "https://github.com/\(repo)/commit/\(id)") }

    // MARK: Reading a commit message

    /// Branches whose commits count as published.
    static let live: Set<String> = ["master", "main", "gh-pages"]

    /// Reads a commit message into what it did. Handles "feat(scope): subject"
    /// and plain sentences ("Add the icon designer"); bullets come from "- " lines.
    static func read(id: String, date: Date, repo: String, branches: [String], message: String) -> WorkEntry {
        let lines = message.components(separatedBy: .newlines)
        let head = lines.first?.trimmingCharacters(in: .whitespaces) ?? ""
        let trailers = lines.filter { $0.contains("Co-Authored-By: Claude") || $0.hasPrefix("Claude-Session:") || $0.contains("Generated with [Claude Code]") }

        var kind = WorkKind.changed
        var project = ""
        var subject = head
        // "feat(paradox-hq): one header row" or "fix: the tick".
        if let colon = head.firstIndex(of: ":"), head.distance(from: head.startIndex, to: colon) <= 40 {
            var label = String(head[..<colon])
            if let open = label.firstIndex(of: "("), let close = label.lastIndex(of: ")"), open < close {
                project = String(label[label.index(after: open)..<close])
                label = String(label[..<open])
            }
            if let known = kinds[label.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "! "))] {
                kind = known
                subject = String(head[head.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            } else {
                project = ""
            }
        }
        // "Add …", "Fixed …", "Polish …": the first word says it.
        if subject == head, let first = head.split(separator: " ").first,
           let known = verbs[first.lowercased()] {
            kind = known
            subject = head.dropFirst(first.count).trimmingCharacters(in: .whitespaces)
        }
        // "Focus 0.0.4: stress-tested" names its product before the colon.
        if project.isEmpty, subject == head, let colon = head.firstIndex(of: ":") {
            let before = head[..<colon]
            if before.count <= 24, !before.contains(" ") || before.split(separator: " ").count <= 2 {
                project = String(before.split(separator: " ").first ?? "")
                subject = String(head[head.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
        }

        // Bullets: "- text", with wrapped lines joined back on.
        var points: [String] = []
        for raw in lines.dropFirst() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                points.append(String(line.dropFirst(2)))
            } else if !line.isEmpty, !trailers.contains(raw), raw.hasPrefix("  "), !points.isEmpty {
                points[points.count - 1] += " " + line
            }
        }
        return WorkEntry(id: id, date: date, repo: repo, branches: branches.sorted(), kind: kind, project: project,
                         subject: subject, points: points, claude: !trailers.isEmpty,
                         published: !live.isDisjoint(with: branches))
    }

    private static let kinds: [String: WorkKind] = [
        "feat": .added, "feature": .added, "add": .added,
        "fix": .fixed, "bug": .fixed, "hotfix": .fixed,
        "style": .styled, "design": .styled, "ui": .styled,
        "docs": .wrote, "doc": .wrote, "copy": .wrote,
        "test": .tested, "tests": .tested,
        "refactor": .changed, "perf": .changed, "change": .changed, "update": .changed,
        "chore": .tidied, "ci": .tidied, "build": .tidied, "revert": .tidied,
    ]

    private static let verbs: [String: WorkKind] = [
        "add": .added, "added": .added, "adds": .added, "new": .added, "create": .added, "created": .added,
        "build": .added, "built": .added, "introduce": .added,
        "fix": .fixed, "fixed": .fixed, "fixes": .fixed, "repair": .fixed,
        "style": .styled, "styled": .styled, "polish": .styled, "polished": .styled, "restyle": .styled,
        "write": .wrote, "wrote": .wrote, "document": .wrote,
        "test": .tested, "tested": .tested,
        "change": .changed, "changed": .changed, "update": .changed, "updated": .changed, "rename": .changed,
        "move": .changed, "rework": .changed, "make": .changed,
        "remove": .tidied, "removed": .tidied, "delete": .tidied, "tidy": .tidied, "clean": .tidied,
    ]
}

/// Messages sent to Claude on one day (counted on the Mac, see tools/claude_stats.py).
nonisolated struct ClaudeDay: Codable, Hashable, Sendable {
    var day: String          // "2026-11-17"
    var messages: Int
    var sessions: Int
}

/// What the graph can show.
nonisolated enum WorkMeasure: String, CaseIterable, Identifiable, Sendable {
    case pushed = "Pushed", claude = "Claude", writing = "Writing"
    var id: String { rawValue }

    var unit: (one: String, many: String) {
        switch self {
        case .pushed: ("version", "versions")
        case .claude: ("message", "messages")
        case .writing: ("note", "notes")
        }
    }
}

/// The sums behind the Work card. Pure, so they can be tested.
nonisolated enum WorkLedger {
    /// How many versions were pushed on each of the last `days` days, oldest first.
    static func perDay(_ entries: [WorkEntry], days: Int, now: Date, calendar: Calendar) -> [Bucket] {
        NoteText.perDay(entries.map(\.date), days: days, now: now, calendar: calendar)
    }

    /// Messages to Claude on each of the last `days` days, oldest first.
    static func perDay(_ claude: [ClaudeDay], days: Int, now: Date, calendar: Calendar) -> [Bucket] {
        let counts = Dictionary(claude.map { ($0.day, $0.messages) }, uniquingKeysWith: +)
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: today).map { date in
                Bucket(date: date, amount: counts[stamp(date, calendar)] ?? 0)
            }
        }
    }

    /// "2026-11-17" for a date, in the calendar's own time zone.
    static func stamp(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The entries of one day, latest first.
    static func on(_ day: Date, _ entries: [WorkEntry], calendar: Calendar) -> [WorkEntry] {
        entries.filter { calendar.isDate($0.date, inSameDayAs: day) }.sorted { $0.date > $1.date }
    }

    /// Entries grouped by day, latest day first, each day latest first.
    static func byDay(_ entries: [WorkEntry], calendar: Calendar) -> [(day: Date, entries: [WorkEntry])] {
        Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
            .map { (day: $0.key, entries: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    /// The same commit seen on several branches is one piece of work.
    static func merged(_ seen: [WorkEntry]) -> [WorkEntry] {
        var byID: [String: WorkEntry] = [:]
        for entry in seen {
            if var held = byID[entry.id] {
                held.branches = Array(Set(held.branches + entry.branches)).sorted()
                held.published = held.published || entry.published
                byID[entry.id] = held
            } else {
                byID[entry.id] = entry
            }
        }
        return byID.values.sorted { $0.date > $1.date }
    }
}

// MARK: - GitHub

/// The little of GitHub's JSON that is read.
nonisolated enum GitHubWork {
    struct Event: Decodable {
        var type: String
        var payload: Payload
        struct Payload: Decodable { var ref: String? }
    }

    struct Commit: Decodable {
        var sha: String
        var commit: Detail
        var parents: [Parent]
        struct Detail: Decodable {
            var message: String
            var committer: Person?
            var author: Person?
        }
        struct Person: Decodable {
            var name: String?
            var date: Date?
        }
        struct Parent: Decodable { var sha: String }
    }

    /// The branches pushed to lately, from the repo's event feed, newest first.
    static func branches(in events: [Event]) -> [String] {
        var seen: [String] = []
        for event in events where event.type == "PushEvent" {
            guard let ref = event.payload.ref, ref.hasPrefix("refs/heads/") else { continue }
            let branch = String(ref.dropFirst("refs/heads/".count))
            // Build results and the message count are robots' branches, not work.
            if !branch.hasPrefix("ci/"), !branch.hasPrefix("stats/"), !seen.contains(branch) { seen.append(branch) }
        }
        return seen
    }

    /// Commits as work: merges and the build robot's own commits are left out.
    static func entries(_ commits: [Commit], repo: String, branch: String) -> [WorkEntry] {
        commits.compactMap { commit in
            guard commit.parents.count <= 1,
                  let date = commit.commit.committer?.date ?? commit.commit.author?.date else { return nil }
            let who = commit.commit.author?.name ?? ""
            if who.hasSuffix("-ci") || who.contains("[bot]") { return nil }
            return WorkEntry.read(id: commit.sha, date: date, repo: repo, branches: [branch], message: commit.commit.message)
        }
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Fetches the work and keeps the last answer on the phone.
@MainActor @Observable final class WorkStore {
    /// The repos read. One for now: everything is built in it.
    static let repos = ["Labern/Clean"]
    /// Where the Mac publishes the count of messages sent to Claude.
    static let claudeFeed = URL(string: "https://raw.githubusercontent.com/Labern/Clean/stats/claude/claude.json")!
    static let days = 30

    private(set) var entries: [WorkEntry] = []
    private(set) var claude: [ClaudeDay] = []
    private(set) var loading = false
    private(set) var problem = ""
    private(set) var fetched: Date? = nil
    @ObservationIgnored private let file: URL

    private nonisolated struct Saved: Codable {
        var entries: [WorkEntry]
        var claude: [ClaudeDay]
        var fetched: Date?
    }

    init(file: URL = URL.applicationSupportDirectory.appending(path: "work.json")) {
        self.file = file
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            entries = saved.entries
            claude = saved.claude
            fetched = saved.fetched
        }
        if Launch.screen == "work" || UserDefaults.standard.bool(forKey: "sampleNotes") && entries.isEmpty {
            entries = Self.sample()
            claude = Self.sampleClaude()
        }
    }

    /// Reads GitHub again, unless it was read in the last few minutes (without a
    /// token GitHub allows 60 questions an hour, and one refresh asks about ten).
    func refresh(force: Bool = false, now: Date = .now) async {
        guard !loading, !Launch.unlocked || force else { return }
        if !force, let fetched, now.timeIntervalSince(fetched) < 15 * 60 { return }
        loading = true
        defer { loading = false }
        let token = Keychain.get(FeedSync.tokenName)
        do {
            var seen: [WorkEntry] = []
            let since = Calendar.current.date(byAdding: .day, value: -Self.days, to: now) ?? now
            for repo in Self.repos {
                let events: [GitHubWork.Event] = try await Self.ask("repos/\(repo)/events?per_page=100", token: token)
                let pushed = GitHubWork.branches(in: events)
                // The live branches are always read, so "published" is right.
                let branches = Array((pushed + WorkEntry.live.sorted()).reduce(into: [String]()) { list, branch in
                    if !list.contains(branch) { list.append(branch) }
                }.prefix(14))
                let stamp = since.formatted(.iso8601)
                for branch in branches {
                    let path = "repos/\(repo)/commits?sha=\(branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? branch)&since=\(stamp)&per_page=100"
                    // A branch that has gone, or never was, is simply skipped.
                    guard let commits: [GitHubWork.Commit] = try? await Self.ask(path, token: token) else { continue }
                    seen += GitHubWork.entries(commits, repo: repo, branch: branch)
                }
            }
            entries = WorkLedger.merged(seen)
            problem = ""
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? "GitHub couldn't be reached."
        }
        // The count of Claude messages is a small public file; missing is fine.
        if let (data, response) = try? await URLSession.shared.data(from: Self.claudeFeed),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let feed = try? JSONDecoder().decode(ClaudeFeed.self, from: data) {
            claude = feed.days
        }
        fetched = now
        try? JSONEncoder().encode(Saved(entries: entries, claude: claude, fetched: fetched)).write(to: file, options: .atomic)
    }

    private nonisolated struct ClaudeFeed: Decodable { var days: [ClaudeDay] }

    private nonisolated struct Refused: LocalizedError {
        var code: Int
        var errorDescription: String? {
            code == 403 || code == 429 ? "GitHub is rate-limiting this phone. It reads again shortly." : "GitHub answered \(code)."
        }
    }

    private static func ask<T: Decodable>(_ path: String, token: String?) async throws -> T {
        var request = URLRequest(url: URL(string: "https://api.github.com/\(path)")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw Refused(code: code) }
        return try GitHubWork.decoder().decode(T.self, from: data)
    }

    // MARK: Example work, for the cloud build's screenshots

    static func sample(now: Date = .now) -> [WorkEntry] {
        let messages = [
            "feat(paradox-hq): one header row; Dashboard in Graphik\n\n- The mark and Dashboard on the left, the photo and role on the right\n- Settings > Typeface switches the whole app\n\nCo-Authored-By: Claude <noreply@anthropic.com>",
            "fix(paradox-hq): Focus wears its own colours on the links",
            "feat(paradox-hq): mark a note done with a swipe; a Done list that folds\n\n- A done note is crossed out with a tick\n- Tap the Done heading to fold the list away",
            "style(focus): quieter session banner",
            "feat(focus): named sessions\n\n- Name a session as it starts\n- Past sessions list them by name",
            "docs(paradox-hq): how the feed keeps the phone's edits",
            "fix(focus): the Dock icon stayed after quitting",
            "feat(pica): import a Final Draft PDF",
        ]
        return messages.enumerated().map { index, message in
            let date = now.addingTimeInterval(-Double(index) * 5.3 * 3600 - 1200)
            return WorkEntry.read(id: String(format: "%040d", index), date: date, repo: repos[0],
                                  branches: [index % 3 == 0 ? "master" : "claude/work"], message: message)
        }
    }

    static func sampleClaude(now: Date = .now) -> [ClaudeDay] {
        (0..<14).map { back in
            let date = Calendar.current.date(byAdding: .day, value: -back, to: now) ?? now
            return ClaudeDay(day: WorkLedger.stamp(date, .current), messages: [84, 131, 40, 0, 212, 96, 57][back % 7], sessions: 3 + back % 4)
        }
    }
}
