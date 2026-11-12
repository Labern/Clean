// Focus — quit every Dock / ⌘⇥ app except the ones you keep, so their RAM, CPU and GPU go to the work.
// Same key again brings them all back exactly as they were. Menu bar apps (Wispr Flow etc.) are never touched.
// Menu bar only. One file, no dependencies, no permissions. Build: ./build.sh
//   ⌃⌥⌘F      quit everything not kept         (again: bring it all back)
//   ⌃⌥⌘H      hide everything not kept         (again: bring it all back)
//   ⌃⌥⌘K      exclude / include the app you're in
//   ⌘⇥ ⌘⇧⇥   while focused: cycle only what's still open — the system switcher is off until you come back
import AppKit
import Carbon.HIToolbox
import ServiceManagement

// Private SkyLight call, the same one AltTab uses: switches the Dock's ⌘⇥ (id 1) and ⌘⇧⇥ (id 2) off or on.
// The setting outlives the process, so it is switched back on at every launch, quit and signal.
// Resolved at runtime from the shared cache, so the build needs no private-framework stubs.
let setSymbolicHotKey: (@convention(c) (Int32, Bool) -> Int32)? = {
    guard let lib = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
          let fn = dlsym(lib, "CGSSetSymbolicHotKeyEnabled") else { return nil }
    return unsafeBitCast(fn, to: (@convention(c) (Int32, Bool) -> Int32).self)
}()
func systemSwitcher(_ on: Bool) { _ = setSymbolicHotKey?(1, on); _ = setSymbolicHotKey?(2, on) }

func hotkey(_ id: UInt32, _ key: Int, _ mods: Int) -> EventHotKeyRef? {
    var ref: EventHotKeyRef?
    RegisterEventHotKey(UInt32(key), UInt32(mods), EventHotKeyID(signature: 0x464F_4355, id: id), GetEventDispatcherTarget(), 0, &ref)
    return ref
}
func symbol(_ name: String) -> NSImage? { NSImage(systemSymbolName: name, accessibilityDescription: nil) }

/// The menu bar mark: a viewfinder ring with a centre dot. Open brackets at rest; a closed ring and a
/// bigger dot while focused. Template image, so it follows light / dark menu bars.
func glyph(focused: Bool) -> NSImage {
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
        let ring = NSBezierPath(ovalIn: r.insetBy(dx: 2.5, dy: 2.5)); ring.lineWidth = 1.6
        if !focused { ring.setLineDash([7.4, 2.6], count: 2, phase: 2.6) }   // four gaps → viewfinder brackets
        ring.stroke()
        NSBezierPath(ovalIn: r.insetBy(dx: focused ? 6 : 7.25, dy: focused ? 6 : 7.25)).fill()
        return true
    }
    img.isTemplate = true
    return img
}

typealias Session = [String: Any]                              // "date": Date, "apps": [["path": String, "hidden": Bool]]

final class Focus: NSObject, NSMenuDelegate {
    let ws = NSWorkspace.shared, store = UserDefaults.standard
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var tabKeys: [EventHotKeyRef?] = []                         // our ⌘⇥ / ⌘⇧⇥, registered only while focused
    let when: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; f.doesRelativeDateFormatting = true; return f
    }()

    var sessions: [Session] {                                   // newest first, last 12 kept
        get { store.array(forKey: "sessions") as? [Session] ?? [] }
        set { store.set(Array(newValue.prefix(12)), forKey: "sessions") }
    }
    var excluded: [String] {                                    // bundle ids that never get cleared
        get { store.stringArray(forKey: "excluded") ?? [] }
        set { store.set(newValue, forKey: "excluded") }
    }
    var focused: Bool {
        get { store.bool(forKey: "focused") }
        set { store.set(newValue, forKey: "focused"); refresh() }
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

    override init() {
        super.init()
        let menu = NSMenu(); menu.delegate = self; item.menu = menu
        if !store.bool(forKey: "setUp") { keepWindows = true; store.set(true, forKey: "setUp") }
        systemSwitcher(true); refresh()                         // also heals a crash mid-focus
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in systemSwitcher(true) }
    }

    func refresh() {
        item.button?.image = glyph(focused: focused)
        guard focused == tabKeys.isEmpty else { return }
        systemSwitcher(!focused)
        if focused { tabKeys = [hotkey(4, kVK_Tab, cmdKey), hotkey(5, kVK_Tab, cmdKey | shiftKey)] }
        else { tabKeys.forEach { if let k = $0 { UnregisterEventHotKey(k) } }; tabKeys = [] }
    }

    /// Everything in the Dock / ⌘⇥ except Finder (which can't leave). Menu bar apps are `.accessory`: never listed, never touched.
    func apps() -> [NSRunningApplication] {
        ws.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != "com.apple.finder" }
    }

    // MARK: focus / unfocus

    func park(quit: Bool) {
        let out = apps().filter { !excluded.contains($0.bundleIdentifier ?? "") }
        guard !out.isEmpty else { return }
        sessions.insert(["date": Date(), "apps": out.compactMap { a in a.bundleURL.map { ["path": $0.path, "hidden": a.isHidden] as [String: Any] } }], at: 0)
        for a in out { if quit { a.terminate() } else { a.hide() } }   // polite quit: unsaved work still prompts
        focused = true
    }

    /// Relaunch or unhide every app in the session, windows restored; whatever was hidden stays hidden.
    func open(_ s: Session) {
        for e in s["apps"] as? [[String: Any]] ?? [] {
            guard let path = e["path"] as? String else { continue }
            let hidden = e["hidden"] as? Bool ?? false
            if let a = ws.runningApplications.first(where: { $0.bundleURL?.path == path }) {
                if !hidden { a.unhide() }
            } else {
                let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = false; cfg.hides = hidden
                ws.openApplication(at: URL(fileURLWithPath: path), configuration: cfg)
            }
        }
        focused = false
    }

    /// Session apps that didn't quit: an unsaved-changes prompt, a hang, or an app that drops to the menu bar instead of quitting.
    func stragglers() -> [NSRunningApplication] {
        guard focused else { return [] }
        let paths = Set((sessions.first?["apps"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String })
        return ws.runningApplications.filter { paths.contains($0.bundleURL?.path ?? "") && !$0.isHidden }
    }

    func toggle(quit: Bool) {
        if !focused { return park(quit: quit) }
        if let s = sessions.first { open(s) } else { focused = false }
    }

    /// Fixed order, so holding ⌘ and tapping ⇥ walks through every open app; with two it just flips.
    func cycle(_ step: Int) {
        let ring = apps().filter { !$0.isHidden || $0.isActive }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        guard !ring.isEmpty else { return }
        let i = ring.firstIndex { $0.isActive } ?? -step
        // Activating through Launch Services is honoured on macOS 14+, where a background app's activate() is refused.
        guard let url = ring[(i + step + ring.count) % ring.count].bundleURL else { return }
        ws.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func exclude(_ id: String) { excluded = excluded.contains(id) ? excluded.filter { $0 != id } : excluded + [id] }
    func excludeFront() {
        guard let id = ws.frontmostApplication?.bundleIdentifier else { return }
        exclude(id)
        item.button?.image = symbol(excluded.contains(id) ? "pin.fill" : "pin.slash")   // brief confirmation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.refresh() }
    }

    @objc func quitRest() { toggle(quit: true) }
    @objc func hideRest() { toggle(quit: false) }
    @objc func flip(_ s: NSMenuItem) { if let id = s.representedObject as? String { exclude(id) } }
    @objc func reopen(_ s: NSMenuItem) { open(sessions[s.tag]) }
    @objc func forget(_ s: NSMenuItem) { sessions.remove(at: s.tag) }
    @objc func windows() { keepWindows.toggle() }
    @objc func kill() { stragglers().forEach { $0.forceTerminate() } }
    @objc func login() {
        let s = SMAppService.mainApp
        try? (s.status == .enabled ? s.unregister() : s.register())
    }
    @objc func bye() { NSApp.terminate(nil) }

    // MARK: menu (rebuilt each time it opens, so it never goes stale)

    func appIcon(_ path: String) -> NSImage { let i = ws.icon(forFile: path); i.size = NSSize(width: 16, height: 16); return i }

    func menuNeedsUpdate(_ m: NSMenu) {
        m.removeAllItems()
        @discardableResult
        func add(_ title: String, _ action: Selector?, key: String = "", image: NSImage? = nil, to menu: NSMenu? = nil) -> NSMenuItem {
            let i = (menu ?? m).addItem(withTitle: title, action: action, keyEquivalent: key)
            i.target = self; i.image = image; i.keyEquivalentModifierMask = [.control, .option, .command]
            return i
        }
        func header(_ t: String) {
            if #available(macOS 14, *) { m.addItem(.sectionHeader(title: t)) } else { add(t, nil) }
        }

        if focused, let n = (sessions.first?["apps"] as? [Any])?.count {
            add("Bring back \(n) apps", #selector(quitRest), key: "f", image: symbol("arrow.uturn.backward.circle"))
            let left = stragglers()
            if !left.isEmpty {                                  // shown only when something is still eating memory
                add("Force quit \(left.count) still running: " + left.compactMap(\.localizedName).joined(separator: ", "),
                    #selector(kill), image: symbol("exclamationmark.triangle"))
            }
        } else {
            add("Focus — quit the rest", #selector(quitRest), key: "f", image: glyph(focused: true))
            add("Focus — hide the rest", #selector(hideRest), key: "h", image: symbol("eye.slash"))
        }

        m.addItem(.separator())
        header("Keep open · menu bar apps are never touched")
        let running = apps().compactMap { a in a.bundleIdentifier.flatMap { id in a.bundleURL.map { (id, $0.path) } } }
        let idle = excluded.filter { id in !running.contains { $0.0 == id } }   // excluded but not running: still listed, so it can be un-excluded
            .compactMap { id in ws.urlForApplication(withBundleIdentifier: id).map { (id, $0.path) } }
        for (id, path) in running + idle {
            let i = add(FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: ""), #selector(flip), image: appIcon(path))
            i.representedObject = id; i.state = excluded.contains(id) ? .on : .off
        }
        add("Toggle the app you're in", nil, key: "k").isEnabled = false

        if !sessions.isEmpty {
            m.addItem(.separator())
            header("Sessions")
            for (n, s) in sessions.enumerated() {
                let list = s["apps"] as? [[String: Any]] ?? []
                let date = (s["date"] as? Date).map { when.string(from: $0) } ?? "?"
                let i = add("\(date) · \(list.count) apps", nil, image: symbol("clock.arrow.circlepath"))
                let sub = NSMenu()
                for path in list.compactMap({ $0["path"] as? String }) {
                    add(FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: ""), nil, image: appIcon(path), to: sub)
                }
                sub.addItem(.separator())
                add("Open all", #selector(reopen), image: symbol("arrow.up.forward.app"), to: sub).tag = n
                add("Delete", #selector(forget), image: symbol("trash"), to: sub).tag = n
                i.submenu = sub
            }
        }

        m.addItem(.separator())
        add("Reopen windows as they were", #selector(windows)).state = keepWindows ? .on : .off
        add("Open at login", #selector(login)).state = SMAppService.mainApp.status == .enabled ? .on : .off
        add("Quit Focus", #selector(bye), image: symbol("power"))
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)                             // no Dock icon, not in Cmd-Tab
let focus = Focus()

// Global hotkeys via Carbon: the only route that needs no Accessibility permission.
var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
    var hk = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
    DispatchQueue.main.async {
        switch hk.id {
        case 1: focus.toggle(quit: true)
        case 2: focus.toggle(quit: false)
        case 3: focus.excludeFront()
        case 4: focus.cycle(1)
        default: focus.cycle(-1)
        }
    }
    return noErr
}, 1, &spec, nil, nil)
for (id, key) in [(1, kVK_ANSI_F), (2, kVK_ANSI_H), (3, kVK_ANSI_K)] { _ = hotkey(UInt32(id), key, controlKey | optionKey | cmdKey) }
for sig in [SIGTERM, SIGINT, SIGHUP] { signal(sig) { _ in systemSwitcher(true); exit(0) } }   // never leave ⌘⇥ dead
app.run()
