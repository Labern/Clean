// Focus — Super Smart Search (SSS).
//
// One key from anywhere (⌘⇧Space by default), type a few letters, Return: the exact window or browser tab you meant
// comes to the front — out of every app, every Chrome / Safari / Arc / Brave / Edge tab, minimised or not.
//
// How it finds things:
//   • Windows — the Accessibility API (AXWindows of every regular app), in front-to-back order, so the most recently
//     used ones rank first when two match equally. Minimised windows are included and un-minimised on open.
//   • Tabs — AppleScript to each *running* browser (never launches one): one bulk round trip per property, so 100
//     tabs cost the same four Apple Events as one.
//   • Apps — every running app, so "mail" still lands somewhere when Mail has no window.
// How it ranks: every word you type must match somewhere (title, app, site or address). A word scores most as a whole
// word, then as the start of a word, then as initials ("gd" → Google Docs), then anywhere inside, then as letters in
// order, and finally with one typo. Ties go to the recent window and the tab in front. And it learns: what you
// opened for a query is boosted next time you type the start of it.
//
// It keeps no record of windows: everything is read afresh each time the panel opens (≈ 50–150 ms in the
// background), so it can never point at something that has gone.
import AppKit
import SwiftUI
import ApplicationServices
import Carbon.HIToolbox

// MARK: the things it can find

struct SSSItem: Identifiable, Hashable {
    enum Kind: String { case window = "Window", tab = "Tab", app = "App" }
    let kind: Kind
    let title: String
    let app: String
    let bundle: String
    let pid: pid_t
    let url: String                 // tabs only
    let order: Int                  // front-to-back position (0 = most recent); tabs: window order
    var minimised = false
    var activeTab = false
    var twin = false                // another tab has the same title: show its address so you can tell them apart
    // How to get back to it.
    var windowID = 0                // browser window id (AppleScript)
    var tabIndex = 0                // 1-based
    var axIndex = 0                 // index into the app's AXWindows
    var id: String { "\(kind.rawValue)|\(bundle)|\(windowID)|\(tabIndex)|\(axIndex)|\(title)" }
    /// What "the same thing" means across launches, for learning: a tab is its address, a window its app + title.
    var memoryKey: String { kind == .tab ? "t|" + SSS.strip(url) : kind == .app ? "a|" + bundle : "w|" + bundle + "|" + title }
    var host: String { URL(string: url)?.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? "" }
    var subtitle: String {
        switch kind {
        case .tab: return twin ? app + " · " + SSS.strip(url) : host.isEmpty ? app : app + " · " + host
        case .window: return minimised ? app + " · minimised" : app
        case .app: return "Running app"
        }
    }
    static func == (a: SSSItem, b: SSSItem) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct SSSHit { let item: SSSItem; let score: Double; let marks: [Int] }   // marks: title character offsets that matched

enum SSS {
    /// Browsers whose tabs it reads. Chromium ones share one dictionary; Safari has its own.
    static let chromium: Set<String> = ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "com.brave.Browser",
                                        "com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "org.chromium.Chromium", "com.operasoftware.Opera"]
    static let safari: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    static let sep = "\u{1F}", eol = "\u{1E}"

    // MARK: gathering

    /// Everything findable, now. Runs the browsers and the windows side by side; call it off the main thread.
    static func gather(skipping own: pid_t = ProcessInfo.processInfo.processIdentifier) -> [SSSItem] {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != own && !$0.isTerminated }
        let zorder = frontToBack()
        let rank: (pid_t) -> Int = { p in zorder.firstIndex(of: p) ?? 999 }
        var out: [[SSSItem]] = Array(repeating: [], count: apps.count)
        DispatchQueue.concurrentPerform(iterations: apps.count) { i in
            let a = apps[i], b = a.bundleIdentifier ?? ""
            var got: [SSSItem] = []
            if chromium.contains(b) || safari.contains(b) { got = tabs(a, order: rank(a.processIdentifier)) }
            if got.isEmpty { got = windows(a, order: rank(a.processIdentifier)) }   // a browser that refused: its windows still
            got.append(SSSItem(kind: .app, title: a.localizedName ?? b, app: a.localizedName ?? b, bundle: b, pid: a.processIdentifier, url: "", order: rank(a.processIdentifier)))
            out[i] = got
        }
        var all = out.flatMap { $0 }
        var count: [String: Int] = [:]
        for it in all where it.kind == .tab { count[it.title, default: 0] += 1 }
        for i in all.indices where all[i].kind == .tab && (count[all[i].title] ?? 0) > 1 { all[i].twin = true }
        return all
    }

    /// The order apps' windows are stacked on screen, front first (no Screen Recording needed for owner pids).
    static func frontToBack() -> [pid_t] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        var seen: [pid_t] = []
        for w in info where (w[kCGWindowLayer as String] as? Int) == 0 {
            if let p = w[kCGWindowOwnerPID as String] as? pid_t, !seen.contains(p) { seen.append(p) }
        }
        if let f = NSWorkspace.shared.frontmostApplication?.processIdentifier { seen.removeAll { $0 == f }; seen.insert(f, at: 0) }
        return seen
    }

    static var trusted: Bool { AXIsProcessTrusted() }
    static func askForAccessibility() {
        let k = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([k: true] as CFDictionary)
    }

    static func axWindows(_ pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.4)                 // a hung app must not hang the search
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v) == .success, let ws = v as? [AXUIElement] else { return [] }
        return ws
    }
    static func ax<T>(_ e: AXUIElement, _ attr: String) -> T? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success ? v as? T : nil
    }

    static func windows(_ a: NSRunningApplication, order: Int) -> [SSSItem] {
        guard trusted else { return [] }
        let name = a.localizedName ?? "", b = a.bundleIdentifier ?? ""
        return axWindows(a.processIdentifier).enumerated().compactMap { i, w in
            let role: String? = ax(w, kAXSubroleAttribute)
            guard role == nil || role == kAXStandardWindowSubrole as String || role == kAXDialogSubrole as String else { return nil }   // no palettes or popovers
            let t: String = ax(w, kAXTitleAttribute) ?? ""
            var it = SSSItem(kind: .window, title: t.isEmpty ? name : t, app: name, bundle: b, pid: a.processIdentifier, url: "", order: order * 100 + i)
            it.minimised = ax(w, kAXMinimizedAttribute) ?? false
            it.axIndex = i
            return it
        }
    }

    /// One browser's tabs, in four Apple Events whatever the count. Returns [] if it refused (no permission yet).
    static func tabs(_ a: NSRunningApplication, order: Int) -> [SSSItem] {
        guard let b = a.bundleIdentifier else { return [] }
        let isSafari = safari.contains(b)
        let script = """
        tell application id "\(b)"
          set out to ""
          set wids to id of every window
          set ts to \(isSafari ? "name" : "title") of every tab of every window
          set us to URL of every tab of every window
          set ai to \(isSafari ? "index of current tab" : "active tab index") of every window
          repeat with i from 1 to count of wids
            set tl to item i of ts
            set ul to item i of us
            repeat with j from 1 to count of tl
              set u to item j of ul
              if u is missing value then set u to ""
              set out to out & (item i of wids) & "\(sep)" & j & "\(sep)" & (item i of ai) & "\(sep)" & i & "\(sep)" & (item j of tl) & "\(sep)" & u & "\(eol)"
            end repeat
          end repeat
          return out
        end tell
        """
        guard let text = osascript(script, timeout: 3) else { return [] }
        let name = a.localizedName ?? b
        return text.components(separatedBy: eol).compactMap { line in
            let f = line.components(separatedBy: sep)
            guard f.count >= 6, let w = Int(f[0]), let t = Int(f[1]) else { return nil }
            let wi = Int(f[3]) ?? 1, title = f[4].trimmingCharacters(in: .whitespacesAndNewlines), url = f[5...].joined(separator: sep)
            var it = SSSItem(kind: .tab, title: title.isEmpty ? url : title, app: name, bundle: b, pid: a.processIdentifier, url: url, order: order * 100 + wi)
            it.windowID = w; it.tabIndex = t; it.activeTab = Int(f[2]) == t
            return it
        }
    }

    /// Runs AppleScript in a child process: thread-safe (NSAppleScript is not) and killable if an app hangs.
    static func osascript(_ source: String, timeout: TimeInterval) -> String? {
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]; p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let done = DispatchSemaphore(value: 0)
        var data = Data()
        DispatchQueue.global().async { data = out.fileHandleForReading.readDataToEndOfFile(); done.signal() }
        if done.wait(timeout: .now() + timeout) == .timedOut { p.terminate(); return nil }
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines) : nil
    }

    // MARK: ranking

    static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil) }
    static func strip(_ url: String) -> String {
        var u = url
        for p in ["https://", "http://"] where u.hasPrefix(p) { u.removeFirst(p.count) }
        if u.hasPrefix("www.") { u.removeFirst(4) }
        if let h = u.firstIndex(of: "#") { u = String(u[..<h]) }
        return u
    }
    /// Words and where each starts (letters/digits runs; also splits camelCase so "SpotifyDrive" has "drive").
    static func words(_ s: [Character]) -> [(start: Int, text: [Character])] {
        var out: [(Int, [Character])] = [], cur: [Character] = [], start = 0
        for (i, c) in s.enumerated() {
            let alnum = c.isLetter || c.isNumber
            let camel = !cur.isEmpty && c.isUppercase && (cur.last?.isLowercase ?? false)
            if !alnum || camel { if !cur.isEmpty { out.append((start, cur)) }; cur = []; if !alnum { continue } }
            if cur.isEmpty { start = i }
            cur.append(c)
        }
        if !cur.isEmpty { out.append((start, cur)) }
        return out.map { ($0.0, Array(fold(String($0.1)))) }
    }

    /// How well one typed word matches one field, and which characters. 0 = not at all.
    static func match(_ q: [Character], in raw: String) -> (Double, [Int]) {
        guard !q.isEmpty, !raw.isEmpty else { return (0, []) }
        let chars = Array(raw), ws = words(chars), low = Array(fold(raw))
        let span = { (s: Int, n: Int) in Array(s..<min(s + n, chars.count)) }
        for w in ws where w.text == q { return (100, span(w.start, q.count)) }                       // a whole word
        for (k, w) in ws.enumerated() where w.text.starts(with: q) { return (k == 0 ? 88 : 80, span(w.start, q.count)) }   // start of a word
        if q.count >= 2, ws.count >= q.count {                                                       // initials: "gd" → Google Docs
            let inits = ws.map { $0.text.first! }
            if let r = find(q, in: inits) { return (62, (r..<r + q.count).map { ws[$0].start }) }
        }
        if q.count >= 2, let r = find(q, in: low) { return (q.count == 2 ? 28 : 55, span(r, q.count)) }   // inside a word (two letters: weak)
        if q.count >= 3 {                                                                            // letters in order, tightly
            var marks: [Int] = [], j = 0
            for (i, c) in low.enumerated() where j < q.count && c == q[j] { marks.append(i); j += 1 }
            if j == q.count, let a = marks.first, let z = marks.last {
                let spread = Double(z - a + 1) / Double(q.count)                                    // 1 = contiguous
                if spread <= 4 { return (max(20, 45 - spread * 6), marks) }
            }
        }
        if q.count >= 4 { for w in ws where abs(w.text.count - q.count) <= 1 && near(q, w.text) { return (35, span(w.start, w.text.count)) } }   // one typo
        return (0, [])
    }
    static func find(_ q: [Character], in s: [Character]) -> Int? {
        guard q.count <= s.count else { return nil }
        for i in 0...(s.count - q.count) where Array(s[i..<i + q.count]) == q { return i }
        return nil
    }
    /// Within one edit (insert, delete, substitute or swap two neighbours).
    static func near(_ a: [Character], _ b: [Character]) -> Bool {
        if a == b { return true }
        if a.count == b.count {
            let d = zip(a, b).enumerated().filter { $0.element.0 != $0.element.1 }.map(\.offset)
            if d.count == 1 { return true }
            if d.count == 2, d[1] == d[0] + 1, a[d[0]] == b[d[1]], a[d[1]] == b[d[0]] { return true }
            return false
        }
        let (s, l) = a.count < b.count ? (a, b) : (b, a)
        guard l.count - s.count == 1 else { return false }
        var i = 0, j = 0, skipped = false
        while i < s.count && j < l.count { if s[i] == l[j] { i += 1; j += 1 } else if skipped { return false } else { skipped = true; j += 1 } }
        return true
    }

    /// Ranks everything for a query. Empty query: recent windows and front tabs, as a "jump back" list.
    static func rank(_ items: [SSSItem], _ query: String, memory: [String: [String: Int]] = SSSMemory.all) -> [SSSHit] {
        let terms = fold(query).split(whereSeparator: { $0 == " " }).map { Array($0) }
        let learned = SSSMemory.boosts(query, memory)
        if terms.isEmpty {
            let recent = items.filter { $0.kind == .window || ($0.kind == .tab && $0.activeTab) }
            return recent.sorted { $0.order < $1.order }.prefix(30).map { SSSHit(item: $0, score: 0, marks: []) }
        }
        var hits: [SSSHit] = []
        for it in items {
            var total = 0.0, marks: [Int] = [], ok = true
            for q in terms {
                let t = match(q, in: it.title), a = match(q, in: it.app)
                let h = it.kind == .tab ? match(q, in: it.host) : (0, [])
                let u = it.kind == .tab ? match(q, in: strip(it.url)) : (0, [])
                let best = max(t.0, a.0 * 0.75, h.0 * 0.9, u.0 * 0.5)
                if best == 0 { ok = false; break }
                total += best
                if t.0 > 0 && t.0 >= best { marks += t.1 }
            }
            guard ok else { continue }
            var s = total / Double(terms.count)
            if it.kind == .app { s -= 18 }                         // an app only when nothing of it matches better
            if it.minimised { s -= 2 }
            if it.activeTab { s += 3 }
            s += max(0, 8 - Double(it.order) / 100)               // recency: the front app's things first
            s += Double(learned[it.memoryKey] ?? 0)
            hits.append(SSSHit(item: it, score: s, marks: Array(Set(marks)).sorted()))
        }
        // An app entry is noise when one of its own windows or tabs is already in the list.
        let withThings = Set(hits.filter { $0.item.kind != .app }.map(\.item.bundle))
        hits.removeAll { $0.item.kind == .app && withThings.contains($0.item.bundle) && $0.score < 60 }
        return hits.sorted { $0.score != $1.score ? $0.score > $1.score : $0.item.order < $1.item.order }
    }

    // MARK: going there

    /// Brings the exact window or tab to the front: un-minimises, unhides, switches tab, raises, activates.
    @discardableResult
    static func open(_ it: SSSItem) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: it.pid) else { return false }
        if app.isHidden { app.unhide() }
        switch it.kind {
        case .tab:
            let isSafari = safari.contains(it.bundle)
            let pick = isSafari ? "set current tab of w to tab \(it.tabIndex) of w" : "set active tab index of w to \(it.tabIndex)"
            let ok = osascript("""
            tell application id "\(it.bundle)"
              set w to window id \(it.windowID)
              \(pick)
              set index of w to 1
              if minimized of w then set minimized of w to false
              activate
            end tell
            """, timeout: 3) != nil
            app.activate()
            raiseFront(it.pid)
            return ok
        case .window:
            let ws = axWindows(it.pid)
            let w = ws.indices.contains(it.axIndex) && (ax(ws[it.axIndex], kAXTitleAttribute) ?? "") == it.title
                ? ws[it.axIndex] : ws.first { (ax($0, kAXTitleAttribute) ?? "") == it.title }   // windows may have reordered
            app.activate()
            guard let w else { return false }
            if it.minimised { AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
            AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
            return true
        case .app:
            app.activate()
            return true
        }
    }
    /// After a browser switches tab, make sure its front window really is the raised one (across Spaces too).
    static func raiseFront(_ pid: pid_t) {
        guard trusted, let w = axWindows(pid).first else { return }
        AXUIElementPerformAction(w, kAXRaiseAction as CFString)
    }
}

// MARK: learning — what you opened for what you typed

enum SSSMemory {
    static let key = "sssMemory"
    /// prefix (folded, up to 12 chars) → memoryKey → times chosen. Small, local, never leaves the Mac.
    static var all: [String: [String: Int]] { UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Int]] ?? [:] }
    static func remember(_ query: String, _ it: SSSItem) {
        let q = String(SSS.fold(query).trimmingCharacters(in: .whitespaces).prefix(12))
        guard !q.isEmpty else { return }
        var m = all
        for n in 1...q.count {                                    // every prefix: "fo" and "foc" both learn "focus"
            let p = String(q.prefix(n))
            var e = m[p] ?? [:]; e[it.memoryKey, default: 0] += 1
            if e.count > 8 { e = Dictionary(uniqueKeysWithValues: e.sorted { $0.value > $1.value }.prefix(8).map { ($0.key, $0.value) }) }
            m[p] = e
        }
        if m.count > 600 { m = Dictionary(uniqueKeysWithValues: m.sorted { $0.key.count < $1.key.count }.prefix(600).map { ($0.key, $0.value) }) }
        UserDefaults.standard.set(m, forKey: key)
    }
    /// The boost for each thing: up to +30 for what you always pick, scaled by how often.
    static func boosts(_ query: String, _ m: [String: [String: Int]]) -> [String: Int] {
        let q = String(SSS.fold(query).trimmingCharacters(in: .whitespaces).prefix(12))
        guard !q.isEmpty, let e = m[q] else { return [:] }
        return e.mapValues { min(30, 12 + $0 * 6) }
    }
}

// MARK: the panel — a Spotlight-style field that floats over whatever you're doing

final class SSSModel: ObservableObject {
    @Published var query = "" { didSet { refresh() } }
    @Published var hits: [SSSHit] = []
    @Published var selected = 0
    @Published var loading = true
    @Published var trusted = SSS.trusted
    var items: [SSSItem] = []
    var onDone: () -> Void = {}
    func reload() {
        loading = true; trusted = SSS.trusted
        DispatchQueue.global(qos: .userInitiated).async {
            let got = SSS.gather()
            DispatchQueue.main.async { self.items = got; self.loading = false; self.refresh() }
        }
    }
    func refresh() { hits = Array(SSS.rank(items, query).prefix(40)); selected = 0 }
    func move(_ d: Int) { guard !hits.isEmpty else { return }; selected = (selected + d + hits.count) % hits.count }
    func go(_ i: Int? = nil) {
        let n = i ?? selected
        guard hits.indices.contains(n) else { return }
        let it = hits[n].item
        SSSMemory.remember(query, it)
        onDone()
        DispatchQueue.main.async { SSS.open(it) }
    }
}

/// A borderless panel that takes typing without bringing Focus forward, so Escape leaves you exactly where you were.
final class SSSPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    var keys: ((NSEvent) -> Bool)?
    override func sendEvent(_ e: NSEvent) {
        if e.type == .keyDown, keys?(e) == true { return }
        super.sendEvent(e)
    }
    override func resignKey() { super.resignKey(); orderOut(nil) }            // click elsewhere: it goes
}

final class SSSController {
    static let shared = SSSController()
    let model = SSSModel()
    var panel: SSSPanel?
    var shown: Bool { panel?.isVisible ?? false }

    func toggle() { shown ? hide() : show() }
    func hide() { panel?.orderOut(nil) }
    func show() {
        let p = panel ?? make()
        model.query = ""; model.reload()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let s = screen?.visibleFrame {                                     // where Spotlight sits: centred, a third down
            p.setFrameOrigin(NSPoint(x: s.midX - p.frame.width / 2, y: s.maxY - s.height * 0.22 - p.frame.height))
        }
        p.makeKeyAndOrderFront(nil)
    }
    private func make() -> SSSPanel {
        let p = SSSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 470), styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        p.level = .floating; p.isFloatingPanel = true; p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.backgroundColor = .clear; p.isOpaque = false; p.hasShadow = true
        p.isMovableByWindowBackground = true
        model.onDone = { [weak p] in p?.orderOut(nil) }
        p.keys = { [unowned self] e in
            let cmd = e.modifierFlags.contains(.command)
            switch Int(e.keyCode) {
            case kVK_Escape: if model.query.isEmpty { hide() } else { model.query = "" }; return true
            case kVK_DownArrow: model.move(1); return true
            case kVK_UpArrow: model.move(-1); return true
            case kVK_Return, kVK_ANSI_KeypadEnter: model.go(); return true
            case kVK_ANSI_N where e.modifierFlags.contains(.control): model.move(1); return true
            case kVK_ANSI_P where e.modifierFlags.contains(.control): model.move(-1); return true
            default:
                if cmd, let c = e.charactersIgnoringModifiers, let d = Int(c), (1...9).contains(d) { model.go(d - 1); return true }   // ⌘1–9: that row
                return false
            }
        }
        p.contentView = NSHostingView(rootView: SSSView(m: model))
        panel = p
        return p
    }
}

struct SSSView: View {
    @ObservedObject var m: SSSModel
    var embedded = false                                     // inside the desktop window's page, not the floating panel
    @FocusState private var typing: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .medium)).foregroundColor(Site.muted)
                TextField("", text: $m.query, prompt: Text("Find any window or tab").foregroundColor(Site.muted))
                    .textFieldStyle(.plain).font(Site.font(24)).foregroundColor(Site.head).focused($typing)
                    .onSubmit { m.go() }
                if m.loading { ProgressView().controlSize(.small) }
                else if !m.query.isEmpty { Text("\(m.hits.count)").font(Site.font(15)).foregroundColor(Site.muted).monospacedDigit() }
            }.padding(.horizontal, 20).frame(height: 62)
            Rectangle().fill(Site.line).frame(height: 1)
            if !m.trusted {
                Button { SSS.askForAccessibility(); DispatchQueue.main.asyncAfter(deadline: .now() + 2) { m.reload() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.open").font(.system(size: 13))
                        Text("Allow Accessibility so SSS can find and raise every window").font(Site.font(15))
                        Spacer()
                        Text("Allow").font(Site.font(14, .medium)).foregroundColor(Site.paper).padding(.horizontal, 10).frame(height: 22).background(Capsule().fill(Site.ink))
                    }.foregroundColor(Site.low).padding(.horizontal, 20).frame(height: 40)
                }.buttonStyle(.plain)
                Rectangle().fill(Site.line).frame(height: 1)
            }
            ScrollViewReader { sv in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        if m.query.isEmpty && !m.hits.isEmpty {
                            Text("Jump back").font(Site.font(13, .medium)).foregroundColor(Site.muted)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 2)
                        }
                        ForEach(Array(m.hits.enumerated()), id: \.element.item.id) { i, h in
                            SSSRow(hit: h, n: i, selected: i == m.selected).id(i)
                                .onTapGesture { m.go(i) }
                                .onHover { if $0 { m.selected = i } }
                        }
                        if !m.loading && m.hits.isEmpty && !m.query.isEmpty {
                            Text("Nothing open matches “\(m.query)”").font(Site.font(16)).foregroundColor(Site.muted).padding(.vertical, 26)
                        }
                    }.padding(8)
                }.onReceive(m.$selected) { n in withAnimation(.easeOut(duration: 0.08)) { sv.scrollTo(n) } }
            }
        }
        .background(RoundedRectangle(cornerRadius: embedded ? 12 : 16, style: .continuous).fill(Site.paper))
        .overlay(RoundedRectangle(cornerRadius: embedded ? 12 : 16, style: .continuous).stroke(Site.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: embedded ? 12 : 16, style: .continuous))
        .onAppear { typing = true }
    }
}

struct SSSRow: View {
    let hit: SSSHit, n: Int, selected: Bool
    var body: some View {
        let it = hit.item
        HStack(spacing: 12) {
            Image(nsImage: SSSIcons.icon(it.pid)).resizable().interpolation(.high).frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                marked(it.title, hit.marks).font(Site.font(17)).lineLimit(1).truncationMode(.middle)
                Text(it.subtitle).font(Site.font(13)).foregroundColor(Site.muted).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(it.kind.rawValue).font(Site.font(13)).foregroundColor(Site.muted)              // one right-aligned column
            Text(n < 9 ? "⌘\(n + 1)" : "").font(Site.font(13)).foregroundColor(selected ? Site.head : Site.muted).frame(width: 28, alignment: .trailing)
        }
        .padding(.horizontal, 12).frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? Site.surface2 : .clear))
        .contentShape(Rectangle())
    }
    /// The title with the letters that matched in full ink, the rest a step down: you see *why* it was found.
    func marked(_ s: String, _ marks: [Int]) -> Text {
        let set = Set(marks)
        guard !set.isEmpty else { return Text(s).foregroundColor(Site.head) }
        var a = AttributedString()
        for (i, c) in s.enumerated() {
            var piece = AttributedString(String(c))
            piece.foregroundColor = set.contains(i) ? Site.head : Site.low
            if set.contains(i) { piece.inlinePresentationIntent = .stronglyEmphasized }
            a += piece
        }
        return Text(a)
    }
}

enum SSSIcons {
    static var cache: [pid_t: NSImage] = [:]
    static func icon(_ pid: pid_t) -> NSImage {
        if let i = cache[pid] { return i }
        let i = NSRunningApplication(processIdentifier: pid)?.icon ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)!
        cache[pid] = i
        return i
    }
}

/// The desktop window's page: the same search, in place, with what it is and its key.
struct SSSPage: View {
    @ObservedObject var m: DesktopModel
    @StateObject private var s = SSSModel()
    var body: some View {
        let f = m.f
        PageFrame(title: "Super Smart Search", text: "Press \(f.sssKey) anywhere, type a few letters of what you're looking for, and press Return. SSS looks through every window of every app and every tab in Chrome, Safari, Arc, Brave and Edge, and brings the exact one to the front.") {
            SSSView(m: s, embedded: true).frame(height: 420).padding(.top, 14)
                .onAppear {
                    s.onDone = {}
                    if renderArgs.contains("sss") { s.items = SSS.gather(); s.loading = false; s.query = renderArgs.first { $0.hasPrefix("q=") }.map { String($0.dropFirst(2)) } ?? "" }   // off-screen renders: filled at once
                    else { s.reload() }
                }
            SettingLine(title: "Shortcut", note: f.sssKeyTaken ? "That combination is taken by another app. Pick another." : "From anywhere. Press again to put it away.") {
                Choice(options: modifierChoices.map { $0.label + "Space" }, selected: modifierChoices.firstIndex { $0.mods == f.sssMods } ?? 0) { i in m.act { f.sssMods = modifierChoices[i].mods } }
            }.padding(.top, 14)
            Text("How it ranks: every word you type has to match something — the title, the app, the site or the address. Whole words count most, then starts of words, then initials (gd → Google Docs), then letters in order, then a single typo. It learns what you open, so the thing you always want comes first.")
                .font(Site.font(15)).foregroundColor(Site.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
        }
    }
}

/// `Focus --render-sss FILE "query" [look=light]`: the floating panel, filled with this Mac's real windows and tabs,
/// drawn off-screen to a PNG — to look at it without opening anything on screen.
func renderSSS(to file: String, query: String) {
    let m = SSSModel(); m.items = SSS.gather(); m.loading = false; m.query = query
    let v = NSHostingView(rootView: SSSView(m: m).frame(width: 680, height: 470).background(Color.gray.opacity(0.35)))
    v.frame = NSRect(x: 0, y: 0, width: 680, height: 470)
    let w = NSWindow(contentRect: v.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = v; v.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
    v.cacheDisplay(in: v.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: file))
}
