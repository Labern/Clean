// Focus — park the big apps (Chrome, Obsidian, Keynote…) so their memory goes to the work, then bring them
// back exactly as they were. Quitting is slow and safe: one app at a time, each asked to quit normally (so it
// saves its state, and unsaved work still prompts), waiting for it to finish before the next. Never forced.
// Restoring relaunches them one at a time with their windows (Chrome with its last session).
// Menu bar only. One file, no dependencies, no permissions.
//   ⌘⇧F   start a session (quit everything not kept) · again: bring it all back
//   ⌘⇧E   open the Focus menu: click apps to keep them for this session, then Start Session Now
// Never touched, ever: system apps (/System/Library/CoreServices), menu bar apps, Focus itself, and the
// user's Critical System Processes (seeded with Wispr Flow). The system ⌘⇥ is never altered.
import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI
import Darwin

// Earlier builds switched the system ⌘⇥ off during a session (private SkyLight call). That setting outlives
// the process, so every launch switches it back on — heals any Mac left without ⌘⇥ by an old build.
func healSystemSwitcher() {
    guard let lib = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
          let fn = dlsym(lib, "CGSSetSymbolicHotKeyEnabled") else { return }
    let set = unsafeBitCast(fn, to: (@convention(c) (Int32, Bool) -> Int32).self)
    _ = set(1, true); _ = set(2, true)
}

func hotkey(_ id: UInt32, _ key: Int, _ mods: Int) -> EventHotKeyRef? {
    var ref: EventHotKeyRef?
    RegisterEventHotKey(UInt32(key), UInt32(mods), EventHotKeyID(signature: 0x464F_4355, id: id), GetEventDispatcherTarget(), 0, &ref)
    return ref
}
func symbol(_ name: String, _ colors: [NSColor]? = nil) -> NSImage? {
    let i = NSImage(systemSymbolName: name, accessibilityDescription: nil)
    guard let colors else { return i }
    return i?.withSymbolConfiguration(.init(paletteColors: colors))
}

/// Every colour the custom menu views use. One token set: swap it to re-theme the whole menu.
struct Theme {
    var accent = NSColor.controlAccentColor
    var onAccent = NSColor.white
    var hover = NSColor.labelColor.withAlphaComponent(0.08)
    var text = NSColor.labelColor
    var faint = NSColor.secondaryLabelColor
    var dropped = NSColor.tertiaryLabelColor
}
let theme = Theme()
let menuWidth: CGFloat = 320
let sessionKey = "⌘⇧F"
let claude = "com.anthropic.claudefordesktop", wispr = "com.electron.wispr-flow", chrome = "com.google.Chrome"

/// Every process with its parent and short name, read the way `ps` reads them (sysctl KERN_PROC_ALL).
/// (proc_listallpids silently skipped processes, Claude's own among them.)
struct Proc { let pid: pid_t, ppid: pid_t, name: String }
func processes() -> [Proc] {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0], size = 0
    let stride = MemoryLayout<kinfo_proc>.stride
    guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return [] }
    var buf = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 64)
    size = buf.count * stride
    guard sysctl(&mib, 4, &buf, &size, nil, 0) == 0 else { return [] }
    return buf.prefix(size / stride).map { k in
        var comm = k.kp_proc.p_comm
        let name = withUnsafeBytes(of: &comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return Proc(pid: k.kp_proc.p_pid, ppid: k.kp_eproc.e_ppid, name: name)
    }
}

/// Physical memory per process tree, the number Activity Monitor calls "Memory". An app's figure includes its
/// helpers (Chrome's renderers, Electron's GPU process…), which are its child processes.
func memoryByPid() -> [pid_t: UInt64] {
    var own: [pid_t: UInt64] = [:], kids: [pid_t: [pid_t]] = [:]
    for p in processes() where p.pid > 0 {
        kids[p.ppid, default: []].append(p.pid)
        var ru = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &ru) { $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(p.pid, RUSAGE_INFO_V4, $0) } }
        if ok == 0 { own[p.pid] = ru.ri_phys_footprint }
    }
    var total: [pid_t: UInt64] = [:]
    func sum(_ p: pid_t, _ depth: Int) -> UInt64 {
        if let t = total[p] { return t }
        let t = (own[p] ?? 0) + (depth > 8 ? 0 : (kids[p] ?? []).reduce(0) { $0 + sum($1, depth + 1) })
        total[p] = t; return t
    }
    for p in own.keys where p > 1 { _ = sum(p, 0) }
    return total
}

/// Every ancestor of a running Claude Code process (`claude` → shell → login → Terminal / iTerm / Ghostty…).
/// The app among them is the terminal Claude is working in, and Focus must never close it.
func claudeHosts() -> Set<pid_t> {
    let all = processes()
    var parent: [pid_t: pid_t] = [:], hosts = Set<pid_t>()
    for p in all { parent[p.pid] = p.ppid }
    var name = [CChar](repeating: 0, count: 256), path = [CChar](repeating: 0, count: 4096)
    func isClaude(_ pid: pid_t) -> Bool {               // its full name, or its binary under …/claude/ (versions/2.1.x)
        if proc_name(pid, &name, UInt32(name.count)) > 0, String(cString: name) == "claude" { return true }
        return proc_pidpath(pid, &path, UInt32(path.count)) > 0 && String(cString: path).contains("/.local/share/claude/")
    }
    for p in all where p.name == "claude" || isClaude(p.pid) {
        var up = p.ppid, hops = 0
        while up > 1 && hops < 32 { hosts.insert(up); up = parent[up] ?? 1; hops += 1 }
    }
    return hosts
}
func gb(_ b: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .memory) }

/// The menu bar mark: a viewfinder ring with a centre dot. `t` is linear progress, 0 (at rest: four open
/// brackets, gaps at the compass points, small dot) to 1 (focused: one closed ring, bigger dot). With `hunt`
/// the ring first pulls in and comes back out — a lens finding focus — then the gaps close in place and the
/// dot swells. Each phase has its own eased slice of the timeline. Template image: follows light / dark bars.
func glyph(_ t: CGFloat, hunt: Bool = false) -> NSImage {
    func phase(_ a: CGFloat, _ b: CGFloat) -> CGFloat {          // 0…1 across [a, b], smoothstep-eased
        let x = min(max((t - a) / (b - a), 0), 1); return x * x * (3 - 2 * x)
    }
    let pull = hunt ? sin(.pi * phase(0, 0.55)) * 2.0 : 0
    let close = hunt ? phase(0.35, 0.85) : t                     // gap fraction closed
    let swell = hunt ? phase(0.45, 1) : t
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
        let c = NSPoint(x: r.midX, y: r.midY), radius = 6.5 - pull
        let gap = 23.4 * (1 - close)                                 // degrees; 0 = a closed ring
        let ring = NSBezierPath(); ring.lineWidth = 1.6
        if gap < 0.5 { ring.appendOval(in: NSRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)) }
        else { for k in 0..<4 {                                       // arcs centred on 45°, 135°… so gaps sit on the axes
            let mid = 45 + 90 * CGFloat(k)
            ring.move(to: NSPoint(x: c.x + radius * cos((mid - 45 + gap / 2) * .pi / 180), y: c.y + radius * sin((mid - 45 + gap / 2) * .pi / 180)))
            ring.appendArc(withCenter: c, radius: radius, startAngle: mid - 45 + gap / 2, endAngle: mid + 45 - gap / 2)
        } }
        ring.stroke()
        let dot = 1.75 + 1.25 * swell - (hunt ? pull * 0.3 : 0)      // radius: 1.75 at rest, 3 focused
        NSBezierPath(ovalIn: NSRect(x: c.x - dot, y: c.y - dot, width: dot * 2, height: dot * 2)).fill()
        return true
    }
    img.isTemplate = true
    return img
}
func glyph(focused: Bool) -> NSImage { glyph(focused ? 1 : 0) }

/// A menu view that highlights under the pointer and stretches to the menu's width.
class HoverView: NSView {
    var hover = false { didSet { needsDisplay = true } }
    init(height: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: height))
        autoresizingMask = [.width]
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { nil }
    override func mouseEntered(with e: NSEvent) { hover = true }
    override func mouseExited(with e: NSEvent) { hover = false }
    // Take the whole click. Unhandled, mouseDown falls through to the menu, which can read it as a click-away and close.
    override func mouseDown(with e: NSEvent) {}
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
}

/// One app: icon, name, and a mark on the right. Clicking flips it without closing the menu, so several
/// can be set in one go. `on` uses `onMark`, off uses an empty circle; apps that will go read dimmer.
final class AppRow: HoverView {
    let name: String, icon: NSImage, detail: String, onMark: String, flip: () -> Bool
    var on: Bool
    init(_ name: String, _ icon: NSImage, detail: String = "", on: Bool, onMark: String = "checkmark.circle.fill", flip: @escaping () -> Bool) {
        self.name = name; self.icon = icon; self.detail = detail; self.on = on; self.onMark = onMark; self.flip = flip
        super.init(height: 26)
    }
    required init?(coder: NSCoder) { nil }
    override func mouseUp(with e: NSEvent) { on = flip(); needsDisplay = true }
    override func draw(_ r: NSRect) {
        if hover { theme.hover.setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 5, yRadius: 5).fill() }
        icon.draw(in: NSRect(x: 14, y: 5, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: on ? 1 : 0.55)
        (name as NSString).draw(at: NSPoint(x: 38, y: 4.5), withAttributes: [.font: NSFont.menuFont(ofSize: 13), .foregroundColor: on ? theme.text : theme.faint])
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: theme.faint]
        let d = detail as NSString
        d.draw(at: NSPoint(x: bounds.width - 42 - d.size(withAttributes: small).width, y: 6), withAttributes: small)
        let mark = on ? symbol(onMark, [theme.onAccent, theme.accent]) : symbol("circle", [theme.dropped])
        mark?.draw(in: NSRect(x: bounds.width - 32, y: 5, width: 16, height: 16))
    }
}

/// The big button at the bottom: the one action, its key, and a live caption of what it will do.
final class BigButton: HoverView {
    let title: () -> String, caption: () -> String, action: () -> Void
    var down = false { didSet { needsDisplay = true } }
    init(title: @escaping () -> String, caption: @escaping () -> String, action: @escaping () -> Void) {
        self.title = title; self.caption = caption; self.action = action
        super.init(height: 72)
    }
    required init?(coder: NSCoder) { nil }
    override func mouseDown(with e: NSEvent) { down = true }
    override func mouseUp(with e: NSEvent) {
        down = false
        enclosingMenuItem?.menu?.cancelTracking()
        DispatchQueue.main.async(execute: action)
    }
    override func draw(_ r: NSRect) {
        let pill = NSRect(x: 12, y: 26, width: bounds.width - 24, height: 38)
        (down ? theme.accent.blended(withFraction: 0.2, of: .black) : hover ? theme.accent.blended(withFraction: 0.1, of: .white) : theme.accent)?.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 9, yRadius: 9).fill()
        let big: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: theme.onAccent]
        (title() as NSString).draw(at: NSPoint(x: pill.minX + 14, y: pill.midY - 9), withAttributes: big)
        let key: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: theme.onAccent.withAlphaComponent(0.75)]
        let k = sessionKey as NSString
        k.draw(at: NSPoint(x: pill.maxX - 14 - k.size(withAttributes: key).width, y: pill.midY - 8.5), withAttributes: key)
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: theme.faint]
        let c = caption() as NSString
        c.draw(at: NSPoint(x: bounds.midX - c.size(withAttributes: small).width / 2, y: 6), withAttributes: small)
    }
}

/// The session snapshot as a rounded thumbnail; click to open it full size.
final class Thumb: HoverView {
    let img: NSImage, action: () -> Void
    init(_ img: NSImage, _ size: NSSize, action: @escaping () -> Void) {
        self.img = img; self.action = action
        super.init(height: size.height + 8)
    }
    required init?(coder: NSCoder) { nil }
    override func mouseUp(with e: NSEvent) { enclosingMenuItem?.menu?.cancelTracking(); DispatchQueue.main.async(execute: action) }
    override func draw(_ r: NSRect) {
        let rect = NSRect(x: 14, y: 4, width: bounds.width - 28, height: bounds.height - 8)
        let clip = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSGraphicsContext.saveGraphicsState(); clip.addClip()
        img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: hover ? 1 : 0.92)
        NSGraphicsContext.restoreGraphicsState()
        theme.dropped.setStroke(); clip.lineWidth = 1; clip.stroke()
    }
}

typealias Session = [String: Any]                              // "date": Date, "apps": [["path": String, "hidden": Bool]]

final class Focus: NSObject, NSMenuDelegate {
    let ws = NSWorkspace.shared, store: UserDefaults
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    weak var button: BigButton?                                 // redrawn as rows change, so its caption is live
    var mem: [pid_t: UInt64] = [:]                              // refreshed each time the menu opens
    var hosts = claudeHosts()                                   // terminals running Claude Code: refreshed before every decision
    var queue: [NSRunningApplication] = [], total = 0           // the slow, one-at-a-time quit in progress
    var status: String? { didSet { item.button?.toolTip = status ?? "Focus" } }
    lazy var never = NeverModel(self)
    var neverWindow: NSWindow?
    let when: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; f.doesRelativeDateFormatting = true; return f
    }()

    var sessions: [Session] {                                   // newest first, last 12 kept
        get { store.array(forKey: "sessions") as? [Session] ?? [] }
        set { store.set(Array(newValue.prefix(12)), forKey: "sessions") }
    }
    var excluded: [String] {                                    // "keep open": the user's per-session picks
        get { store.stringArray(forKey: "excluded") ?? [] }
        set { store.set(newValue, forKey: "excluded") }
    }
    var neverClose: [String] {                                  // "never close": the user's permanent list
        get { store.stringArray(forKey: "neverClose") ?? [] }
        set { store.set(newValue, forKey: "neverClose") }
    }
    var snapshots: Bool {                                       // screenshot at session start, deleted on restore
        get { store.object(forKey: "snapshots") as? Bool ?? true }
        set { store.set(newValue, forKey: "snapshots") }
    }
    /// ~/Library/Application Support/Focus — snapshots live here and nowhere else.
    lazy var folder: URL = {                                    // the self-test gets its own, so it can never prune a real snapshot
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(store == .standard ? "Focus" : "Focus-selftest", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    var hideMode: Bool {                                        // hide instead of quit: instant, but keeps the memory
        get { store.bool(forKey: "hideMode") }
        set { store.set(newValue, forKey: "hideMode") }
    }
    var focused: Bool {
        get { store.bool(forKey: "focused") }
        set {
            let was = store.bool(forKey: "focused")
            store.set(newValue, forKey: "focused")
            if newValue != was { animateIcon(to: newValue) } else { item.button?.image = glyph(focused: newValue) }
        }
    }
    /// The system's "reopen windows when an app relaunches" (System Settings ▸ Desktop & Dock ▸
    /// "Close windows when quitting an application", inverted). Without it a quit app comes back empty.
    var keepWindows: Bool {
        get { store.bool(forKey: "NSQuitAlwaysKeepsWindows") }
        set {
            CFPreferencesSetAppValue("NSQuitAlwaysKeepsWindows" as CFString, newValue as CFBoolean, kCFPreferencesAnyApplication)
            CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        }
    }

    init(store: UserDefaults = .standard) {
        self.store = store
        super.init()
        let menu = NSMenu(); menu.delegate = self; menu.minimumWidth = menuWidth; item.menu = menu
        if !store.bool(forKey: "setUp") { keepWindows = true; store.set(true, forKey: "setUp") }
        if !store.bool(forKey: "keepClaude") {                  // Claude starts kept (user's default for now); untick to drop it
            if !excluded.contains(claude) { excluded.append(claude) }
            store.set(true, forKey: "keepClaude")
        }
        if !store.bool(forKey: "neverCloseSeeded") {            // Wispr Flow must never be closed (user's rule)
            if !neverClose.contains(wispr) { neverClose.append(wispr) }
            store.set(true, forKey: "neverCloseSeeded")
        }
        healSystemSwitcher()
        item.button?.image = glyph(focused: focused)
        pruneSnapshots()
    }

    /// System apps (Finder & co. live in CoreServices), Focus itself, and the user's Never close list.
    func system(_ a: NSRunningApplication) -> Bool {
        a.bundleURL?.path.hasPrefix("/System/Library/CoreServices/") ?? true || a.bundleIdentifier == Bundle.main.bundleIdentifier
    }
    func protected(_ a: NSRunningApplication) -> Bool { system(a) || neverClose.contains(a.bundleIdentifier ?? "") }
    /// The terminal Claude Code runs in starts out ticked to keep, once per app; after that the user decides.
    func autoKeepClaudeHosts() {
        var seen = store.stringArray(forKey: "claudeAutoKept") ?? []
        for a in ws.runningApplications where hosts.contains(a.processIdentifier) && a.activationPolicy == .regular {
            guard let id = a.bundleIdentifier, !seen.contains(id) else { continue }
            if !excluded.contains(id) { excluded.append(id) }
            seen.append(id)
        }
        store.set(seen, forKey: "claudeAutoKept")
    }

    /// Dock / ⌘⇥ apps Focus may touch. Menu bar apps are `.accessory`: never listed, never touched.
    func apps() -> [NSRunningApplication] { ws.runningApplications.filter { $0.activationPolicy == .regular && !protected($0) } }
    func leaving() -> [NSRunningApplication] { apps().filter { !excluded.contains($0.bundleIdentifier ?? "") } }
    func memory(_ a: NSRunningApplication) -> UInt64 { mem[a.processIdentifier] ?? 0 }
    /// Apps the user could add to Never close: anything in the Dock that isn't a system app.
    func candidates() -> [String] { ws.runningApplications.filter { $0.activationPolicy == .regular && !system($0) }.compactMap(\.bundleIdentifier) }

    // MARK: session

    func park(quit: Bool) {
        hosts = claudeHosts(); autoKeepClaudeHosts()
        let out = leaving()
        guard !out.isEmpty else { return }
        var session: Session = ["date": Date(), "apps": out.compactMap { a in a.bundleURL.map { ["path": $0.path, "hidden": a.isHidden] as [String: Any] } }]
        if snapshots, let shot = snapshot() { session["shot"] = shot }   // before anything moves
        sessions.insert(session, at: 0)
        pruneSnapshots()
        focused = true
        if !quit { out.forEach { $0.hide() }; return }
        queue = out.sorted { memory($0) > memory($1) }; total = queue.count   // biggest first: memory comes back soonest
        quitNext()
    }

    /// One app at a time: ask it to quit the normal way (it saves its state; unsaved work prompts), wait until it
    /// has really gone, pause, then the next. An app still open after 60 s is left alone — never forced.
    func quitNext() {
        guard focused, let a = queue.first else { queue = []; status = nil; return }
        if protected(a) || excluded.contains(a.bundleIdentifier ?? "") { queue.removeFirst(); return quitNext() }   // marked keep / critical since the session began
        status = "Saving and quitting \(a.localizedName ?? "app") · \(total - queue.count + 1) of \(total)"
        a.terminate()
        let started = Date()
        func check() {
            guard queue.first === a else { return }             // cancelled by Bring Back
            if a.isTerminated || Date().timeIntervalSince(started) > 60 {
                queue.removeFirst()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.quitNext() }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: check)
            }
        }
        check()
    }

    /// Relaunch or unhide every app in the session, one at a time, windows restored; hidden ones stay hidden.
    func open(_ s: Session) {
        queue = []; status = nil; focused = false
        relaunch(ArraySlice(s["apps"] as? [[String: Any]] ?? []))
    }

    /// The whole main display, silently, via the system's own screencapture. Needs Screen Recording once.
    func snapshot() -> String? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH.mm.ss"
        let path = folder.appendingPathComponent("session-\(f.string(from: Date())).png").path
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); p.arguments = ["-x", "-t", "png", path]
        do { try p.run(); p.waitUntilExit() } catch { return nil }
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }
    /// Keeps the newest snapshot and one spare; anything older goes. (Names are timestamps, so they sort by age.)
    func pruneSnapshots() {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasPrefix("session-") }.sorted()
        for name in names.dropLast(2) { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
    }
    func relaunch(_ rest: ArraySlice<[String: Any]>) {
        guard let e = rest.first else { return }
        if let path = e["path"] as? String {
            let hidden = e["hidden"] as? Bool ?? false
            if let a = ws.runningApplications.first(where: { $0.bundleURL?.path == path }) {
                if !hidden { a.unhide() }
            } else {
                let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = false; cfg.hides = hidden
                if Bundle(path: path)?.bundleIdentifier == chrome { cfg.arguments = ["--restore-last-session"] }   // tabs back even if Chrome's own setting is off
                ws.openApplication(at: URL(fileURLWithPath: path), configuration: cfg)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { self.relaunch(rest.dropFirst()) }
    }

    /// Session apps still open after their turn: usually a save prompt waiting for you.
    func stragglers() -> [NSRunningApplication] {
        guard focused, !hideMode else { return [] }
        let waiting = Set(queue.map(\.processIdentifier))
        let paths = Set((sessions.first?["apps"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String })
        return ws.runningApplications.filter { paths.contains($0.bundleURL?.path ?? "") && !$0.isHidden && !protected($0) && !waiting.contains($0.processIdentifier) }
    }

    func toggle() {
        item.menu?.cancelTracking()
        if !focused { return park(quit: !hideMode) }
        if let s = sessions.first { open(s) } else { focused = false }
    }
    /// ~0.7 s at 60 fps, ease-out; runs in common modes so it plays even with the menu open.
    var anim: Timer?
    func animateIcon(to on: Bool) {
        anim?.invalidate()
        let start = Date(), duration = on ? 0.75 : 0.45
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] tm in
            let p = min(1, Date().timeIntervalSince(start) / duration), e = 1 - pow(1 - p, 3)
            self?.item.button?.image = on ? glyph(p, hunt: true) : glyph(1 - e)   // in: phased timeline · out: ease back
            if p >= 1 { tm.invalidate() }
        }
        RunLoop.main.add(t, forMode: .common); anim = t
    }
    func showMenu() { item.button?.performClick(nil) }

    func flip(_ list: ReferenceWritableKeyPath<Focus, [String]>, _ id: String) -> Bool {
        self[keyPath: list] = self[keyPath: list].contains(id) ? self[keyPath: list].filter { $0 != id } : self[keyPath: list] + [id]
        button?.needsDisplay = true
        return self[keyPath: list].contains(id)
    }

    @objc func pick() {
        let p = NSOpenPanel()
        p.directoryURL = URL(fileURLWithPath: "/Applications"); p.allowedContentTypes = [.applicationBundle]
        p.allowsMultipleSelection = true; p.prompt = "Add"; p.message = "Choose apps Focus must never quit"
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK else { return }
        for url in p.urls { if let id = Bundle(url: url)?.bundleIdentifier, !neverClose.contains(id) { neverClose.append(id) } }
    }
    @objc func reopen(_ s: NSMenuItem) { open(sessions[s.tag]) }
    @objc func forget(_ s: NSMenuItem) { sessions.remove(at: s.tag) }
    @objc func snaps() { snapshots.toggle() }
    @objc func viewShot(_ s: NSMenuItem) { if let p = s.representedObject as? String { ws.open(URL(fileURLWithPath: p)) } }
    @objc func hiding() { hideMode.toggle() }
    @objc func windows() { keepWindows.toggle() }
    @objc func look() { stragglers().first?.activate() }       // bring the save prompt forward; never force
    @objc func showNever() {
        never.reload()
        if neverWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: NeverView(m: never)))
            w.title = "Critical System Processes"; w.styleMask = [.titled, .closable]; w.isReleasedWhenClosed = false; w.center()
            neverWindow = w
        }
        NSApp.activate(ignoringOtherApps: true); neverWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func login() {
        let s = SMAppService.mainApp
        try? (s.status == .enabled ? s.unregister() : s.register())
    }
    @objc func bye() { NSApp.terminate(nil) }

    // MARK: menu (rebuilt each time it opens, so it never goes stale)

    func appIcon(_ path: String) -> NSImage { let i = ws.icon(forFile: path); i.size = NSSize(width: 16, height: 16); return i }
    func appName(_ path: String) -> String { FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "") }
    func apps(_ n: Int) -> String { n == 1 ? "1 app" : "\(n) apps" }
    func path(_ id: String) -> String? { ws.urlForApplication(withBundleIdentifier: id)?.path }

    func menuNeedsUpdate(_ m: NSMenu) {
        m.removeAllItems()
        @discardableResult
        func add(_ title: String, _ action: Selector?, image: NSImage? = nil, to menu: NSMenu? = nil) -> NSMenuItem {
            let i = (menu ?? m).addItem(withTitle: title, action: action, keyEquivalent: "")
            i.target = self; i.image = image
            return i
        }
        func header(_ t: String, in menu: NSMenu? = nil) {
            if #available(macOS 14, *) { (menu ?? m).addItem(.sectionHeader(title: t)) } else { add(t, nil, to: menu).isEnabled = false }
        }
        func view(_ v: NSView, in menu: NSMenu? = nil) { let i = NSMenuItem(); i.view = v; (menu ?? m).addItem(i) }

        mem = memoryByPid(); hosts = claudeHosts(); autoKeepClaudeHosts()
        if let status { header(status) }
        if focused, let shot = sessions.first?["shot"] as? String, let img = NSImage(contentsOfFile: shot) {
            header("What you were doing — click to open")
            let w = menuWidth - 28, h = (w * img.size.height / max(img.size.width, 1)).rounded()
            view(Thumb(img, NSSize(width: w, height: h)) { [unowned self] in self.ws.open(URL(fileURLWithPath: shot)) })
            m.addItem(.separator())
        }

        // Keep open — this session's picks.
        header(focused ? "In session · kept open" : "Keep open this session — click to choose")
        let running = apps().compactMap { a in a.bundleIdentifier.flatMap { id in a.bundleURL.map { (id, $0.path) } } }
        let idle = excluded.filter { id in !running.contains { $0.0 == id } && !neverClose.contains(id) }.compactMap { id in path(id).map { (id, $0) } }
        for (id, p) in running + idle {
            let size = ws.runningApplications.first { $0.bundleIdentifier == id }.map(memory) ?? 0
            let claudeHere = ws.runningApplications.contains { $0.bundleIdentifier == id && hosts.contains($0.processIdentifier) }
            let detail = [claudeHere ? "Claude is here" : nil, size > 0 ? gb(size) : nil].compactMap { $0 }.joined(separator: " · ")
            view(AppRow(appName(p), appIcon(p), detail: detail, on: excluded.contains(id)) { [unowned self] in self.flip(\.excluded, id) })
        }

        // Critical system processes — never quit or hidden by Focus. Click to take one off; it moves up next time.
        m.addItem(.separator())
        header("Critical System Processes — never quit")
        for id in neverClose {
            guard let p = path(id) else { continue }
            view(AppRow(appName(p), appIcon(p), on: true, onMark: "lock.circle.fill") { [unowned self] in self.flip(\.neverClose, id) })
        }
        add("Add or remove…", #selector(showNever), image: symbol("plus.circle"))

        let left = stragglers()
        if !left.isEmpty {                                      // shown only when something is still eating memory
            m.addItem(.separator())
            add("Still open — probably a save prompt: " + left.compactMap(\.localizedName).joined(separator: ", "),
                #selector(look), image: symbol("exclamationmark.bubble"))
        }

        m.addItem(.separator())
        if !sessions.isEmpty {
            let past = add("Past sessions", nil, image: symbol("clock.arrow.circlepath")), sub = NSMenu()
            for (n, s) in sessions.enumerated() {
                let list = s["apps"] as? [[String: Any]] ?? []
                let date = (s["date"] as? Date).map { when.string(from: $0) } ?? "?"
                let i = add("\(date) · \(apps(list.count))", nil, to: sub), one = NSMenu()
                for p in list.compactMap({ $0["path"] as? String }) { add(appName(p), nil, image: appIcon(p), to: one) }
                one.addItem(.separator())
                if let shot = s["shot"] as? String, FileManager.default.fileExists(atPath: shot) { add("View snapshot", #selector(viewShot), image: symbol("photo"), to: one).representedObject = shot }
                add("Open all", #selector(reopen), image: symbol("arrow.up.forward.app"), to: one).tag = n
                add("Delete", #selector(forget), image: symbol("trash"), to: one).tag = n
                i.submenu = one
            }
            past.submenu = sub
        }
        let settings = add("Settings", nil, image: symbol("gearshape")), sub = NSMenu()
        add("Hide apps instead of quitting", #selector(hiding), to: sub).state = hideMode ? .on : .off
        add("Take a snapshot when a session starts", #selector(snaps), to: sub).state = snapshots ? .on : .off
        add("Reopen windows as they were", #selector(windows), to: sub).state = keepWindows ? .on : .off
        add("Open at login", #selector(login), to: sub).state = SMAppService.mainApp.status == .enabled ? .on : .off
        sub.addItem(.separator())
        add("⌘⇧E opens this menu", nil, to: sub).isEnabled = false
        add("Quit Focus", #selector(bye), image: symbol("power"), to: sub)
        settings.submenu = sub

        m.addItem(.separator())
        let b = BigButton(
            title: { [unowned self] in self.focused ? "End Session" : "Start Session Now" },
            caption: { [unowned self] in
                if self.focused {
                    let n = self.apps((self.sessions.first?["apps"] as? [Any])?.count ?? 0)
                    return self.queue.isEmpty ? "Reopens \(n) as they were" : "Stops quitting and reopens \(n) as they were"
                }
                let out = self.leaving()
                let kept = self.ws.runningApplications.filter { $0.activationPolicy == .regular && !self.system($0) }.count - out.count
                if out.isEmpty { return "Nothing to \(self.hideMode ? "hide" : "quit") — everything is kept" }
                if self.hideMode { return "Hides \(self.apps(out.count)) · keeps \(kept)" }
                return "Saves and quits \(self.apps(out.count)) · frees ~\(gb(out.reduce(0) { $0 + self.memory($1) })) · keeps \(kept)"
            },
            action: { [unowned self] in self.toggle() })
        button = b; view(b)
    }
}

/// The Never close window: every app Focus could touch, with a switch. Switched on = Focus never quits or hides it.
final class NeverModel: ObservableObject {
    struct Entry: Identifiable { let id: String, name: String, icon: NSImage, running: Bool }
    unowned let f: Focus
    @Published var on: Set<String> = []
    @Published var entries: [Entry] = []
    init(_ f: Focus) { self.f = f }
    func reload() {
        on = Set(f.neverClose)
        let running = Set(f.candidates())
        var seen = Set<String>()
        entries = (f.neverClose + f.candidates().sorted { (f.path($0).map(f.appName) ?? "") < (f.path($1).map(f.appName) ?? "") })
            .filter { seen.insert($0).inserted }
            .compactMap { id in f.path(id).map { Entry(id: id, name: f.appName($0), icon: f.ws.icon(forFile: $0), running: running.contains(id)) } }
    }
    func set(_ id: String, _ v: Bool) {
        f.neverClose = v ? f.neverClose + [id] : f.neverClose.filter { $0 != id }
        on = Set(f.neverClose)
    }
    func add() { f.pick(); reload() }
}

struct NeverView: View {
    @ObservedObject var m: NeverModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Critical System Processes").font(.system(size: 20, weight: .semibold))
                Text("Focus never quits or hides the apps switched on here — things that must always run, like Wispr Flow or Mu. macOS's own apps, menu bar–only apps and Focus itself are always safe.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            List(m.entries) { e in
                HStack(spacing: 10) {
                    Image(nsImage: e.icon).resizable().frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.name)
                        if !e.running { Text("Not open").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { m.on.contains(e.id) }, set: { m.set(e.id, $0) })).toggleStyle(.switch).labelsHidden()
                }
                .padding(.vertical, 3)
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
            HStack {
                Button("Add App…") { m.add() }
                Spacer()
                Button("Done") { NSApp.keyWindow?.close() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440, height: 560)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)                             // no Dock icon, not in Cmd-Tab

// One Focus at a time: a second copy (double launch, login item + manual open…) quits at once.
let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.labern.focus").filter { $0 != .current }
if !others.isEmpty && !CommandLine.arguments.contains("--selftest") { print("Focus is already running (pid \(others[0].processIdentifier))"); exit(0) }

/// `Focus --selftest`: the real session path, on TextEdit only, with its own settings store. Aborts before
/// touching anything if the session would include any other app.
if CommandLine.arguments.contains("--selftest") {
    let suite = "com.labern.focus.selftest"
    UserDefaults.standard.removePersistentDomain(forName: suite)
    let t = Focus(store: UserDefaults(suiteName: suite)!)
    func say(_ s: String) { print("selftest:", s); fflush(stdout) }
    func later(_ s: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: f) }
    let edit = "com.apple.TextEdit"
    later(0.5) {
        t.excluded = t.apps().compactMap(\.bundleIdentifier).filter { $0 != edit }
        let out = t.leaving().compactMap(\.bundleIdentifier)
        guard out == [edit] else { say("ABORT — would quit \(out)"); exit(1) }
        say("session would quit only TextEdit ✓  (protected: \(t.ws.runningApplications.filter(t.protected).compactMap(\.localizedName)))")
        t.park(quit: true)
        let shot = t.sessions.first?["shot"] as? String
        say("snapshot: \(shot.map { "\($0) (\((try? FileManager.default.attributesOfItem(atPath: $0)[.size]) ?? 0) bytes)" } ?? "NONE")")
        later(6) {
            let gone = !t.ws.runningApplications.contains { $0.bundleIdentifier == edit }
            say("TextEdit quit: \(gone ? "✓" : "✗ still running")  in session: \(t.focused)")
            t.toggle()
            later(4) {
                let back = t.ws.runningApplications.contains { $0.bundleIdentifier == edit }
                say("TextEdit back: \(back ? "✓" : "✗")  in session: \(t.focused)")
                say("snapshot kept after restore: \(shot.map { FileManager.default.fileExists(atPath: $0) ? "✓" : "✗ gone" } ?? "n/a")")
                for _ in 0..<3 { _ = t.snapshot(); Thread.sleep(forTimeInterval: 1.1); t.pruneSnapshots() }
                let left = (try? FileManager.default.contentsOfDirectory(atPath: t.folder.path))?.filter { $0.hasPrefix("session-") }.count ?? -1
                say("after 4 snapshots, kept: \(left) \(left == 2 ? "✓ (newest + one spare)" : "✗")")
                try? FileManager.default.removeItem(at: t.folder)
                UserDefaults.standard.removePersistentDomain(forName: suite)
                exit(0)
            }
        }
    }
    app.run()
}
let focus = Focus()

// Global hotkeys via Carbon: the only route that needs no Accessibility permission.
var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
    var hk = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
    DispatchQueue.main.async { hk.id == 1 ? focus.toggle() : focus.showMenu() }
    return noErr
}, 1, &spec, nil, nil)
_ = hotkey(1, kVK_ANSI_F, cmdKey | shiftKey)                    // ⌘⇧F: start a session / bring it all back
_ = hotkey(2, kVK_ANSI_E, cmdKey | shiftKey)                    // ⌘⇧E: open the menu
app.run()
