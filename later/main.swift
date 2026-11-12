// Later — park every app except the ones you're using, bring them back on one key.
// Menu bar only. No dependencies, no permissions. Build: ./build.sh
import AppKit
import Carbon.HIToolbox

final class Later: NSObject, NSMenuDelegate {
    let ws = NSWorkspace.shared, store = UserDefaults.standard
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var recent: [pid_t] = []                                  // most recently active first

    var parked: [String] {                                    // bundle paths waiting to come back
        get { store.stringArray(forKey: "parked") ?? [] }
        set { store.set(newValue, forKey: "parked"); icon() }
    }
    var pins: [String] {                                      // bundle ids that always stay
        get { store.stringArray(forKey: "pins") ?? [] }
        set { store.set(newValue, forKey: "pins") }
    }

    override init() {
        super.init()
        let menu = NSMenu(); menu.delegate = self; item.menu = menu; icon()
        // Seed the recency order from window z-order, then track activations live.
        let wins = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in wins where w[kCGWindowLayer as String] as? Int == 0 {
            if let p = w[kCGWindowOwnerPID as String] as? pid_t, !recent.contains(p) { recent.append(p) }
        }
        ws.notificationCenter.addObserver(self, selector: #selector(activated), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    @objc func activated(_ n: Notification) {
        guard let p = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier else { return }
        recent.removeAll { $0 == p }; recent.insert(p, at: 0)
    }

    func icon() {
        item.button?.image = NSImage(systemSymbolName: parked.isEmpty ? "moon.zzz" : "moon.zzz.fill", accessibilityDescription: "Later")
    }

    /// Everything in Cmd-Tab except Finder (which can't leave it).
    func apps() -> [NSRunningApplication] {
        ws.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != "com.apple.finder" }
    }

    /// Pinned apps if any are running, otherwise the two most recently used.
    func keepers(_ apps: [NSRunningApplication]) -> [NSRunningApplication] {
        let pinned = apps.filter { pins.contains($0.bundleIdentifier ?? "") }
        if !pinned.isEmpty { return pinned }
        func rank(_ a: NSRunningApplication) -> Int { recent.firstIndex(of: a.processIdentifier) ?? .max }
        return Array(apps.sorted { rank($0) < rank($1) }.prefix(2))
    }

    func park(quit: Bool) {
        let all = apps(), keep = keepers(all)
        let out = all.filter { !keep.contains($0) }
        parked = Array(Set(parked + out.compactMap { $0.bundleURL?.path }))
        for a in out { if quit { a.terminate() } else { a.hide() } }   // terminate() is the polite quit: unsaved work still prompts
    }

    func restore() {
        let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = false
        for path in parked {
            if let a = ws.runningApplications.first(where: { $0.bundleURL?.path == path }) { a.unhide() }
            else { ws.openApplication(at: URL(fileURLWithPath: path), configuration: cfg) }
        }
        parked = []
    }

    func toggle(quit: Bool) { if parked.isEmpty { park(quit: quit) } else { restore() } }
    @objc func quitRest() { toggle(quit: true) }
    @objc func hideRest() { toggle(quit: false) }
    @objc func bye() { NSApp.terminate(nil) }
    @objc func pin(_ s: NSMenuItem) {
        guard let id = s.representedObject as? String else { return }
        pins = pins.contains(id) ? pins.filter { $0 != id } : pins + [id]
    }

    func menuNeedsUpdate(_ m: NSMenu) {
        m.removeAllItems()
        func add(_ title: String, _ action: Selector?, _ key: String = "") -> NSMenuItem {
            let i = m.addItem(withTitle: title, action: action, keyEquivalent: key)
            i.target = self; i.keyEquivalentModifierMask = [.control, .option, .command]
            return i
        }
        let all = apps(), keep = keepers(all)
        if parked.isEmpty {
            _ = add("Quit the rest", #selector(quitRest), "l")
            _ = add("Hide the rest", #selector(hideRest), "h")
        } else {
            _ = add("Bring back \(parked.count) apps", #selector(quitRest), "l")
        }
        m.addItem(.separator())
        _ = add("Keep (click to pin)", nil)
        for a in all {                                        // ✓ pinned, – kept automatically
            let i = add(a.localizedName ?? "?", #selector(pin))
            i.representedObject = a.bundleIdentifier
            i.state = pins.contains(a.bundleIdentifier ?? "") ? .on : keep.contains(a) ? .mixed : .off
        }
        m.addItem(.separator())
        _ = add("Quit Later", #selector(bye))
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)                           // no Dock icon, not in Cmd-Tab
let later = Later()

// Global hotkeys via Carbon: the only route that needs no Accessibility permission.
// ⌃⌥⌘L quit/restore, ⌃⌥⌘H hide/restore.
var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
    var id = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
    let quit = id.id == 1
    DispatchQueue.main.async { later.toggle(quit: quit) }
    return noErr
}, 1, &spec, nil, nil)
for (id, key) in [(1, kVK_ANSI_L), (2, kVK_ANSI_H)] {
    var ref: EventHotKeyRef?
    RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey | cmdKey), EventHotKeyID(signature: 0x4C54_5221, id: UInt32(id)), GetEventDispatcherTarget(), 0, &ref)
}
app.run()
