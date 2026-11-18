// Focus — Super Smart Search (SSS).
//
// One key from anywhere, a few letters, Return: the exact window or browser tab comes forward.
//
// What it reads, and how:
//   · Every open window of every app — the Accessibility API (names, and bringing one forward). Needs the
//     Accessibility permission; without it SSS still lists the open apps.
//   · Every tab in Safari and the Chrome family — each browser's own scripting (name, address, switch to it).
//     macOS asks once per browser ("Focus wants to control Google Chrome").
//   · How recently each was used — the window server's front-to-back order (no permission needed).
// Nothing is stored and nothing leaves the Mac: the list is rebuilt each time the search opens.
//
// KNOWN GAPS (stated, not hidden): Firefox and Arc have no tab scripting SSS can use, so they give windows only
// (a Firefox window is named after its current tab). Tabs inside other apps (Terminal, editors) are found by their
// window's name only.
import AppKit
import SwiftUI
import ApplicationServices
import Carbon.HIToolbox

// MARK: one thing you can jump to

struct SSSItem: Identifiable, Equatable {
    enum Kind: Int { case tab, window, app }
    var id: String
    var kind: Kind
    var title: String                                           // the window's or tab's name
    var app: String                                             // the app's name
    var bundle: String
    var pid: pid_t
    var path: String                                            // the app's bundle, for its icon
    var url = ""                                                // tabs: the address
    var window = 0                                              // tabs: the browser's own id for the window
    var tab = 0                                                 // tabs: its place in that window, from 1
    var order = 0                                               // 0 = in front right now; larger = used longer ago
    /// The address without its scheme, "www." or path: what people call the site.
    var host: String {
        guard let h = URLComponents(string: url)?.host else { return "" }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }
}

// MARK: the search — pure, so it can be tested without opening anything

enum SSSRank {
    static func fold(_ s: String) -> String { s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil).lowercased() }
    /// The words of a name: split at anything that isn't a letter or digit, and at camelCase humps (so "GitHub" also
    /// answers to "hub").
    static func words(_ s: String) -> [String] {
        var out: [String] = [], cur = "", prevLower = false
        for ch in s {
            if ch.isLetter || ch.isNumber {
                if ch.isUppercase && prevLower && !cur.isEmpty { out.append(cur); cur = "" }
                cur.append(ch); prevLower = ch.isLowercase
            } else { if !cur.isEmpty { out.append(cur); cur = "" }; prevLower = false }
        }
        if !cur.isEmpty { out.append(cur) }
        var folded = out.map(fold)
        let whole = fold(s).split { !($0.isLetter || $0.isNumber) }.map(String.init)       // "github" as one word too
        for w in whole where !folded.contains(w) { folded.append(w) }
        return folded
    }
    /// Edits between two short words (insert, delete, replace, or two neighbours swapped), stopping early past `limit`.
    static func edits(_ a: String, _ b: String, limit: Int) -> Int {
        let x = Array(a), y = Array(b)
        if abs(x.count - y.count) > limit { return limit + 1 }
        if x.isEmpty { return y.count }; if y.isEmpty { return x.count }
        var prev2 = [Int](repeating: 0, count: y.count + 1), prev = Array(0...y.count), cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i; var low = cur[0]
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                if i > 1, j > 1, x[i - 1] == y[j - 2], x[i - 2] == y[j - 1] { cur[j] = min(cur[j], prev2[j - 2] + 1) }
                low = min(low, cur[j])
            }
            if low > limit { return limit + 1 }
            prev2 = prev; prev = cur
        }
        return prev[y.count]
    }
    /// How well one typed word fits one name (0 = not at all, 100 = it is one of its words).
    static func fit(_ t: String, _ ws: [String]) -> Double {
        var best = 0.0
        let n = t.count, slack = n >= 8 ? 2 : n >= 4 ? 1 : 0
        for (i, w) in ws.enumerated() {
            let late = Double(min(i, 8)) * 0.5                                  // earlier words count a little more
            if w == t { best = max(best, 100 - late) }
            else if w.hasPrefix(t) { best = max(best, 88 - late - Double(min(w.count - n, 10)) * 0.3) }
            else if n >= 2, w.contains(t) { best = max(best, 66 - late) }
            else if slack > 0, best < 52 {                                      // a slip of the fingers
                if edits(t, w, limit: slack) <= slack || (w.count > n && edits(t, String(w.prefix(n)), limit: slack) <= slack) { best = max(best, 52 - late) }
            }
        }
        if best < 72, n >= 2 {                                                  // initials: "gpr" for GitHub Pull Requests
            let initials = String(ws.compactMap(\.first))
            if initials.contains(t) { best = max(best, 72) }
        }
        if best == 0, n >= 3 {                                                  // letters in order, starting a word, close together
            for w in ws where w.first == t.first {
                var it = t.makeIterator(), want = it.next(), span = 0, done = false
                for ch in w { span += 1; if ch == want { want = it.next(); if want == nil { done = true; break } } }
                if done, span <= n * 2 { best = max(best, 40); break }
            }
        }
        return best
    }
    /// The whole query against one item: every typed word must fit somewhere (its name, its app, its address).
    static func score(_ query: String, _ item: SSSItem) -> Double? {
        let tokens = fold(query).split { !($0.isLetter || $0.isNumber) }.map(String.init)
        guard !tokens.isEmpty else { return 0 }
        let title = words(item.title), app = words(item.app), host = words(item.host)
        let rest = words(item.url.replacingOccurrences(of: item.host, with: " "))
        var total = 0.0
        for t in tokens {
            let s = max(fit(t, title), fit(t, app) * 0.9, fit(t, host) * 0.85, fit(t, rest) * 0.5)
            if s == 0 { return nil }
            total += s
        }
        var out = total / Double(tokens.count)
        let q = fold(query).trimmingCharacters(in: .whitespaces)
        if q.count >= 3, fold(item.title).contains(q) { out += 12 }             // typed as it's written
        out += max(0, 8 - Double(item.order) * 0.4)                             // what you used last, first
        if item.kind == .app { out -= 4 }
        return out
    }
    static func search(_ query: String, in items: [SSSItem]) -> [SSSItem] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty { return items.sorted { $0.order < $1.order } }
        return items.compactMap { i in score(query, i).map { (i, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.order < $1.0.order }.map(\.0)
    }
    /// The parts of a name the query touched, to show brighter.
    static func marks(_ query: String, in title: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        for t in query.split(whereSeparator: { !($0.isLetter || $0.isNumber) }) {
            if let r = title.range(of: String(t), options: [.caseInsensitive, .diacriticInsensitive]) { out.append(r) }
        }
        return out.sorted { $0.lowerBound < $1.lowerBound }
    }
}

// MARK: reading the Mac

@_silgen_name("_AXUIElementCreateWithRemoteToken")
private func _AXUIElementCreateWithRemoteToken(_ data: CFData) -> Unmanaged<AXUIElement>?

final class SSSIndex {
    static let shared = SSSIndex()
    /// Renders and tests search this instead of the real Mac.
    static var fixture: [SSSItem]?
    private(set) var items: [SSSItem] = []
    private var elements: [String: AXUIElement] = [:]           // a window item's id → the window itself
    private let work = DispatchQueue(label: "focus.sss", qos: .userInitiated)
    private var busy = false, again: [() -> Void] = []
    /// Browsers that are open but haven't been allowed yet (or were refused): their tabs can't be read.
    private(set) var tabsWaiting: [String] = []

    static let chromium = ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "com.brave.Browser",
                           "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "org.chromium.Chromium"]
    static let safari = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    static var windowsAllowed: Bool { AXIsProcessTrusted() }
    /// The one deliberate ask for Accessibility: macOS shows its own prompt, with a button to System Settings.
    static func askWindows() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
    /// Whether Focus may script this browser: 0 yes, -1744 not asked yet, -1743 refused. `ask` shows macOS's prompt.
    static func automation(_ bundle: String, ask: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundle)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
    }
    /// Asks for each open browser in turn, then re-reads.
    func askTabs(_ done: @escaping () -> Void) {
        let waiting = tabsWaiting
        DispatchQueue.global(qos: .userInitiated).async {
            for b in waiting { _ = SSSIndex.automation(b, ask: true) }
            DispatchQueue.main.async { self.refresh(done) }
        }
    }

    /// Runs a script with a time limit, off the main thread. Returns what it printed, or nil.
    static func script(_ source: String, limit: TimeInterval = 3) -> String? {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-e", source]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + limit) { if p.isRunning { p.terminate() } }
        let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return p.terminationStatus == 0 ? String(data: data, encoding: .utf8) : nil
    }
    static func tabScript(_ bundle: String) -> String {
        let chrome = !safari.contains(bundle)
        return """
        tell application id "\(bundle)"
        set o to ""
        set us to ASCII character 31
        set rs to ASCII character 30
        set k to 0
        repeat with w in windows
        set k to k + 1
        try
        set wid to id of w
        set a to \(chrome ? "active tab index of w" : "index of current tab of w")
        set ts to \(chrome ? "title" : "name") of tabs of w
        set ls to URL of tabs of w
        repeat with i from 1 to count of ts
        set u to ""
        try
        set u to (item i of ls) as text
        end try
        set o to o & wid & us & k & us & i & us & (i = a) & us & (item i of ts) & us & u & rs
        end repeat
        end try
        end repeat
        return o
        end tell
        """
    }
    /// One browser's answer → its tabs. Each record: window id, window place, tab place, is-current, name, address.
    static func parseTabs(_ text: String, app: String, bundle: String, pid: pid_t, path: String, front: Int) -> [SSSItem] {
        text.split(separator: "\u{1E}").compactMap { rec in
            let p = rec.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
            guard p.count >= 6, let wid = Int(p[0]), let k = Int(p[1]), let i = Int(p[2]) else { return nil }
            let current = p[3].trimmingCharacters(in: .whitespacesAndNewlines) == "true"
            let title = p[4].trimmingCharacters(in: .whitespacesAndNewlines)
            return SSSItem(id: "t:\(bundle):\(wid):\(i)", kind: .tab, title: title.isEmpty ? p[5] : title, app: app, bundle: bundle, pid: pid, path: path,
                           url: p[5].trimmingCharacters(in: .whitespacesAndNewlines), window: wid, tab: i,
                           order: current ? front + (k - 1) : front + 20 + (k - 1) * 3)   // a window's current tab ranks as the window does
        }
    }

    /// A window's name without its app's name on the end ("Inbox - Google Chrome" → "Inbox"): the row already says the app.
    static func plainTitle(_ title: String, app: String) -> String {
        for dash in [" - ", " – ", " — "] where title.hasSuffix(dash + app) && title.count > (dash + app).count { return String(title.dropLast((dash + app).count)) }
        return title.isEmpty ? app : title
    }
    private struct AppInfo { let pid: pid_t, bundle: String, name: String, path: String }
    private static func string(_ el: AXUIElement, _ attr: String) -> String {
        var v: CFTypeRef?; return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? (v as? String ?? "") : ""
    }
    private static func frame(_ el: AXUIElement) -> CGRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &s) == .success,
              let pv = p, let sv = s, CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &pt); AXValueGetValue(sv as! AXValue, .cgSize, &sz)
        return CGRect(origin: pt, size: sz)
    }
    /// An app's windows. The ordinary list leaves out windows on other desktops (Spaces), so when the window server
    /// shows more than Accessibility returned, the rest are found by asking for each element in turn (0.12 s at most).
    private static func windows(of pid: pid_t, expecting: Int) -> [AXUIElement] {
        let appEl = AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(appEl, 0.3)
        var v: CFTypeRef?
        var found = AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &v) == .success ? (v as? [AXUIElement] ?? []) : []
        guard found.count < expecting else { return found }
        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f_636f)) { Data($0) })
        let began = Date()
        for n in 0..<1000 where Date().timeIntervalSince(began) < 0.12 {
            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: UInt64(n)) { Data($0) })
            guard let el = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue() else { continue }
            AXUIElementSetMessagingTimeout(el, 0.1)
            let sub = string(el, kAXSubroleAttribute)
            if sub == "AXStandardWindow" || sub == "AXDialog", !found.contains(where: { CFEqual($0, el) }) { found.append(el) }
        }
        return found
    }

    /// Re-reads everything, off the main thread, then calls back on it.
    func refresh(_ done: @escaping () -> Void = {}) {
        if SSSIndex.fixture != nil { items = SSSIndex.fixture!; done(); return }
        if busy { again.append(done); return }
        busy = true
        let me = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != me }
            .compactMap { a -> AppInfo? in
                guard let url = a.bundleURL else { return nil }
                return AppInfo(pid: a.processIdentifier, bundle: a.bundleIdentifier ?? url.lastPathComponent, name: a.localizedName ?? url.deletingPathExtension().lastPathComponent, path: url.path)
            }
        let trusted = SSSIndex.windowsAllowed
        work.async {
            // Front to back, every desktop: who owns each ordinary window, and where it is.
            let cg = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
            let onScreen = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
            func plain(_ list: [[String: Any]]) -> [(pid: pid_t, rect: CGRect, titled: Bool)] {
                list.compactMap { w in
                    guard (w[kCGWindowLayer as String] as? Int) == 0, let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                          let b = w[kCGWindowBounds as String] as? [String: CGFloat], (b["Width"] ?? 0) > 60, (b["Height"] ?? 0) > 60 else { return nil }
                    return (pid, CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0), !((w[kCGWindowName as String] as? String) ?? "").isEmpty)
                }
            }
            let stack = plain(onScreen), all = plain(cg)
            func place(_ pid: pid_t, _ r: CGRect?) -> Int? {
                guard let r else { return nil }
                return stack.firstIndex { $0.pid == pid && abs($0.rect.minX - r.minX) < 2 && abs($0.rect.minY - r.minY) < 2 && abs($0.rect.width - r.width) < 2 }
            }
            var out: [SSSItem] = [], els: [String: AXUIElement] = [:], waiting: [String] = []
            let lock = NSLock(), group = DispatchGroup()
            for (rank, app) in apps.enumerated() {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    defer { group.leave() }
                    let front = stack.firstIndex { $0.pid == app.pid } ?? (300 + rank)
                    var mine: [SSSItem] = [], myEls: [String: AXUIElement] = [:]
                    // Tabs, from the browser itself.
                    var tabs: [SSSItem] = []
                    if SSSIndex.chromium.contains(app.bundle) || SSSIndex.safari.contains(app.bundle) {
                        if SSSIndex.automation(app.bundle, ask: false) == noErr, let text = SSSIndex.script(SSSIndex.tabScript(app.bundle)) {
                            tabs = SSSIndex.parseTabs(text, app: app.name, bundle: app.bundle, pid: app.pid, path: app.path, front: front)
                        } else { lock.lock(); waiting.append(app.bundle); lock.unlock() }
                    }
                    let current = tabs.filter { $0.order < front + 20 }.map(\.title).filter { !$0.isEmpty }
                    // Windows, from Accessibility.
                    if trusted {
                        let expecting = max(all.filter { $0.pid == app.pid && $0.titled }.count, all.filter { $0.pid == app.pid }.isEmpty ? 0 : 1)
                        for (n, w) in SSSIndex.windows(of: app.pid, expecting: expecting).enumerated() {
                            let sub = SSSIndex.string(w, kAXSubroleAttribute), title = SSSIndex.string(w, kAXTitleAttribute)
                            guard sub == "AXStandardWindow" || (sub == "AXDialog" && !title.isEmpty) else { continue }
                            if current.contains(where: { title.hasPrefix($0) }) { continue }        // a browser window already listed as its current tab
                            let id = "w:\(app.pid):\(n):\(title)"
                            mine.append(SSSItem(id: id, kind: .window, title: SSSIndex.plainTitle(title, app: app.name), app: app.name, bundle: app.bundle, pid: app.pid, path: app.path,
                                                order: place(app.pid, SSSIndex.frame(w)) ?? (front + 40 + n)))
                            myEls[id] = w
                        }
                    }
                    if mine.isEmpty && tabs.isEmpty {                            // no window to name: the app itself
                        mine.append(SSSItem(id: "a:\(app.pid)", kind: .app, title: app.name, app: app.name, bundle: app.bundle, pid: app.pid, path: app.path, order: front))
                    }
                    lock.lock(); out += mine + tabs; els.merge(myEls) { a, _ in a }; lock.unlock()
                }
            }
            group.wait()
            DispatchQueue.main.async {
                self.items = out; self.elements = els; self.tabsWaiting = waiting.sorted(); self.busy = false
                done()
                if !self.again.isEmpty { let next = self.again; self.again = []; self.refresh { next.forEach { $0() } } }
            }
        }
    }

    // MARK: going there

    private static func raise(_ w: AXUIElement) {
        AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementPerformAction(w, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
    }
    private static func bringForward(_ pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        if app.isHidden { app.unhide() }
        if #available(macOS 14.0, *) { NSApp.yieldActivation(to: app) }
        app.activate(options: [])
    }
    static func openScript(_ item: SSSItem) -> String {
        SSSIndex.safari.contains(item.bundle)
            ? "tell application id \"\(item.bundle)\"\nset w to window id \(item.window)\nset current tab of w to tab \(item.tab) of w\nset index of w to 1\nend tell"
            : "tell application id \"\(item.bundle)\"\nset active tab index of window id \(item.window) to \(item.tab)\nset index of window id \(item.window) to 1\nend tell"
    }
    /// Brings the item forward: the tab is chosen in its browser, the window raised, the app made active.
    func open(_ item: SSSItem) {
        guard SSSIndex.fixture == nil else { return }
        switch item.kind {
        case .tab:
            let source = SSSIndex.openScript(item)
            let trusted = SSSIndex.windowsAllowed
            work.async {
                _ = SSSIndex.script(source)
                if trusted {                                              // and the browser's window itself, over its other windows
                    let wins = SSSIndex.windows(of: item.pid, expecting: 0)
                    if let w = wins.first(where: { !item.title.isEmpty && SSSIndex.string($0, kAXTitleAttribute).hasPrefix(item.title) }) { SSSIndex.raise(w) }
                }
                DispatchQueue.main.async { SSSIndex.bringForward(item.pid) }
            }
        case .window:
            if let w = elements[item.id] { SSSIndex.raise(w) }
            SSSIndex.bringForward(item.pid)
        case .app:
            SSSIndex.bringForward(item.pid)
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: item.path), configuration: NSWorkspace.OpenConfiguration())   // an app with no window opens one
        }
    }
}

// MARK: the mark — "IQ", where the Q is the magnifying glass

enum SSSGlyph {
    /// The mark in a box (drawn for 30 × 22, y downwards): an I with its serifs, then a ring whose tail is a handle.
    static func path(in r: CGRect) -> CGPath {
        let p = CGMutablePath(), w = r.width, h = r.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * w, y: r.minY + y * h) }
        p.move(to: pt(0.14, 0.14)); p.addLine(to: pt(0.14, 0.80))
        p.move(to: pt(0.04, 0.14)); p.addLine(to: pt(0.24, 0.14))
        p.move(to: pt(0.04, 0.80)); p.addLine(to: pt(0.24, 0.80))
        let c = pt(0.60, 0.47), rad = 0.33 * h, k: CGFloat = 0.7071
        p.addEllipse(in: CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2))
        p.move(to: CGPoint(x: c.x + rad * k * 0.7, y: c.y + rad * k * 0.7))
        p.addLine(to: CGPoint(x: c.x + rad * k + 0.29 * h, y: c.y + rad * k + 0.29 * h))
        return p
    }
    /// For the menu: a template image, so macOS colours it like the menu's other symbols.
    static func image(height: CGFloat = 13) -> NSImage {
        let size = NSSize(width: (height * 30 / 22).rounded(), height: height)
        let im = NSImage(size: size, flipped: true) { r in
            guard let g = NSGraphicsContext.current?.cgContext else { return false }
            g.addPath(path(in: r.insetBy(dx: 0.8, dy: 0.8))); g.setLineWidth(max(1.2, height * 0.11)); g.setLineCap(.round); g.setLineJoin(.round)
            g.setStrokeColor(NSColor.black.cgColor); g.strokePath(); return true
        }
        im.isTemplate = true; return im
    }
}
struct SSSGlyphShape: Shape { func path(in rect: CGRect) -> Path { Path(SSSGlyph.path(in: rect)) } }

/// The mark, in whatever colour the text around it is. `draws`: it writes itself when it appears.
struct SSSLogo: View {
    var height: CGFloat = 15
    var draws = false
    @State private var t: CGFloat = 1
    var body: some View {
        SSSGlyphShape().trim(from: 0, to: t)
            .stroke(style: StrokeStyle(lineWidth: max(1.2, height * 0.105), lineCap: .round, lineJoin: .round))
            .frame(width: height * 30 / 22, height: height)
            .onAppear {
                guard draws, !renderArgs.contains(where: { $0.hasPrefix("--render") || $0.hasPrefix("--selftest") }), !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                t = 0; withAnimation(.easeOut(duration: 0.55)) { t = 1 }
            }
    }
}

// MARK: what the search shows — one bar. No list, unless Tab asks for one.

/// The colours of the bar: black, always, when it floats over the Mac; the window's own look on its page in Focus.
struct SSSLook {
    let ground: Color, edge: Color, ink: Color, low: Color, muted: Color, line: Color, chosen: Color, hover: Color, nsInk: NSColor
    static let bar = SSSLook(ground: .black, edge: Color.white.opacity(0.18), ink: .white, low: Site.hex(0xD0D1D2), muted: Site.hex(0x8E8E8E),
                             line: Site.hex(0x2A2A2A), chosen: Site.hex(0x232323), hover: Site.hex(0x1A1A1A), nsInk: .white)
    static var page: SSSLook { SSSLook(ground: Site.surface, edge: Site.line, ink: Site.head, low: Site.low, muted: Site.muted, line: Site.line,
                                       chosen: Site.surface2, hover: Site.surface2.opacity(0.6), nsInk: Site.light ? .black : .white) }
}

final class SSSModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { update(reset: true) } } }
    @Published var results: [SSSItem] = []
    @Published var selected = 0
    @Published var open = false                                 // the dropdown: only after Tab (or an arrow)
    @Published var shown = false                                // the bar has arrived
    @Published var shakes = 0                                   // Return with nothing to find: the bar shakes its head
    @Published var focus = 0                                    // bumped to put the caret back in the field
    @Published var tick = 0
    var limit = 6
    var emptyGoes = true                                        // nothing typed + Return: the window used before this one
    var onPick: (SSSItem) -> Void = { _ in }
    var onCancel: () -> Void = {}
    var moved = false                                           // the arrows were used: a fresh list leaves the chosen row alone
    private var icons: [String: NSImage] = [:]
    func icon(_ path: String) -> NSImage {
        if let i = icons[path] { return i }
        let i = NSWorkspace.shared.icon(forFile: path); i.size = NSSize(width: 64, height: 64); icons[path] = i; return i
    }
    /// Whether there is something to go to for what's typed (the mark dims when there isn't).
    var match: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty || !results.isEmpty }
    func update(reset: Bool) {
        results = Array(SSSRank.search(query, in: SSSIndex.shared.items).prefix(limit))
        // Nothing typed: most recent first, and the choice starts on the one before this one.
        if reset { selected = query.isEmpty && results.count > 1 ? 1 : 0; moved = false }
        selected = min(selected, max(0, results.count - 1))
    }
    func reload() { SSSIndex.shared.refresh { [weak self] in guard let self else { return }; self.update(reset: !self.moved); self.tick &+= 1 } }
    /// Tab (or an arrow): the first press opens the dropdown on the best guess; after that it moves the choice.
    func tab(_ by: Int) {
        if !open { withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) { open = true }; return }
        guard !results.isEmpty else { return }
        moved = true; selected = (selected + by + results.count) % results.count
    }
    func submit() {
        let empty = query.trimmingCharacters(in: .whitespaces).isEmpty
        if results.indices.contains(selected), !(empty && !emptyGoes && !open) { onPick(results[selected]) }
        else if !empty { withAnimation(.linear(duration: 0.38)) { shakes += 1 } }
    }
}

struct SSSShake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform { ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0)) }
}

func sssFont(_ base: CGFloat, medium: Bool = false) -> NSFont {
    let size = (base * Site.standard * Site.scale).rounded()
    return NSFont(name: medium ? "Graphik-Medium" : "Graphik-Regular", size: size) ?? NSFont(name: medium ? "HelveticaNeue-Medium" : "HelveticaNeue", size: size) ?? .systemFont(ofSize: size)
}

/// The field itself: a plain line of text that hands Tab, the arrows, Return and Esc to the search.
struct SSSField: NSViewRepresentable {
    @ObservedObject var s: SSSModel
    let ink: NSColor
    func makeCoordinator() -> Keys { Keys(s) }
    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField()
        f.isBordered = false; f.drawsBackground = false; f.focusRingType = .none; f.usesSingleLineMode = true
        f.cell?.wraps = false; f.cell?.isScrollable = true; f.font = sssFont(22); f.textColor = ink; f.delegate = context.coordinator
        f.setContentHuggingPriority(.defaultLow, for: .horizontal); f.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return f
    }
    func updateNSView(_ f: NSTextField, context: Context) {
        if f.stringValue != s.query { f.stringValue = s.query }
        f.textColor = ink
        if context.coordinator.focus != s.focus {
            context.coordinator.focus = s.focus
            DispatchQueue.main.async { f.window?.makeFirstResponder(f); (f.currentEditor() as? NSTextView)?.insertionPointColor = ink }
        }
    }
    final class Keys: NSObject, NSTextFieldDelegate {
        let s: SSSModel; var focus = -1
        init(_ s: SSSModel) { self.s = s }
        func controlTextDidChange(_ n: Notification) { if let f = n.object as? NSTextField { s.query = f.stringValue } }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.moveDown(_:)): s.tab(1); return true
            case #selector(NSResponder.insertBacktab(_:)), #selector(NSResponder.moveUp(_:)): s.tab(-1); return true
            case #selector(NSResponder.insertNewline(_:)): s.submit(); return true
            case #selector(NSResponder.cancelOperation(_:)): s.onCancel(); return true
            default: return false
            }
        }
    }
}

/// A name with the typed parts brighter.
struct SSSTitle: View {
    let text: String, query: String, on: Bool, look: SSSLook
    var body: some View {
        let marks = SSSRank.marks(query, in: text), base = on || marks.isEmpty ? look.ink : look.low
        var out = AttributedString(), at = text.startIndex
        func piece(_ t: Substring, _ bright: Bool) {
            var a = AttributedString(String(t)); a.foregroundColor = bright ? look.ink : base; a.font = Site.font(17, bright ? .medium : .regular); out += a
        }
        for r in marks where r.lowerBound >= at { piece(text[at..<r.lowerBound], false); piece(text[r], true); at = r.upperBound }
        piece(text[at...], false)
        return Text(out).lineLimit(1).truncationMode(.tail)
    }
}

struct SSSRow: View {
    let item: SSSItem, icon: NSImage, query: String, on: Bool, look: SSSLook, pick: () -> Void
    @State private var hover = false
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: 26, height: 26)
            SSSTitle(text: item.title, query: query, on: on, look: look)
            Spacer(minLength: 12)
            let place = item.kind == .tab && !item.host.isEmpty ? item.host : item.app
            Text(place.count > 32 ? place.prefix(31) + "…" : place).font(Site.font(15)).foregroundColor(look.muted).lineLimit(1)
                .fixedSize().layoutPriority(1)                                  // the site is short: a long name gives way first
            Image(systemName: "return").font(.system(size: 11, weight: .medium)).foregroundColor(look.muted).opacity(on ? 1 : 0).frame(width: 16)   // Return goes here
        }
        .padding(.horizontal, 14).frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? look.chosen : hover ? look.hover : Color.clear))
        .contentShape(Rectangle()).onHover { hover = $0 }.onTapGesture(perform: pick)
    }
}

/// The bar: the mark, the field. Under it, only once Tab has asked, the few things it could mean.
struct SSSBar: View {
    @ObservedObject var s: SSSModel
    let look: SSSLook
    var radius: CGFloat = 16
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                SSSLogo(height: 20, draws: true).foregroundColor(look.ink).opacity(s.match ? 1 : 0.35).animation(.easeOut(duration: 0.18), value: s.match)
                    .id(s.focus)                                                // it writes itself each time the bar opens
                SSSField(s: s, ink: look.nsInk).frame(height: 30)
            }
            .padding(.horizontal, 20).frame(height: 60)
            if s.open {
                Rectangle().fill(look.line).frame(height: 1)
                if s.results.isEmpty {
                    Text("Nothing open matches.").font(Site.font(16)).foregroundColor(look.muted).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20).frame(height: 50)
                } else {
                    VStack(spacing: 2) {
                        ForEach(Array(s.results.enumerated()), id: \.element.id) { i, item in
                            SSSRow(item: item, icon: s.icon(item.path), query: s.query, on: i == s.selected, look: look) { s.onPick(item) }
                        }
                    }.padding(6)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(look.ground))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(look.edge, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .modifier(SSSShake(animatableData: CGFloat(s.shakes)))
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: s.results.count)
    }
}

// MARK: the floating bar — the shortcut (or the menu) opens it over whatever is in front

final class SSSPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The bar's arrival and leaving: it settles in from slightly small, and lifts away towards what it found.
struct SSSStage: View {
    @ObservedObject var s: SSSModel
    var body: some View {
        SSSBar(s: s, look: .bar).frame(width: SSSController.width)
            .shadow(color: .black.opacity(0.55), radius: 30, y: 16)
            .scaleEffect(s.shown ? 1 : 0.965, anchor: .top).opacity(s.shown ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 10)
            .preferredColorScheme(.dark)
    }
}

final class SSSController: NSObject, NSWindowDelegate {
    static let shared = SSSController()
    static let width: CGFloat = 640
    let model = SSSModel()
    private var panel: SSSPanel?
    private var leaving = false
    var onHide: (() -> Void)?                                   // the stand-alone try-out quits when the bar goes
    var shown: Bool { panel?.isVisible == true && !leaving }
    private var still: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func toggle() { if shown { hide() } else { show() } }
    func show() {
        let height = 60 + CGFloat(model.limit) * 44 + 14 + 90                 // the dropdown at its tallest, and room for the shadow
        if panel == nil {
            let p = SSSPanel(contentRect: NSRect(x: 0, y: 0, width: SSSController.width + 100, height: height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.level = .modalPanel
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]; p.hidesOnDeactivate = false; p.isReleasedWhenClosed = false
            p.appearance = NSAppearance(named: .darkAqua); p.delegate = self
            p.contentView = NSHostingView(rootView: SSSStage(s: model))
            model.onPick = { [weak self] item in self?.go(item) }
            model.onCancel = { [weak self] in self?.hide() }
            panel = p
        }
        guard let p = panel else { return }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let v = screen?.visibleFrame {                                       // a little above the middle, where the eye already is
            p.setFrameOrigin(NSPoint(x: v.midX - p.frame.width / 2, y: v.maxY - v.height * 0.28 - p.frame.height))
        }
        leaving = false
        model.open = false; model.query = ""; model.update(reset: true); model.shown = false; model.focus &+= 1
        p.makeKeyAndOrderFront(nil); p.orderFrontRegardless()
        if still { model.shown = true } else { withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) { model.shown = true } }
        model.reload()                                                          // what was there last time is ready at once; the fresh list follows
    }
    /// Fades the bar out, then takes the panel away.
    private func leave(_ after: @escaping () -> Void = {}) {
        guard panel?.isVisible == true, !leaving else { return }
        leaving = true
        if still { model.shown = false } else { withAnimation(.easeIn(duration: 0.12)) { model.shown = false } }
        DispatchQueue.main.asyncAfter(deadline: .now() + (still ? 0 : 0.13)) { [weak self] in
            guard let self else { return }
            self.panel?.orderOut(nil); self.leaving = false; after()
        }
    }
    func hide() { leave { [weak self] in self?.onHide?() } }
    func go(_ item: SSSItem) {
        SSSIndex.shared.open(item)                                              // at once: the bar is already leaving
        leave { [weak self] in DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self?.onHide?() } }
    }
    func windowDidResignKey(_ notification: Notification) { hide() }             // a click anywhere else puts it away
}

// MARK: the shortcut and the menu

extension Focus {
    /// Super Smart Search: ⌘⇧S by default (his choice, 2026-11-18), beside ⌘⇧F for sessions and ⌘⇧E for this app.
    var sssMods: Int { get { store.object(forKey: "sssModsS") as? Int ?? modifierChoices[0].mods } set { store.set(newValue, forKey: "sssModsS"); applyShortcuts() } }
    var sssKey: String { label(sssMods) + "S" }
    /// The menu's line: the same thing the shortcut opens (once the menu has closed).
    @objc func openSSS() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { SSSController.shared.show() } }
    @objc func pickSSSKey(_ s: NSMenuItem) { sssMods = s.tag }
}

// MARK: its page in the desktop app — the header, the bar, one line

struct SSSPage: View {
    @ObservedObject var m: DesktopModel
    @StateObject private var s = SSSModel()
    var body: some View {
        let _ = s.tick
        PageFrame(title: "Super Smart Search", text: "") {
            SSSBar(s: s, look: .page, radius: 12).padding(.top, 6)
            Text("Type anything — tab name, contents, window — and SSS will find wherever it's running and open it.")
                .font(Site.font(15)).foregroundColor(Site.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 12).padding(.horizontal, 2)
            if !SSSIndex.windowsAllowed && SSSIndex.fixture == nil {
                SettingLine(title: "Windows", note: "Allow Focus in Accessibility, so it can read each window's name and bring it forward.") {
                    SiteButton("Allow…") { SSSIndex.askWindows() }
                }.padding(.top, 14)
            }
            if !SSSIndex.shared.tabsWaiting.isEmpty {
                SettingLine(title: "Browser tabs", note: "Allow Focus to read the tabs open in your browser.") {
                    SiteButton("Allow…") { SSSIndex.shared.askTabs { s.update(reset: false); s.tick &+= 1 } }
                }
            }
        }
        .onAppear {
            s.emptyGoes = false
            s.onPick = { item in SSSIndex.shared.open(item); s.open = false; s.query = "" }
            s.onCancel = { withAnimation(.easeOut(duration: 0.15)) { s.open = false }; s.query = "" }
            if renderArgs.contains("open") { s.open = true }
            if let q = renderArgs.first(where: { $0.hasPrefix("query=") }) { s.query = String(q.dropFirst(6)) }
            s.update(reset: true); s.reload(); s.focus &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in s.reload() }   // back from System Settings
    }
}

// MARK: renders and tests

/// A made-up desk, so pictures and tests never depend on (or show) what is really open.
func sssFixture() -> [SSSItem] {
    let ws = NSWorkspace.shared
    func path(_ id: String) -> String { ws.urlForApplication(withBundleIdentifier: id)?.path ?? "/System/Applications/Utilities/Terminal.app" }
    let browser = ws.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil ? ("Google Chrome", "com.google.Chrome") : ("Safari", "com.apple.Safari")
    func tab(_ n: Int, _ title: String, _ url: String, _ order: Int) -> SSSItem {
        SSSItem(id: "t:\(n)", kind: .tab, title: title, app: browser.0, bundle: browser.1, pid: 1, path: path(browser.1), url: url, window: 1, tab: n, order: order)
    }
    func win(_ n: Int, _ title: String, _ app: String, _ id: String, _ order: Int) -> SSSItem {
        SSSItem(id: "w:\(n)", kind: .window, title: title, app: app, bundle: id, pid: pid_t(n + 1), path: path(id), order: order)
    }
    return [
        win(1, "Focus — sss.swift", "Terminal", "com.apple.Terminal", 0),
        tab(1, "Invoice INV-2041 – Stripe Dashboard", "https://dashboard.stripe.com/invoices/in_1Q", 1),
        tab(2, "Pull requests · Labern/Clean", "https://github.com/Labern/Clean/pulls", 21),
        tab(3, "Café menu ideas – Google Docs", "https://docs.google.com/document/d/1x", 22),
        tab(4, "Checkout — Paradoxica", "https://paradoxica.co.uk/focus/checkout/", 23),
        tab(5, "Weather for London", "https://www.bbc.co.uk/weather/2643743", 24),
        win(2, "Kitten weights 2026", "Notes", "com.apple.Notes", 2),
        win(3, "Downloads", "Finder", "com.apple.finder", 3),
        win(4, "Budget November.numbers", "Numbers", "com.apple.iWork.Numbers", 4),
        win(5, "Screenplay draft 4.pdf", "Preview", "com.apple.Preview", 5),
        SSSItem(id: "a:9", kind: .app, title: "Music", app: "Music", bundle: "com.apple.Music", pid: 9, path: path("com.apple.Music"), order: 6),
    ]
}

/// `Focus --render-sss FILE [query=…] [look=light] [live]`: the floating panel drawn off-screen.
func renderSSS(to file: String) -> NSBitmapImageRep? {
    _ = NSApplication.shared
    let live = renderArgs.contains("live")
    SSSIndex.fixture = live ? nil : sssFixture()
    let s = SSSModel()
    if live {
        var done = false; SSSIndex.shared.refresh { done = true }
        let until = Date().addingTimeInterval(6); while !done && Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    } else { SSSIndex.shared.refresh() }
    s.query = renderArgs.first { $0.hasPrefix("query=") }.map { String($0.dropFirst(6)) } ?? ""
    s.update(reset: true); s.shown = true; s.open = renderArgs.contains("open")
    let size = NSSize(width: SSSController.width + 100, height: 60 + CGFloat(s.limit) * 44 + 104)
    let view = SSSStage(s: s).padding(.top, 20)
        .background(Site.hex(0x4A4A4A))                                         // a mid grey stands in for the desktop behind
    let host = NSHostingView(rootView: view)
    let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    w.appearance = NSAppearance(named: Site.light ? .aqua : .darkAqua); w.contentView = host
    host.frame = NSRect(origin: .zero, size: size); host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
    host.cacheDisplay(in: host.bounds, to: rep)
    if !file.isEmpty { try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: file)) }
    return rep
}

/// `Focus --selftest-sss`: the search itself, on a made-up desk. Opens nothing, reads nothing real, changes no setting.
/// Prints in the stress harness's format so test.sh collects it.
func sssSelfTest() -> Int32 {
    var failures = 0
    func check(_ n: Int, _ name: String, _ ok: Bool, _ detail: String) {
        if !ok { failures += 1 }
        print("stress: \(ok ? "PASS" : "FAIL")  \(n). \(name) — \(detail)")
    }
    let desk = sssFixture()
    func top(_ q: String) -> String { SSSRank.search(q, in: desk).first?.title ?? "(nothing)" }
    func found(_ q: String) -> [String] { SSSRank.search(q, in: desk).map(\.title) }
    check(201, "SSS: a word finds its window", top("budget").hasPrefix("Budget"), top("budget"))
    check(202, "SSS: a typo still finds it", top("invioce").hasPrefix("Invoice") && top("screnplay").hasPrefix("Screenplay"), "invioce → \(top("invioce")); screnplay → \(top("screnplay"))")
    check(203, "SSS: the start of a word is enough", top("kit").hasPrefix("Kitten") && top("down").hasPrefix("Downloads"), "kit → \(top("kit")); down → \(top("down"))")
    check(204, "SSS: words in any order, across name, app and address", top("stripe inv").hasPrefix("Invoice") && top("clean pull").hasPrefix("Pull requests"), "stripe inv → \(top("stripe inv")); clean pull → \(top("clean pull"))")
    check(205, "SSS: a site's name finds a tab whose title doesn't say it", top("github").hasPrefix("Pull requests") && top("bbc").hasPrefix("Weather"), "github → \(top("github")); bbc → \(top("bbc"))")
    check(206, "SSS: accents don't matter", top("cafe").hasPrefix("Café"), top("cafe"))
    check(207, "SSS: initials work", top("sd").hasPrefix("Invoice") || top("sd").hasPrefix("Screenplay"), "sd → \(top("sd"))")
    check(208, "SSS: nonsense finds nothing", found("zzqxv").isEmpty && found("budget zzqxv").isEmpty, "\(found("zzqxv").count) results")
    let all = SSSRank.search("", in: desk)
    check(209, "SSS: nothing typed lists everything, most recent first", all.count == desk.count && all.map(\.order) == all.map(\.order).sorted(), "\(all.count) of \(desk.count)")
    let browser = found("chrome").isEmpty ? "safari" : "chrome"
    check(210, "SSS: an app's name lists all of its tabs", found(browser).count == 5, "\(found(browser).count) for “\(browser)”")
    let rec = "71\u{1F}1\u{1F}1\u{1F}false\u{1F}Inbox\u{1F}https://mail.example.com/\u{1E}71\u{1F}1\u{1F}2\u{1F}true\u{1F}Docs, with a comma\u{1F}https://docs.example.com/a\u{1E}9\u{1F}2\u{1F}1\u{1F}true\u{1F}\u{1F}about:blank\u{1E}"
    let tabs = SSSIndex.parseTabs(rec, app: "Browser", bundle: "b", pid: 1, path: "/", front: 4)
    check(211, "SSS: a browser's answer becomes its tabs, the current one ranked with its window",
          tabs.count == 3 && tabs[1].order == 4 && tabs[0].order > tabs[1].order && tabs[1].window == 71 && tabs[1].tab == 2 && tabs[1].host == "docs.example.com" && tabs[2].title == "about:blank",
          "\(tabs.count) tabs; orders \(tabs.map(\.order))")
    check(215, "SSS: a window's name drops its app's name from the end", SSSIndex.plainTitle("Inbox - Google Chrome", app: "Google Chrome") == "Inbox" && SSSIndex.plainTitle("Google Chrome", app: "Google Chrome") == "Google Chrome" && SSSIndex.plainTitle("", app: "Notes") == "Notes", SSSIndex.plainTitle("Inbox - Google Chrome", app: "Google Chrome"))
    // The scripts must be ones each installed browser understands: compiled against its own dictionary (nothing is sent to it).
    let installed = (SSSIndex.chromium + SSSIndex.safari).filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    var bad: [String] = []
    for b in installed {
        let probe = SSSItem(id: "t", kind: .tab, title: "x", app: "x", bundle: b, pid: 1, path: "/", window: 1, tab: 1)
        for src in [SSSIndex.tabScript(b), SSSIndex.openScript(probe)] {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
            p.arguments = ["-o", NSTemporaryDirectory() + "focus-sss-\(UUID().uuidString).scpt", "-e", src]; p.standardError = Pipe(); p.standardOutput = Pipe()
            try? p.run(); p.waitUntilExit(); try? FileManager.default.removeItem(atPath: p.arguments![1])
            if p.terminationStatus != 0 { bad.append(b) }
        }
    }
    check(214, "SSS: every installed browser understands its tab scripts", bad.isEmpty && !installed.isEmpty, installed.map { $0.components(separatedBy: ".").last ?? $0 }.joined(separator: ", ") + (bad.isEmpty ? "" : " — failed: \(bad)"))
    // The pictures. The bar shows no list until Tab asks for one; then the best guesses are under it. The bar is
    // black with white text whatever the window's look.
    func ink(_ opts: [String]) -> (bar: Int, below: Int) {
        let saved = renderArgs; renderArgs = ["Focus", "--render-sss", ""] + opts
        let rep = renderSSS(to: ""); renderArgs = saved
        guard let rep else { return (0, 0) }
        let s = CGFloat(rep.pixelsWide) / (SSSController.width + 100)          // pixels per point
        func bright(_ ys: Range<Int>) -> Int {
            var n = 0
            for y in stride(from: ys.lowerBound, to: ys.upperBound, by: 2) { for x in stride(from: Int(70 * s), to: rep.pixelsWide - Int(70 * s), by: 2) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent > 0.8 { n += 1 }
            } }
            return n
        }
        return (bright(Int(34 * s)..<Int(86 * s)), bright(Int(100 * s)..<Int(330 * s)))
    }
    for look in ["dark", "light"] {
        let shut = ink(["look=\(look)", "query=in"]), open = ink(["look=\(look)", "query=in", "open"])
        check(look == "dark" ? 212 : 213, "SSS: one bar and no list until Tab; then the best guesses (\(look) look)",
              shut.bar > 40 && shut.below == 0 && open.below > 200, "typed text and mark: \(shut.bar) bright samples; under the bar: \(shut.below) shut, \(open.below) open")
    }
    // Tab opens the dropdown on the best guess; Tab again moves on; Return with nothing to find shakes instead of going.
    SSSIndex.fixture = desk; SSSIndex.shared.refresh()
    let tm = SSSModel(); var went: [String] = []; tm.onPick = { went.append($0.title) }
    tm.query = "in"; let before = tm.open; tm.tab(1); let first = tm.selected; tm.tab(1); let second = tm.selected; tm.submit()
    tm.query = "zzqxv"; let shakes = tm.shakes; tm.submit()
    check(216, "SSS: Tab opens the choices on the best one, Tab again moves on, Return goes; nothing found shakes",
          !before && tm.open && first == 0 && second == 1 && went.count == 1 && tm.shakes == shakes + 1, "open \(tm.open); chosen \(first) then \(second); went to \(went); shakes \(tm.shakes - shakes)")
    let menuMark = SSSGlyph.image()
    check(217, "SSS: its mark draws for the menu", menuMark.isTemplate && menuMark.size.width > menuMark.size.height, "\(Int(menuMark.size.width)) × \(Int(menuMark.size.height))")
    SSSIndex.fixture = nil
    return Int32(failures)
}

/// `Focus --selftest-sss-live`: the real thing, once: reads this Mac, goes to the window used before this one, checks
/// it came forward, and comes straight back. About two seconds; nothing is closed or changed.
func sssLiveTest() -> Int32 {
    _ = NSApplication.shared
    var done = false; SSSIndex.shared.refresh { done = true }
    let until = Date().addingTimeInterval(8); while !done && Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    let all = SSSRank.search("", in: SSSIndex.shared.items)
    let tabs = all.filter { $0.kind == .tab }.count, wins = all.filter { $0.kind == .window }.count
    print("sss-live: accessibility \(SSSIndex.windowsAllowed ? "allowed" : "NOT allowed") · \(wins) windows · \(tabs) tabs · \(all.count - tabs - wins) apps without a window · browsers waiting for permission: \(SSSIndex.shared.tabsWaiting)")
    func frontNow() -> String {
        guard let a = NSWorkspace.shared.frontmostApplication else { return "?" }
        let el = AXUIElementCreateApplication(a.processIdentifier); var v: CFTypeRef?
        var title = ""
        if AXUIElementCopyAttributeValue(el, kAXFocusedWindowAttribute as CFString, &v) == .success, let w = v, CFGetTypeID(w) == AXUIElementGetTypeID() {
            var t: CFTypeRef?; if AXUIElementCopyAttributeValue(w as! AXUIElement, kAXTitleAttribute as CFString, &t) == .success { title = t as? String ?? "" }
        }
        return "\(a.localizedName ?? "?") — \(title)"
    }
    func wait(_ s: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
    guard all.count >= 2 else { print("sss-live: FAIL  fewer than two things open"); return 1 }
    let home = all[0], away = CommandLine.arguments.contains("tab") ? (all.first { $0.kind == .tab && $0.order >= 20 } ?? all[1]) : all[1]
    let before = frontNow()
    SSSIndex.shared.open(away); wait(1.4)
    let there = frontNow(), ok = there.hasPrefix(away.app) && (away.kind == .app || there.contains(String(away.title.prefix(12))))   // (a plain title is the start of the full one)
    SSSIndex.shared.open(home); wait(1.4)
    let back = frontNow()
    print("sss-live: \(ok ? "PASS" : "FAIL")  went to [\(away.kind)] \(away.app) — \(away.title.prefix(40)) · in front was: \(there.prefix(70))")
    let returned = back.hasPrefix(home.app) && (home.kind == .app || back.contains(String(home.title.prefix(12))))
    print("sss-live: \(returned ? "PASS" : "FAIL")  came back to \(home.title.prefix(30)) · before: \(before.prefix(60)) · after: \(back.prefix(60))")
    return ok && returned ? 0 : 1
}
