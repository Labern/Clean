// Shell.swift — a native macOS client for WhatsApp.
//
// It does not reimplement WhatsApp and does not touch the protocol: it loads the
// real web.whatsapp.com in a WKWebView, so the account is linked exactly as the
// browser links it and there is no ban risk. What it adds is everything the
// browser tab cannot give: a real Dock tile with an unread badge, real macOS
// notifications, a themed UI, the furniture he does not want removed, ⌘1–9 jumps
// to pinned chats, a global summon hotkey, and a privacy blur for screen-sharing.
//
// The app's NAME lives in exactly one place — build.sh — and is read back out of
// the bundle at runtime, so renaming it never touches this file. Everything
// injected into the page is namespaced `shell` for the same reason.
//
// THE ONE THING NOT TO BREAK: cfg.websiteDataStore must stay `.default()`.
// That is what makes the WhatsApp link survive quitting the app. A
// non-persistent store means re-scanning the QR code on every launch.
import Cocoa
import WebKit
import Carbon.HIToolbox
import UserNotifications
import UniformTypeIdentifiers

// MARK: - configuration

let kHome = URL(string: "https://web.whatsapp.com/")!
let kAllowedHosts: Set<String> = ["web.whatsapp.com"]

// Safari's own UA. WKWebView is WebKit, so claiming Safari is honest about the
// engine and keeps WhatsApp on its supported path — claiming Chrome would opt us
// into Blink-specific code paths this engine does not have.
let kDefaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
                        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

let kThemes: [(title: String, id: String)] = [
    ("Stock",     "stock"),
    ("Midnight",  "midnight"),
    ("PARADOX",   "paradox"),
    ("MONOGRAPH", "monograph"),
]

// Order is the order they appear in the View menu.
let kHideables: [(title: String, key: String, defaultOn: Bool)] = [
    ("Hide Status",      "status",      true),
    ("Hide Channels",    "channels",    true),
    ("Hide Communities", "communities", true),
    ("Hide Media",       "media",       true),
    ("Hide Meta AI",     "metaai",      true),
    ("Hide Promos & Nags", "promos",    true),
    ("Hide Calls",       "calls",       false),
    ("Hide Filter Chips", "filters",    false),
    ("Hide Archived",    "archived",    false),
]

let kPinCount = 9

// ⌃⌥⌘W — summon or dismiss from anywhere. Deliberately a three-modifier chord:
// a global hotkey must not shadow a character or a common app shortcut.
let kHotKeyCode = UInt32(kVK_ANSI_W)
let kHotKeyMods = UInt32(cmdKey | optionKey | controlKey)

// MARK: - settings

/// Everything the user can change, persisted in UserDefaults. Additive only —
/// new keys must default sensibly so an older settings file still loads whole.
struct Settings {
    var theme: String
    var hide: [String: Bool]
    var privacy: Bool
    var pins: [String]
    var zoom: Double
    var notifications: Bool

    static func load() -> Settings {
        let d = UserDefaults.standard
        var hide: [String: Bool] = [:]
        let stored = d.dictionary(forKey: "hide") as? [String: Bool]
        for h in kHideables { hide[h.key] = stored?[h.key] ?? h.defaultOn }

        var pins = d.stringArray(forKey: "pins") ?? []
        if pins.count < kPinCount { pins += Array(repeating: "", count: kPinCount - pins.count) }

        return Settings(
            theme: d.string(forKey: "theme") ?? "paradox",
            hide: hide,
            privacy: d.bool(forKey: "privacy"),
            pins: Array(pins.prefix(kPinCount)),
            zoom: d.object(forKey: "zoom") as? Double ?? 1.0,
            notifications: d.object(forKey: "notifications") as? Bool ?? true
        )
    }

    func save() {
        let d = UserDefaults.standard
        d.set(theme, forKey: "theme")
        d.set(hide, forKey: "hide")
        d.set(privacy, forKey: "privacy")
        d.set(pins, forKey: "pins")
        d.set(zoom, forKey: "zoom")
        d.set(notifications, forKey: "notifications")
    }
}

// MARK: - helpers

/// The app's own name, from the bundle — never hardcoded, so a rename in
/// build.sh propagates to every menu, alert and window title for free.
let kAppName: String = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
    ?? ProcessInfo.processInfo.processName

/// A string safely escaped as a JavaScript literal, including the quotes.
func jsLiteral(_ s: String) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: [s]),
          var out = String(data: data, encoding: .utf8) else { return "\"\"" }
    out.removeFirst(); out.removeLast()          // strip the enclosing [ ]
    return out
}

/// Carbon hot-key callbacks are C function pointers and cannot capture context.
private weak var gDelegate: AppDelegate?

// MARK: - app

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate,
                         WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate,
                         UNUserNotificationCenterDelegate {

    var window: NSWindow!
    var web: WKWebView!
    var settings = Settings.load()

    private var themeItems: [NSMenuItem] = []
    private var hideItems: [String: NSMenuItem] = [:]
    private var privacyItem: NSMenuItem!
    private var notifyItem: NSMenuItem!
    private var pinItems: [NSMenuItem] = []
    private var unpinMenu: NSMenu!
    private var hotKeyRef: EventHotKeyRef?
    private var notificationsReady = false

    // ---- lifecycle ----

    func applicationDidFinishLaunching(_ note: Notification) {
        gDelegate = self
        buildMenu()
        buildWindow()
        registerHotKey()
        prepareNotifications()
        NSApp.activate(ignoringOtherApps: true)
    }

    // A messenger should keep running with its window closed — ⌃⌥⌘W brings it
    // back, and closing a window is not a request to sign out.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWindow() }
        return true
    }

    func applicationWillTerminate(_ note: Notification) {
        if let z = web?.pageZoom { settings.zoom = Double(z) }
        settings.save()
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
    }

    // ---- window & web view ----

    private func buildWindow() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()      // persistent: the WhatsApp link survives quit
        cfg.userContentController.add(self, name: "shell")
        if #available(macOS 12.0, *) { cfg.preferences.isElementFullscreenEnabled = true }
        installUserScripts(into: cfg.userContentController)

        let v = WKWebView(frame: NSRect(x: 0, y: 0, width: 1180, height: 820), configuration: cfg)
        v.navigationDelegate = self
        v.uiDelegate = self
        v.allowsMagnification = true
        v.customUserAgent = UserDefaults.standard.string(forKey: "userAgent") ?? kDefaultUserAgent
        v.pageZoom = CGFloat(settings.zoom)
        v.setValue(false, forKey: "drawsBackground")   // no white flash before the page paints
        if #available(macOS 13.3, *) { v.isInspectable = true }
        self.web = v

        // A normal title bar, tinted to the theme. Not .fullSizeContentView:
        // WhatsApp's nav rail runs to the very top of its own layout, and the
        // traffic lights would sit on top of it.
        let w = NSWindow(contentRect: v.frame,
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = kAppName
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.contentView = v
        w.minSize = NSSize(width: 760, height: 520)
        w.setFrameAutosaveName("ShellMainWindow")
        w.isReleasedWhenClosed = false
        w.delegate = nil
        w.makeKeyAndOrderFront(nil)
        if w.frame.width < 700 { w.center() }
        self.window = w
        tintWindow()

        v.load(URLRequest(url: kHome))
    }

    /// Injected before WhatsApp's own bundle runs: the config, the stylesheet
    /// text, then shell.js. Rebuilt whenever settings change so that a reload
    /// comes up in the state he last chose rather than the launch state.
    private func installUserScripts(into ucc: WKUserContentController) {
        ucc.removeAllUserScripts()

        let hideJSON = (try? JSONSerialization.data(withJSONObject: settings.hide))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let config = """
        window.__SHELL_CONFIG = { theme: \(jsLiteral(settings.theme)), \
        hide: \(hideJSON), privacy: \(settings.privacy ? "true" : "false") };
        """

        let res = Bundle.main.resourceURL
        let css = (res?.appendingPathComponent("theme.css")).flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let js  = (res?.appendingPathComponent("shell.js")).flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""

        for source in [config, "window.__SHELL_CSS = \(jsLiteral(css));", js] {
            ucc.addUserScript(WKUserScript(source: source,
                                           injectionTime: .atDocumentStart,
                                           forMainFrameOnly: true))
        }
    }

    private func reinstallUserScripts() {
        guard let ucc = web?.configuration.userContentController else { return }
        installUserScripts(into: ucc)
    }

    /// The native title bar takes the theme's panel colour, so the window reads
    /// as one object rather than WhatsApp in a grey frame.
    private func tintWindow() {
        let colours: [String: NSColor] = [
            "paradox":   NSColor(srgbRed: 0x17/255.0, green: 0x13/255.0, blue: 0x31/255.0, alpha: 1),
            "monograph": NSColor(srgbRed: 0xf4/255.0, green: 0xf3/255.0, blue: 0xf1/255.0, alpha: 1),
            "midnight":  NSColor(srgbRed: 0x20/255.0, green: 0x2c/255.0, blue: 0x33/255.0, alpha: 1),
        ]
        if let c = colours[settings.theme] {
            window?.backgroundColor = c
            window?.appearance = NSAppearance(named: settings.theme == "monograph" ? .aqua : .darkAqua)
        } else {
            window?.backgroundColor = nil
            window?.appearance = nil
        }
    }

    private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if window == nil { buildWindow() } else { window.makeKeyAndOrderFront(nil) }
    }

    // ---- navigation policy ----

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.allow); return }
        // Anything that is not WhatsApp itself belongs in the real browser: links
        // friends send, the FAQ, OAuth pages. Keeping them out also means a
        // hostile link cannot navigate the logged-in session somewhere else.
        if let host = url.host, !kAllowedHosts.contains(host),
           url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = action.request.url, u.scheme == "https" || u.scheme == "http" {
            NSWorkspace.shared.open(u)
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyAllToPage()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        retryLater()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        retryLater()
    }

    /// Offline at launch, or the network dropped: keep trying quietly rather than
    /// leaving him at a blank window that needs a manual reload.
    private func retryLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self, let web = self.web else { return }
            if web.url == nil || web.url?.host == nil { web.load(URLRequest(url: kHome)) }
        }
    }

    // ---- uploads, downloads, camera & mic ----

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.begin { completionHandler($0 == .OK ? panel.urls : nil) }
    }

    @available(macOS 12.0, *)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        // Voice notes and calls need the mic; only ever for WhatsApp itself.
        decisionHandler(kAllowedHosts.contains(origin.host) ? .grant : .deny)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        var dest = dir.appendingPathComponent(suggestedFilename.isEmpty ? "whatsapp-download" : suggestedFilename)
        // Never overwrite: "photo.jpg" becomes "photo-2.jpg" rather than clobbering.
        if FileManager.default.fileExists(atPath: dest.path) {
            let base = dest.deletingPathExtension().lastPathComponent
            let ext = dest.pathExtension
            var n = 2
            repeat {
                let name = ext.isEmpty ? "\(base)-\(n)" : "\(base)-\(n).\(ext)"
                dest = dir.appendingPathComponent(name)
                n += 1
            } while FileManager.default.fileExists(atPath: dest.path) && n < 500
        }
        completionHandler(dest)
        download.progress.fileURL = dest
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = download.progress.fileURL else { return }
        notify(title: "Saved to Downloads", body: url.lastPathComponent, id: "dl-\(url.lastPathComponent)", chat: nil)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        notify(title: "Download failed", body: error.localizedDescription, id: "dl-fail", chat: nil)
    }

    // ---- page → native ----

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "notify":
            guard settings.notifications else { return }
            let title = body["title"] as? String ?? kAppName
            notify(title: title,
                   body: body["body"] as? String ?? "",
                   id: body["id"] as? String ?? UUID().uuidString,
                   chat: title)
        case "notify-close":
            if let id = body["id"] as? String {
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
            }
        case "badge":
            let n = (body["count"] as? Int) ?? 0
            NSApp.dockTile.badgeLabel = n > 0 ? String(n) : nil
        case "linked":
            applyAllToPage()
        default:
            break
        }
    }

    // ---- native → page ----

    private func js(_ code: String) {
        web?.evaluateJavaScript("window.__shell && (\(code))", completionHandler: nil)
    }

    private func applyAllToPage() {
        let hideJSON = (try? JSONSerialization.data(withJSONObject: settings.hide))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        js("__shell.applyTheme(\(jsLiteral(settings.theme)))")
        js("__shell.applyHide(\(hideJSON))")
        js("__shell.applyPrivacy(\(settings.privacy ? "true" : "false"))")
    }

    // ---- notifications ----

    private func prepareNotifications() {
        guard Bundle.main.bundleIdentifier != nil else { return }   // not in a bundle: skip
        let centre = UNUserNotificationCenter.current()
        centre.delegate = self
        centre.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            DispatchQueue.main.async { self?.notificationsReady = granted }
        }
    }

    private func notify(title: String, body: String, id: String, chat: String?) {
        guard notificationsReady else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let chat = chat { content.userInfo = ["chat": chat, "jsId": id] }
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    func userNotificationCenter(_ centre: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // WhatsApp already decides not to notify for the chat you are reading, so
        // anything that reaches here is worth showing even if we are frontmost.
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ centre: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        showWindow()
        if let jsId = info["jsId"] as? String {
            let chat = info["chat"] as? String ?? ""
            js("__shell.notificationClicked(\(jsLiteral(jsId)), \(jsLiteral(chat)))")
        }
        completionHandler()
    }

    // ---- global hot key ----

    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { gDelegate?.toggleVisibility() }
            return noErr
        }, 1, &spec, nil, nil)

        let id = EventHotKeyID(signature: OSType(0x53484C4C /* 'SHLL' */), id: 1)
        RegisterEventHotKey(kHotKeyCode, kHotKeyMods, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func toggleVisibility() {
        if NSApp.isActive, let w = window, w.isVisible {
            NSApp.hide(nil)
        } else {
            showWindow()
        }
    }

    // ---- menu actions ----

    @objc private func chooseTheme(_ sender: NSMenuItem) {
        settings.theme = kThemes[sender.tag].id
        settings.save()
        reinstallUserScripts()
        applyAllToPage()
        tintWindow()
        syncMenuState()
    }

    @objc private func cycleTheme(_ sender: Any?) {
        let i = kThemes.firstIndex { $0.id == settings.theme } ?? 0
        settings.theme = kThemes[(i + 1) % kThemes.count].id
        settings.save()
        reinstallUserScripts()
        applyAllToPage()
        tintWindow()
        syncMenuState()
    }

    @objc private func toggleHide(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        settings.hide[key] = !(settings.hide[key] ?? false)
        settings.save()
        reinstallUserScripts()
        applyAllToPage()
        syncMenuState()
    }

    @objc private func togglePrivacy(_ sender: Any?) {
        settings.privacy.toggle()
        settings.save()
        reinstallUserScripts()
        applyAllToPage()
        syncMenuState()
    }

    @objc private func toggleNotifications(_ sender: Any?) {
        settings.notifications.toggle()
        settings.save()
        syncMenuState()
    }

    @objc private func openPin(_ sender: NSMenuItem) {
        let name = settings.pins[sender.tag]
        guard !name.isEmpty else {
            alert("Nothing pinned to ⌘\(sender.tag + 1) yet.",
                  "Open a chat and choose Chats ▸ Pin This Chat.")
            return
        }
        js("__shell.openChat(\(jsLiteral(name)))")
    }

    /// Pin the conversation that is open, with no typing. Falls back to asking
    /// for the name only if the page will not tell us what is open.
    @objc private func pinCurrentChat(_ sender: Any?) {
        web?.evaluateJavaScript("window.__shell ? __shell.currentChatName() : ''") { [weak self] result, _ in
            guard let self = self else { return }
            let name = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if name.isEmpty { self.askForPinName() } else { self.assignPin(name) }
        }
    }

    private func askForPinName() {
        let a = NSAlert()
        a.messageText = "Pin a chat"
        a.informativeText = "Couldn't read which chat is open. Type the chat's name exactly as it appears in the list."
        a.addButton(withTitle: "Pin")
        a.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        a.accessoryView = field
        if a.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { assignPin(name) }
        }
    }

    private func assignPin(_ name: String) {
        if let existing = settings.pins.firstIndex(of: name) {
            alert("Already pinned", "“\(name)” is on ⌘\(existing + 1).")
            return
        }
        guard let slot = settings.pins.firstIndex(where: { $0.isEmpty }) else {
            alert("All nine slots are full",
                  "Unpin one from Chats ▸ Unpin, then pin this chat again.")
            return
        }
        settings.pins[slot] = name
        settings.save()
        syncMenuState()
        alert("Pinned to ⌘\(slot + 1)", "“\(name)”")
    }

    @objc private func unpin(_ sender: NSMenuItem) {
        settings.pins[sender.tag] = ""
        settings.save()
        syncMenuState()
    }

    @objc private func focusSearch(_ sender: Any?) { js("__shell.focusSearch()") }
    @objc private func newChat(_ sender: Any?)     { js("__shell.newChat()") }
    @objc private func reload(_ sender: Any?)      { web?.reload() }

    @objc private func zoomIn(_ sender: Any?)   { setZoom(Double(web?.pageZoom ?? 1) + 0.1) }
    @objc private func zoomOut(_ sender: Any?)  { setZoom(Double(web?.pageZoom ?? 1) - 0.1) }
    @objc private func zoomReset(_ sender: Any?) { setZoom(1.0) }

    private func setZoom(_ z: Double) {
        let clamped = min(max(z, 0.5), 2.5)
        web?.pageZoom = CGFloat(clamped)
        settings.zoom = clamped
        settings.save()
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.alertStyle = .informational
        a.runModal()
    }

    // ---- menu bar ----

    private func item(_ title: String, _ sel: Selector?, _ key: String = "",
                      _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        i.target = sel == nil ? nil : self
        return i
    }

    private func syncMenuState() {
        for (i, item) in themeItems.enumerated() {
            item.state = kThemes[i].id == settings.theme ? .on : .off
        }
        for (key, item) in hideItems {
            item.state = (settings.hide[key] ?? false) ? .on : .off
        }
        privacyItem?.state = settings.privacy ? .on : .off
        notifyItem?.state = settings.notifications ? .on : .off

        for (i, item) in pinItems.enumerated() {
            let name = settings.pins[i]
            item.title = name.isEmpty ? "⌘\(i + 1) — empty" : name
            item.isEnabled = true
        }
        unpinMenu?.removeAllItems()
        var any = false
        for (i, name) in settings.pins.enumerated() where !name.isEmpty {
            let it = item("⌘\(i + 1) — \(name)", #selector(unpin(_:)))
            it.tag = i
            unpinMenu?.addItem(it)
            any = true
        }
        if !any {
            let none = NSMenuItem(title: "Nothing pinned", action: nil, keyEquivalent: "")
            none.isEnabled = false
            unpinMenu?.addItem(none)
        }
    }

    private func buildMenu() {
        let main = NSMenu()

        // App
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About \(kAppName)",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        notifyItem = item("Notifications", #selector(toggleNotifications(_:)))
        appMenu.addItem(notifyItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(kAppName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others",
                                    action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(kAppName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu; main.addItem(appItem)

        // File
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(item("New Chat", #selector(newChat(_:)), "n"))
        fileMenu.addItem(item("Search", #selector(focusSearch(_:)), "k"))
        fileMenu.addItem(item("Find in Chats", #selector(focusSearch(_:)), "f"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("Reload", #selector(reload(_:)), "r"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileItem = NSMenuItem(); fileItem.submenu = fileMenu; main.addItem(fileItem)

        // Edit — a chat app lives on these; WebKit handles them via first responder.
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let pasteMatch = NSMenuItem(title: "Paste and Match Style",
                                    action: Selector(("pasteAsPlainText:")), keyEquivalent: "v")
        pasteMatch.keyEquivalentModifierMask = [.command, .option, .shift]
        editMenu.addItem(pasteMatch)
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(); editItem.submenu = editMenu; main.addItem(editItem)

        // Chats — the pins
        let chatsMenu = NSMenu(title: "Chats")
        for i in 0..<kPinCount {
            let it = item("⌘\(i + 1) — empty", #selector(openPin(_:)), "\(i + 1)")
            it.tag = i
            chatsMenu.addItem(it)
            pinItems.append(it)
        }
        chatsMenu.addItem(.separator())
        chatsMenu.addItem(item("Pin This Chat", #selector(pinCurrentChat(_:)), "p", [.command, .shift]))
        unpinMenu = NSMenu(title: "Unpin")
        let unpinItem = NSMenuItem(title: "Unpin", action: nil, keyEquivalent: "")
        unpinItem.submenu = unpinMenu
        chatsMenu.addItem(unpinItem)
        let chatsItem = NSMenuItem(); chatsItem.submenu = chatsMenu; main.addItem(chatsItem)

        // View — themes, furniture, privacy, zoom
        let viewMenu = NSMenu(title: "View")
        for (i, t) in kThemes.enumerated() {
            let it = item(t.title, #selector(chooseTheme(_:)))
            it.tag = i
            viewMenu.addItem(it)
            themeItems.append(it)
        }
        viewMenu.addItem(item("Next Theme", #selector(cycleTheme(_:)), "t", [.command, .option]))
        viewMenu.addItem(.separator())
        privacyItem = item("Privacy Blur", #selector(togglePrivacy(_:)), "b", [.command, .shift])
        viewMenu.addItem(privacyItem)
        viewMenu.addItem(.separator())
        for h in kHideables {
            let it = item(h.title, #selector(toggleHide(_:)))
            it.representedObject = h.key
            viewMenu.addItem(it)
            hideItems[h.key] = it
        }
        viewMenu.addItem(.separator())
        viewMenu.addItem(item("Zoom In", #selector(zoomIn(_:)), "+"))
        viewMenu.addItem(item("Zoom Out", #selector(zoomOut(_:)), "-"))
        viewMenu.addItem(item("Actual Size", #selector(zoomReset(_:)), "0"))
        viewMenu.addItem(.separator())
        let full = NSMenuItem(title: "Enter Full Screen",
                              action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        full.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(full)
        let viewItem = NSMenuItem(); viewItem.submenu = viewMenu; main.addItem(viewItem)

        // Window
        let winMenu = NSMenu(title: "Window")
        winMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        let winItem = NSMenuItem(); winItem.submenu = winMenu; main.addItem(winItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = winMenu
        syncMenuState()
    }
}

// MARK: - entry point

@main
struct ShellApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)      // Dock tile, ⌘-Tab slot, unread badge
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
