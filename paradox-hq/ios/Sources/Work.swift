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
    /// Published: it reached a live site (the `gh-pages` branch, which GitHub serves).
    /// A product's code landing on its main branch is not publishing: see `shipped`.
    var published: Bool
    /// The Claude conversation it was made in, when the commit names one
    /// ("Claude-Session: https://claude.ai/code/session_…"). Opens in the Claude app.
    var session: String? = nil
    /// It reached a product's main branch. Counted separately, and only when
    /// Settings asks for products on the Work card.
    var shipped: Bool? = nil

    var sessionLink: URL? { session.flatMap(URL.init(string:)) }

    /// "Added the icon designer": the kind, then the subject.
    var line: String {
        subject.isEmpty ? kind.title : "\(kind.title): \(subject)"
    }

    var link: URL? { URL(string: "https://github.com/\(repo)/commit/\(id)") }

    // MARK: Reading a commit message

    /// The branch GitHub serves as a live site.
    static let site = "gh-pages"
    /// The usual names of a product's main branch (a repo's own default is asked for too).
    static let mains: Set<String> = ["master", "main"]

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
        // The conversation it came from: the trailer's address, or one in the pull-request footer.
        let session = lines.lazy.compactMap { line -> String? in
            guard let found = line.range(of: "https://claude.ai/code/session_") else { return nil }
            let address = line[found.lowerBound...].prefix { !$0.isWhitespace && $0 != ")" && $0 != ">" }
            return address.count > "https://claude.ai/code/session_".count ? String(address) : nil
        }.first
        return WorkEntry(id: id, date: date, repo: repo, branches: branches.sorted(), kind: kind, project: project,
                         subject: subject, points: points, claude: !trailers.isEmpty || session != nil,
                         published: branches.contains(site), session: session,
                         shipped: !mains.isDisjoint(with: branches))
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

/// Messages sent to Claude on one day: the older shape of the Mac's file, still read.
nonisolated struct ClaudeDay: Codable, Hashable, Sendable {
    var day: String          // "2026-11-17"
    var messages: Int
    var sessions: Int
}

/// One conversation with Claude: when it began, when it was last used, and how
/// many messages were sent in each hour of it (keys are UTC hours, "2026-11-18T01").
nonisolated struct ClaudeSession: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var started: Date
    var last: Date
    var hours: [String: Int]
    /// Its address in Claude, when the counter was told it (cloud sessions are).
    /// The same address is on every change made in the conversation.
    var link: String? = nil

    var messages: Int { hours.values.reduce(0, +) }
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

/// The stretch of time the Work card is looking at.
nonisolated enum WorkSpan: String, CaseIterable, Identifiable, Sendable {
    case hour, session, day, week, month
    var id: String { rawValue }

    /// The word on its button. `rolling` is the bottom-left switch: the last 24
    /// hours, 7 days and 30 days instead of today, this week and this month.
    func title(rolling: Bool) -> String {
        switch self {
        case .hour: "Hour"
        case .session: "Session"
        case .day: rolling ? "24 h" : "Today"
        case .week: rolling ? "7 days" : "Week"
        case .month: rolling ? "30 days" : "Month"
        }
    }

    /// Said under each figure: "this hour", "last 24 hours".
    func caption(rolling: Bool) -> String {
        switch self {
        case .hour: "this hour"
        case .session: "this session"
        case .day: rolling ? "last 24 hours" : "today"
        case .week: rolling ? "last 7 days" : "this week"
        case .month: rolling ? "last 30 days" : "this month"
        }
    }

    /// When the stretch began. `session` is when the current Claude session started.
    func start(now: Date, calendar: Calendar, rolling: Bool, session: Date?) -> Date {
        switch self {
        case .hour:
            calendar.dateInterval(of: .hour, for: now)?.start ?? now
        case .session:
            session ?? calendar.startOfDay(for: now)
        case .day:
            rolling ? now.addingTimeInterval(-86_400) : calendar.startOfDay(for: now)
        case .week:
            rolling ? now.addingTimeInterval(-7 * 86_400) : calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        case .month:
            rolling ? now.addingTimeInterval(-30 * 86_400) : calendar.dateInterval(of: .month, for: now)?.start ?? now
        }
    }

    /// How the graph is cut for this stretch: 24 hours by the hour, or days.
    var graph: (unit: Calendar.Component, count: Int) {
        switch self {
        case .hour, .session, .day: (.hour, 24)
        case .week: (.day, 7)
        case .month: (.day, 30)
        }
    }
}

/// The sums behind the Work card. Pure, so they can be tested.
nonisolated enum WorkLedger {
    /// How many versions were pushed on each of the last `days` days, oldest first.
    static func perDay(_ entries: [WorkEntry], days: Int, now: Date, calendar: Calendar) -> [Bucket] {
        NoteText.perDay(entries.map(\.date), days: days, now: now, calendar: calendar)
    }

    /// Things that happened (each a time and how many) counted into the last
    /// `count` hours or days, oldest first. The newest bucket is the one `now` is in.
    static func buckets(_ points: [(date: Date, amount: Int)], unit: Calendar.Component, count: Int,
                        now: Date, calendar: Calendar) -> [Bucket] {
        guard let latest = calendar.dateInterval(of: unit, for: now)?.start else { return [] }
        var sums: [Date: Int] = [:]
        for point in points {
            if let start = calendar.dateInterval(of: unit, for: point.date)?.start { sums[start, default: 0] += point.amount }
        }
        return (0..<count).reversed().compactMap { back in
            calendar.date(byAdding: unit, value: -back, to: latest).map { Bucket(date: $0, amount: sums[$0] ?? 0) }
        }
    }

    /// Every hour in which messages went to Claude, across sessions. The same
    /// session reported twice (by the Mac and by a cloud session) counts once.
    static func messages(_ sessions: [ClaudeSession]) -> [(date: Date, amount: Int)] {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return unique(sessions).flatMap { session in
            session.hours.compactMap { key, amount -> (date: Date, amount: Int)? in
                let parts = key.split(whereSeparator: { $0 == "-" || $0 == "T" }).compactMap { Int($0) }
                guard parts.count == 4,
                      let date = utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3]))
                else { return nil }
                return (date, amount)
            }
        }
    }

    /// What was pushed in a conversation: exactly the changes that carry its
    /// address when it is known, otherwise everything since it began.
    static func work(in session: ClaudeSession, _ entries: [WorkEntry], now: Date) -> [WorkEntry] {
        if let link = session.link, !link.isEmpty {
            return entries.filter { $0.session == link }
        }
        return entries.filter { $0.date >= session.started && $0.date <= now }
    }

    /// A name with only its letters and digits, lower case: "PARADOX HQ" and "paradox-hq" are the same.
    static func plain(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// Whether a change belongs to a project. It is deliberately cautious, so a
    /// project never claims work that isn't its own: the change has to name the
    /// project (`feat(paradox-hq): …`, "Focus 0.0.4: …"), or sit on a branch
    /// filed under it (`focus/feat-desktop-app`). Words in the subject don't count.
    static func belongs(_ entry: WorkEntry, toProject name: String, id: String) -> Bool {
        let names = Set([plain(name), plain(id)].filter { $0.count >= 2 })
        guard !names.isEmpty else { return false }
        if names.contains(plain(entry.project)) { return true }
        return entry.branches.contains { branch in
            guard let filed = branch.split(separator: "/").first, branch.contains("/") else { return false }
            return names.contains(plain(String(filed)))
        }
    }

    /// One of each session: where two files report the same one, the fuller report.
    static func unique(_ sessions: [ClaudeSession]) -> [ClaudeSession] {
        var held: [String: ClaudeSession] = [:]
        for session in sessions where (held[session.id]?.messages ?? -1) < session.messages {
            held[session.id] = session
        }
        return held.values.sorted { $0.last > $1.last }
    }

    /// How many of `points` fall from `start` up to `now`. Hours are whole, so an
    /// hour counts when it began inside the stretch.
    static func total(_ points: [(date: Date, amount: Int)], from start: Date, to now: Date, calendar: Calendar) -> Int {
        let first = calendar.dateInterval(of: .hour, for: start)?.start ?? start
        return points.filter { $0.date >= first && $0.date <= now }.reduce(0) { $0 + $1.amount }
    }

    /// The older file had only days: each becomes a session of its own at midday.
    static func sessions(from days: [ClaudeDay]) -> [ClaudeSession] {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return days.compactMap { day in
            let parts = day.day.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3,
                  let noon = utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
            else { return nil }
            return ClaudeSession(id: "day-\(day.day)", started: noon, last: noon, hours: ["\(day.day)T12": day.messages])
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
                held.shipped = (held.shipped ?? false) || (entry.shipped ?? false)
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

    struct Repo: Decodable {
        var full_name: String
        var default_branch: String?
        var pushed_at: Date?
        var fork: Bool?
        var archived: Bool?
    }

    /// The repos worth reading: the account's own, pushed to inside the window, newest first.
    static func active(_ repos: [Repo], since: Date, limit: Int) -> [Repo] {
        Array(repos.filter { ($0.pushed_at ?? .distantPast) >= since && $0.fork != true && $0.archived != true }
            .sorted { ($0.pushed_at ?? .distantPast) > ($1.pushed_at ?? .distantPast) }
            .prefix(limit))
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
    /// `main` marks the branch as the product's main one whatever it is called.
    static func entries(_ commits: [Commit], repo: String, branch: String, main: Bool = false) -> [WorkEntry] {
        commits.compactMap { commit in
            guard commit.parents.count <= 1,
                  let date = commit.commit.committer?.date ?? commit.commit.author?.date else { return nil }
            let who = commit.commit.author?.name ?? ""
            if who.hasSuffix("-ci") || who.hasSuffix("-stats") || who.contains("[bot]") { return nil }
            var entry = WorkEntry.read(id: commit.sha, date: date, repo: repo, branches: [branch], message: commit.commit.message)
            entry.shipped = (entry.shipped ?? false) || main
            return entry
        }
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Fetches the work and keeps the last answer on the phone.
///
/// Nothing here is made up: versions come from GitHub's own API, message
/// counts from the file the Mac publishes. (The cloud build's screenshots use
/// example work, behind a launch argument the phone never gets.)
@MainActor @Observable final class WorkStore {
    /// The Keychain name of the GitHub token, when one has been given.
    nonisolated static let tokenName = "github-token"
    /// Where the counts of messages sent to Claude are published: by the Mac, for
    /// conversations held there, and by cloud sessions, for their own (a cloud
    /// conversation's transcript never reaches the Mac). See tools/claude_stats.py.
    nonisolated static let claudeFeeds = [
        URL(string: "https://raw.githubusercontent.com/Labern/Clean/stats/claude/claude.json")!,
        URL(string: "https://raw.githubusercontent.com/Labern/Clean/claude/dazzling-cerf-y7p4jg/paradox-hq/stats/cloud.json")!,
    ]
    nonisolated static let days = 30

    /// Whose GitHub account is read.
    var owner: String = UserDefaults.standard.string(forKey: "github-owner") ?? "Labern" {
        didSet { UserDefaults.standard.set(owner, forKey: "github-owner") }
    }
    private(set) var entries: [WorkEntry] = []
    private(set) var sessions: [ClaudeSession] = []
    /// When the Mac last counted. Nil until its file has been read once.
    private(set) var claudeCounted: Date? = nil
    /// The repos the last read covered, e.g. ["Labern/Clean"].
    private(set) var repos: [String] = []
    private(set) var loading = false
    private(set) var problem = ""
    private(set) var fetched: Date? = nil
    @ObservationIgnored private let file: URL

    private nonisolated struct Saved: Codable {
        var entries: [WorkEntry]
        var sessions: [ClaudeSession]?
        var fetched: Date?
        var repos: [String]?
        var claudeCounted: Date?
    }

    /// The session being talked to now: the one most recently used.
    var session: ClaudeSession? { sessions.first }

    init(file: URL = URL.applicationSupportDirectory.appending(path: "work.json")) {
        self.file = file
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            entries = saved.entries
            sessions = saved.sessions ?? []
            fetched = saved.fetched
            repos = saved.repos ?? []
            claudeCounted = saved.claudeCounted
        }
        // Only the cloud build's screenshots: it launches with -sampleNotes and never reaches GitHub.
        if Launch.unlocked, UserDefaults.standard.bool(forKey: "sampleNotes"), entries.isEmpty {
            entries = Self.sample()
            sessions = Self.sampleSessions()
            claudeCounted = .now
            repos = ["Labern/Clean"]
        }
    }

    /// The token to ask GitHub with: its own, or the one already given for the feed.
    var token: String? {
        let own = Keychain.get(Self.tokenName) ?? Keychain.get(FeedSync.tokenName)
        return own?.isEmpty == false ? own : nil
    }

    var hasToken: Bool { token != nil }

    /// "142 versions in 3 repositories", for the Company tab.
    var summary: String {
        guard fetched != nil else { return "Not read yet" }
        let versions = "\(entries.count) \(entries.count == 1 ? "version" : "versions")"
        return repos.count <= 1 ? "\(versions) in 30 days" : "\(versions) in \(repos.count) repositories"
    }

    /// Reads everything again. The Claude counts are plain public files and are
    /// read every time. GitHub's API is paced: without a token it allows 60
    /// questions an hour and one read asks ten to twenty, so it waits 20 minutes
    /// between reads unless told to go now.
    func refresh(force: Bool = false, now: Date = .now) async {
        guard !loading, !Launch.unlocked else { return }
        loading = true
        defer { loading = false }

        await readClaude()

        let rest: TimeInterval = hasToken ? 3 * 60 : 20 * 60
        if force || fetched.map({ now.timeIntervalSince($0) >= rest }) ?? true {
            do {
                let read = try await Self.read(owner: owner, token: token, now: now)
                entries = read.entries
                repos = read.repos
                problem = ""
            } catch {
                // What was read before stays on screen.
                problem = (error as? LocalizedError)?.errorDescription ?? "GitHub couldn't be reached."
            }
            fetched = now
        }
        let saved = Saved(entries: entries, sessions: sessions, fetched: fetched, repos: repos, claudeCounted: claudeCounted)
        try? JSONEncoder().encode(saved).write(to: file, options: .atomic)
    }

    /// The counts of Claude messages: small public files; a missing one is not a problem.
    private func readClaude() async {
        var read: [ClaudeSession] = []
        var counted: Date? = nil
        var answered = false
        for feed in Self.claudeFeeds {
            var request = URLRequest(url: feed)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let file = try? GitHubWork.decoder().decode(ClaudeFeed.self, from: data) else { continue }
            answered = true
            read += file.sessions ?? WorkLedger.sessions(from: file.days ?? [])
            if let updated = file.updated { counted = max(counted ?? updated, updated) }
        }
        if answered {
            sessions = WorkLedger.unique(read)
            claudeCounted = counted
        }
    }

    private nonisolated struct ClaudeFeed: Decodable {
        var updated: Date?
        var sessions: [ClaudeSession]?
        var days: [ClaudeDay]?
    }

    nonisolated struct Refused: LocalizedError {
        var code: Int
        var errorDescription: String? {
            switch code {
            case 401: "GitHub didn't accept the token."
            case 403, 429: "GitHub is limiting how often this phone can ask. It reads again shortly."
            case 404: "GitHub has no account by that name."
            default: "GitHub answered \(code)."
            }
        }
    }

    /// Every version pushed in the window, across the account's active repos.
    private nonisolated static func read(owner: String, token: String?, now: Date) async throws -> (entries: [WorkEntry], repos: [String]) {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let stamp = since.formatted(.iso8601)
        // With a token: everything of his, private too. Without: what the account shows publicly.
        let listing = token == nil ? "users/\(owner)/repos?sort=pushed&per_page=50"
                                   : "user/repos?affiliation=owner&sort=pushed&per_page=50"
        let all: [GitHubWork.Repo] = try await ask(listing, token: token)
        let active = GitHubWork.active(all, since: since, limit: token == nil ? 4 : 12)

        var seen: [WorkEntry] = []
        var asked = 0
        for repo in active {
            let name = repo.full_name
            // Which branches moved lately. A busy repo fills a page of events in a couple
            // of days, so more than one page is read.
            var events: [GitHubWork.Event] = []
            for page in 1...(token == nil ? 2 : 3) {
                let more: [GitHubWork.Event] = (try? await ask("repos/\(name)/events?per_page=100&page=\(page)", token: token)) ?? []
                events += more
                if more.count < 100 { break }
            }
            let main = repo.default_branch ?? "main"
            // The main branch and the live site are always read, so nothing shipped or published is missed.
            var branches = [main, WorkEntry.site]
            for branch in GitHubWork.branches(in: events) where !branches.contains(branch) { branches.append(branch) }
            for branch in branches.prefix(token == nil ? 10 : 30) {
                // Without a token, stop short of GitHub's hourly allowance.
                if token == nil, asked >= 30 { break }
                asked += 1
                let path = "repos/\(name)/commits?sha=\(branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? branch)&since=\(stamp)&per_page=100"
                do {
                    let commits: [GitHubWork.Commit] = try await ask(path, token: token)
                    seen += GitHubWork.entries(commits, repo: name, branch: branch, main: branch == main)
                } catch let refused as Refused where [404, 409, 422].contains(refused.code) {
                    continue    // a branch that has gone, or an empty repo
                }
            }
        }
        return (WorkLedger.merged(seen), active.map(\.full_name))
    }

    private nonisolated static func ask<T: Decodable>(_ path: String, token: String?) async throws -> T {
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
            "feat(paradox-hq): one header row; Dashboard in Graphik\n\n- The mark and Dashboard on the left, the photo and role on the right\n- Settings > Typeface switches the whole app\n\nCo-Authored-By: Claude <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_example",
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
            return WorkEntry.read(id: String(format: "%040d", index), date: date, repo: "Labern/Clean",
                                  branches: [index % 3 == 0 ? "gh-pages" : index % 3 == 1 ? "master" : "claude/work"], message: message)
        }
    }

    static func sampleSessions(now: Date = .now) -> [ClaudeSession] {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return (0..<9).map { back in
            let last = now.addingTimeInterval(-Double(back) * 19 * 3600)
            var hours: [String: Int] = [:]
            for step in 0..<4 {
                let parts = utc.dateComponents([.year, .month, .day, .hour], from: last.addingTimeInterval(-Double(step) * 3600))
                let key = String(format: "%04d-%02d-%02dT%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0)
                hours[key] = [9, 14, 6, 3][step] + back % 5
            }
            return ClaudeSession(id: "sample\(back)", started: last.addingTimeInterval(-3 * 3600), last: last, hours: hours)
        }
    }
}
