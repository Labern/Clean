import Foundation

// The canonical copy of everything lives in the company's Supabase project.
// The site, the Mac app and this app all read and write that one copy, so a
// change made anywhere shows everywhere. This file is the plumbing: where it
// is, signing in, asking and telling, and hearing that something changed.
// What is sent and how it is merged is in `CloudSync.swift`.
//
// The project's address and its public key are not in this repo, which is
// public. They sit on the Mac in `Resources/Private/cloud.json` and a build
// made there carries them. A build without them has no cloud: everything
// stays on the phone, exactly as before.

/// Where the canonical copy is.
nonisolated struct CloudConfig: Codable, Sendable {
    var url: URL
    /// The publishable key: made to be shipped in apps, and useless without a sign-in.
    var key: String

    static let current: CloudConfig? = {
        guard let file = Bundle.main.url(forResource: "cloud", withExtension: "json"),
              let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(CloudConfig.self, from: data)
    }()
}

/// Any JSON value, so rows can be carried without a type for every table.
nonisolated enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let value = try? box.decode(Bool.self) { self = .bool(value) }
        else if let value = try? box.decode(Double.self) { self = .number(value) }
        else if let value = try? box.decode(String.self) { self = .string(value) }
        else if let value = try? box.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try box.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self {
        case .null: try box.encodeNil()
        case .bool(let value): try box.encode(value)
        case .number(let value):
            // Whole numbers go as whole numbers: a column of integers refuses "3.0".
            if value.rounded() == value, abs(value) < 9e15 { try box.encode(Int64(value)) } else { try box.encode(value) }
        case .string(let value): try box.encode(value)
        case .array(let value): try box.encode(value)
        case .object(let value): try box.encode(value)
        }
    }

    var string: String? { if case .string(let value) = self { value } else { nil } }
    var number: Double? { if case .number(let value) = self { value } else { nil } }
    var bool: Bool? { if case .bool(let value) = self { value } else { nil } }
    var isNull: Bool { self == .null }
}

/// One row of one table, as the server holds it.
typealias CloudRow = [String: JSONValue]

nonisolated struct CloudError: LocalizedError, Sendable {
    var code: Int
    var message: String
    var errorDescription: String? { message }

    /// The server's own words where it gave some.
    static func read(_ data: Data, code: Int) -> CloudError {
        let said = (try? JSONDecoder().decode([String: JSONValue].self, from: data)) ?? [:]
        let words = ["error_description", "msg", "message", "error"].compactMap { said[$0]?.string }.first
        return CloudError(code: code, message: words ?? "The dashboard's server answered \(code).")
    }
}

/// The times the server sends and takes: ISO 8601 to the millisecond, in UTC.
/// Written and read by hand, because a time must come back as exactly the text
/// that was sent: the sync compares them, and the system's formatter turns
/// "…50.123" into "…50.122" one time in a few.
nonisolated enum CloudDate {
    /// "2026-11-18T19:03:50.123Z", or the same with any number of fraction digits and any offset.
    static func read(_ text: String) -> Date? {
        var whole = text
        var fraction = 0.0
        if let dot = text.firstIndex(of: ".") {
            let after = text[text.index(after: dot)...]
            let digits = after.prefix { $0.isNumber }
            fraction = Double("0." + digits) ?? 0
            whole = String(text[..<dot]) + String(after.dropFirst(digits.count))
        }
        // No zone given: the server means UTC.
        let clock = whole.split(separator: "T").last.map(String.init) ?? ""
        if !whole.hasSuffix("Z"), !clock.contains(where: { $0 == "+" || $0 == "-" }) { whole += "Z" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: whole)?.addingTimeInterval(fraction)
    }

    static func write(_ date: Date) -> String {
        let total = Int64((date.timeIntervalSince1970 * 1000).rounded())
        let seconds = total >= 0 ? total / 1000 : (total - 999) / 1000
        let millis = total - seconds * 1000
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let text = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))     // …:50Z
        return String(text.dropLast()) + String(format: ".%03d", Int(millis)) + "Z"
    }

    /// A time the server sent, as this app would have written it.
    static func same(_ text: String) -> String { read(text).map(write) ?? text }
}

// MARK: - Signing in

/// Who is signed in, and the pass that proves it. The pass lasts an hour and is
/// renewed with a longer-lived one kept in the Keychain; the password is never kept.
actor CloudAccount {
    nonisolated static let renewalKey = "cloud-renewal"
    nonisolated static let emailKey = "cloud-email"

    struct Pass: Codable, Sendable {
        var access_token: String
        var refresh_token: String
        var expires_in: Double
        var user: User?
        struct User: Codable, Sendable { var id: String; var email: String? }
    }

    let config: CloudConfig
    private var access: String? = nil
    private var expires: Date = .distantPast
    private(set) var userID: String? = nil

    init(config: CloudConfig) { self.config = config }

    nonisolated var hasRenewal: Bool { Keychain.get(Self.renewalKey) != nil }
    nonisolated var email: String? { Keychain.get(Self.emailKey) }

    func signIn(email: String, password: String) async throws {
        try await take(grant: "password", body: ["email": email, "password": password])
    }

    /// Makes the account. Only an address the server has been told to allow gets one.
    func signUp(email: String, password: String) async throws {
        var request = URLRequest(url: config.url.appending(path: "auth/v1/signup"))
        request.httpMethod = "POST"
        request.setValue(config.key, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["email": email, "password": password])
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw CloudError.read(data, code: code) }
        // An allowed address is confirmed at once, so signing in works straight away.
        try await signIn(email: email, password: password)
    }

    func signOut() {
        Keychain.delete(Self.renewalKey)
        Keychain.delete(Self.emailKey)
        access = nil
        userID = nil
        expires = .distantPast
    }

    /// A pass that is good for at least the next minute, renewed if need be.
    func token() async throws -> String {
        if let access, expires.timeIntervalSinceNow > 60 { return access }
        guard let renewal = Keychain.get(Self.renewalKey) else { throw CloudError(code: 401, message: "Not signed in to the dashboard.") }
        do {
            try await take(grant: "refresh_token", body: ["refresh_token": renewal])
        } catch let error as CloudError where error.code == 400 || error.code == 401 || error.code == 403 {
            // The long-lived pass was refused: it has been used elsewhere or revoked. Sign in again.
            signOut()
            throw CloudError(code: 401, message: "Signed out of the dashboard. Sign in again.")
        }
        guard let access else { throw CloudError(code: 401, message: "Not signed in to the dashboard.") }
        return access
    }

    private func take(grant: String, body: [String: String]) async throws {
        var parts = URLComponents(url: config.url.appending(path: "auth/v1/token"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "grant_type", value: grant)]
        var request = URLRequest(url: parts.url!)
        request.httpMethod = "POST"
        request.setValue(config.key, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw CloudError.read(data, code: code) }
        let pass = try JSONDecoder().decode(Pass.self, from: data)
        access = pass.access_token
        expires = Date().addingTimeInterval(pass.expires_in)
        userID = pass.user?.id ?? userID
        Keychain.set(pass.refresh_token, for: Self.renewalKey)
        if let email = pass.user?.email { Keychain.set(email, for: Self.emailKey) }
    }
}

// MARK: - Asking and telling

/// Reads and writes rows over the project's REST interface.
nonisolated struct CloudAPI: Sendable {
    let config: CloudConfig
    let account: CloudAccount

    private func ask(_ path: String, query: [URLQueryItem] = []) async throws -> URLRequest {
        var parts = URLComponents(url: config.url.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { parts.queryItems = query }
        var request = URLRequest(url: parts.url!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(config.key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(try await account.token())", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw CloudError.read(data, code: code) }
        return data
    }

    /// Every row of a table that the signed-in person may see.
    func rows(_ table: String) async throws -> [CloudRow] {
        var found: [CloudRow] = []
        // A thousand at a time, which is the server's own limit for one answer.
        var from = 0
        while true {
            var request = try await ask("rest/v1/\(table)", query: [URLQueryItem(name: "select", value: "*")])
            request.setValue("\(from)-\(from + 999)", forHTTPHeaderField: "Range")
            request.setValue("items", forHTTPHeaderField: "Range-Unit")
            let page = try JSONDecoder().decode([CloudRow].self, from: try await send(request))
            found += page
            if page.count < 1000 { return found }
            from += 1000
        }
    }

    /// Adds rows, or replaces the ones with the same id.
    func put(_ rows: [CloudRow], in table: String) async throws {
        guard !rows.isEmpty else { return }
        var request = try await ask("rest/v1/\(table)", query: [URLQueryItem(name: "on_conflict", value: "id")])
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(rows)
        _ = try await send(request)
    }

    /// Changes some columns of one row, leaving the rest as they are.
    func change(_ id: String, to columns: CloudRow, in table: String) async throws {
        guard !columns.isEmpty else { return }
        var request = try await ask("rest/v1/\(table)", query: [URLQueryItem(name: "id", value: "eq.\(id)")])
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(columns)
        _ = try await send(request)
    }

    /// Deletes rows by id, a hundred at a time.
    func remove(_ ids: [String], from table: String) async throws {
        var left = ids[...]
        while !left.isEmpty {
            let some = left.prefix(100)
            left = left.dropFirst(100)
            var request = try await ask("rest/v1/\(table)",
                                        query: [URLQueryItem(name: "id", value: "in.(\(some.joined(separator: ",")))")])
            request.httpMethod = "DELETE"
            request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
            _ = try await send(request)
        }
    }

    /// Calls one of the project's server functions (Money and Work are read there, so no device holds a key).
    func function(_ name: String, query: [URLQueryItem] = []) async throws -> Data {
        try await send(try await ask("functions/v1/\(name)", query: query))
    }
}

// MARK: - Hearing about changes

/// A line held open to the server, which says the moment any row changes, so
/// a tick made on the site lands on the phone within a second. It only ever
/// says "something changed": the sync then reads what did.
nonisolated final class CloudSocket: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let config: CloudConfig
    private let account: CloudAccount
    private let changed: @Sendable () -> Void
    private var task: URLSessionWebSocketTask? = nil
    private var session: URLSession? = nil
    private var beat: Task<Void, Never>? = nil
    private var count = 0
    private var wanted = false
    private let lock = NSLock()

    init(config: CloudConfig, account: CloudAccount, changed: @escaping @Sendable () -> Void) {
        self.config = config
        self.account = account
        self.changed = changed
    }

    func open() {
        lock.withLock { wanted = true }
        Task { await connect() }
    }

    func close() {
        lock.withLock { wanted = false }
        beat?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func next() -> String {
        lock.withLock {
            count += 1
            return String(count)
        }
    }

    private func connect() async {
        guard lock.withLock({ wanted }), task == nil, let token = try? await account.token() else { return }
        var parts = URLComponents(url: config.url.appending(path: "realtime/v1/websocket"), resolvingAgainstBaseURL: false)!
        parts.scheme = "wss"
        parts.queryItems = [URLQueryItem(name: "apikey", value: config.key), URLQueryItem(name: "vsn", value: "1.0.0")]
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: parts.url!)
        self.session = session
        self.task = task
        task.resume()

        // Join one channel that hears every change the signed-in person may see.
        let join: JSONValue = .object([
            "topic": .string("realtime:phone"),
            "event": .string("phx_join"),
            "ref": .string(next()),
            "payload": .object([
                "access_token": .string(token),
                "config": .object([
                    "broadcast": .object(["self": .bool(false)]),
                    "presence": .object(["key": .string("")]),
                    "postgres_changes": .array([.object(["event": .string("*"), "schema": .string("public")])]),
                ]),
            ]),
        ])
        send(join)
        listen(task)

        beat?.cancel()
        beat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard let self, !Task.isCancelled else { return }
                self.send(.object(["topic": .string("phoenix"), "event": .string("heartbeat"),
                                   "payload": .object([:]), "ref": .string(self.next())]))
            }
        }
    }

    private func send(_ message: JSONValue) {
        guard let data = try? JSONEncoder().encode(message), let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }

    private func listen(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self, self.task === task else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message, text.contains("\"postgres_changes\"") { self.changed() }
                self.listen(task)
            case .failure:
                self.dropped()
            }
        }
    }

    /// The line went down: try again shortly, for as long as it is wanted.
    private func dropped() {
        beat?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        guard lock.withLock({ wanted }) else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            await self?.connect()
            // Anything that changed while the line was down is caught by a read.
            self?.changed()
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        if self.task === webSocketTask { dropped() }
    }
}
