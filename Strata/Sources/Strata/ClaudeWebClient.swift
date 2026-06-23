/// Two-phase auth, mirroring the proven pattern from ClaudeUsageMonitor:
///   Phase 1 — login via NSWindow WKWebView, then capture + persist cookies to disk.
///   Phase 2 — all API calls via URLSession + Cookie header (not the WebView).
/// WKWebView's WKWebsiteDataStore.default() cookie storage is unreliable across
/// launches for ad-hoc-signed apps — confirmed empirically in ClaudeUsageMonitor.

import Foundation
import WebKit
import AppKit
import StrataCore

// MARK: - Cookie persistence

struct SavedCookie: Codable {
    let name: String
    let value: String
    let domain: String
}

private let cookieJarURL: URL = {
    strataSupportDir().appendingPathComponent("cookies.json")
}()

func loadSavedCookies() -> [SavedCookie] {
    guard let data = try? Data(contentsOf: cookieJarURL),
          let decoded = try? JSONDecoder().decode([SavedCookie].self, from: data)
    else { return [] }
    return decoded
}

private func persistCookies(_ cookies: [SavedCookie]) {
    guard let data = try? JSONEncoder().encode(cookies) else { return }
    try? data.write(to: cookieJarURL)
}

@MainActor
func captureAndPersistCookies() async -> Bool {
    await withCheckedContinuation { cont in
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            let relevant = cookies.filter { $0.domain.contains("claude.ai") || $0.domain.contains("anthropic.com") }
            guard !relevant.isEmpty else { cont.resume(returning: false); return }
            persistCookies(relevant.map { SavedCookie(name: $0.name, value: $0.value, domain: $0.domain) })
            cont.resume(returning: true)
        }
    }
}

func isAuthenticated() -> Bool { !loadSavedCookies().isEmpty }

func savedOrgId() -> String? {
    loadSavedCookies().first(where: { $0.name == "lastActiveOrg" })?.value
}

// MARK: - URLSession API client

private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

private func makeRequest(_ path: String) -> URLRequest? {
    let jar = loadSavedCookies()
    guard !jar.isEmpty, let url = URL(string: "https://claude.ai\(path)") else { return nil }
    var req = URLRequest(url: url)
    req.setValue(jar.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    return req
}

struct NotAuthenticated: Error {}
struct HTTPError: Error { let status: Int; let body: String }

private func apiGet(_ path: String) async throws -> Any {
    guard let req = makeRequest(path) else { throw NotAuthenticated() }
    let (data, resp) = try await URLSession.shared.data(for: req)
    if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
        throw HTTPError(status: http.statusCode, body: String(data: data, encoding: .utf8)?.prefix(400).description ?? "")
    }
    return try JSONSerialization.jsonObject(with: data)
}

func fetchOrganizations() async throws -> [[String: Any]] {
    guard let arr = try await apiGet("/api/organizations") as? [[String: Any]] else { throw NotAuthenticated() }
    return arr
}

func resolveOrgId() async throws -> String {
    if let cached = savedOrgId() { return cached }
    let orgs = try await fetchOrganizations()
    if let chat = orgs.first(where: { ($0["capabilities"] as? [String])?.contains("chat") == true }),
       let id = chat["uuid"] as? String { return id }
    guard let id = orgs.first?["uuid"] as? String else { throw NotAuthenticated() }
    return id
}

struct ConvSummary: Sendable { let id: String; let updatedAt: String? }

func fetchConversationSummaries(orgId: String) async throws -> [ConvSummary] {
    var all: [ConvSummary] = []
    var offset = 0
    let limit = 100
    while true {
        let res = try await apiGet("/api/organizations/\(orgId)/chat_conversations?limit=\(limit)&offset=\(offset)")
        guard let arr = res as? [[String: Any]], !arr.isEmpty else { break }
        all.append(contentsOf: arr.compactMap {
            guard let id = $0["uuid"] as? String else { return nil }
            return ConvSummary(id: id, updatedAt: $0["updated_at"] as? String)
        })
        if arr.count < limit { break }
        offset += arr.count
        if offset > 500_000 { break }
    }
    return all
}

func fetchConversationDetail(orgId: String, id: String) async throws -> Conversation? {
    let res = try await apiGet("/api/organizations/\(orgId)/chat_conversations/\(id)?tree=True&rendering_mode=raw")
    guard let dict = res as? [String: Any] else { return nil }
    return conversation(fromClaudeDict: dict)
}

// MARK: - Login window (AppKit, mirrors ConnectWindowController in ClaudeUsageMonitor)

@MainActor
final class LoginWindowController: NSObject, WKNavigationDelegate {
    static let shared = LoginWindowController()
    private var window: NSWindow?
    var onDone: (() -> Void)?

    func show() {
        if window?.isVisible == true { window?.makeKeyAndOrderFront(nil); return }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let w: CGFloat = 960, h: CGFloat = 720, bar: CGFloat = 50
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: w, height: h - bar), configuration: config)
        wv.navigationDelegate = self
        wv.autoresizingMask = [.width, .height]

        let barView = NSView(frame: NSRect(x: 0, y: h - bar, width: w, height: bar))
        barView.autoresizingMask = [.width, .minYMargin]
        barView.wantsLayer = true
        barView.layer?.backgroundColor = NSColor(calibratedRed: 0.059, green: 0.047, blue: 0.161, alpha: 1).cgColor

        let btn = NSButton(title: "Done — I'm logged in", target: self, action: #selector(doneTapped))
        btn.bezelStyle = .rounded
        btn.frame = NSRect(x: 12, y: 10, width: 172, height: 30)

        let lbl = NSTextField(labelWithString: "Log into claude.ai, then click Done. Strata will sync all your conversations automatically.")
        lbl.frame = NSRect(x: 196, y: 4, width: w - 208, height: 42)
        lbl.textColor = .white
        lbl.font = .systemFont(ofSize: 11)
        lbl.autoresizingMask = [.width]

        barView.addSubview(btn)
        barView.addSubview(lbl)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        container.addSubview(wv)
        container.addSubview(barView)

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                           styleMask: [.titled, .closable, .resizable, .miniaturizable],
                           backing: .buffered, defer: false)
        win.title = "Connect to claude.ai — Strata"
        win.isReleasedWhenClosed = false   // prevent dangling pointer under ARC
        win.contentView = container
        win.center()
        win.makeKeyAndOrderFront(nil)
        self.window = win

        NSApp.activate(ignoringOtherApps: true)
        wv.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
    }

    @objc private func doneTapped() {
        window?.close()
        window = nil
        Task { @MainActor in
            let ok = await captureAndPersistCookies()
            if ok { onDone?() }
            else {
                let alert = NSAlert()
                alert.messageText = "No claude.ai cookies found"
                alert.informativeText = "Make sure you're fully logged in to claude.ai, then try again."
                alert.runModal()
                self.show()
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}
}
