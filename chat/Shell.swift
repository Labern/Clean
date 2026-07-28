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

// Fonts offered in the menu. "" means "leave the theme's own font alone".
// Any other installed font is reachable through Font ▸ Choose…, which also
// carries a size, so one panel sets both family and message text size.
let kFonts: [(title: String, css: String)] = [
    ("Theme Default",   ""),
    ("System",          "-apple-system, BlinkMacSystemFont, \"Helvetica Neue\", sans-serif"),
    ("SF Mono",         "\"SF Mono\", Menlo, monospace"),
    ("Menlo",           "Menlo, monospace"),
    ("New York",        "\"New York\", Georgia, serif"),
    ("Iowan Old Style", "\"Iowan Old Style\", Palatino, serif"),
]

// Quiet hours, as presets rather than a date-picker sheet — one click, no dialog.
// `from == -1` is off. Ranges wrap past midnight.
// Contact names can differ from the chat font — an empty css means "same as chat".
let kNameFonts: [(title: String, css: String)] = [
    ("Same as Chat",    ""),
    ("System",          "-apple-system, BlinkMacSystemFont, \"Helvetica Neue\", sans-serif"),
    ("SF Mono",         "\"SF Mono\", Menlo, monospace"),
    ("Menlo",           "Menlo, monospace"),
    ("New York",        "\"New York\", Georgia, serif"),
    ("Iowan Old Style", "\"Iowan Old Style\", Palatino, serif"),
]

let kQuietPresets: [(title: String, from: Int, to: Int)] = [
    ("Off",             -1, -1),
    ("22:00 – 08:00",   22,  8),
    ("23:00 – 07:00",   23,  7),
    ("00:00 – 09:00",    0,  9),
]

let kMsgSizeMin = 11.0, kMsgSizeMax = 28.0, kMsgSizeBase = 15.0

// Focus mode's default shape: a full-height column down the right edge, about a
// fifth of the screen wide. His spec: "full height and about 20% width."
let kCompanionWidthFraction: CGFloat = 0.30
let kCompanionMinWidth: CGFloat = 300

// Presets rather than steppers: two more keyboard chords would be worse than a
// submenu, and 0 always means "leave WhatsApp's own value alone".
let kNameSizes: [(title: String, px: Double)] = [
    ("Default", 0), ("11", 11), ("12", 12), ("13", 13), ("14", 14),
    ("15", 15), ("16", 16), ("18", 18), ("20", 20),
]
let kMsgGaps: [(title: String, px: Double)] = [
    ("Default", 0), ("Snug", 3), ("Roomy", 8), ("Airy", 14), ("Wide", 22),
]

// How far a message bubble sits from its edge of the window in focus mode.
// 6 is the minimum that still reads as deliberate rather than as a mistake.
let kEdgeGaps: [(title: String, px: Double)] = [
    ("Minimum", 6), ("Small", 12), ("Medium", 20), ("Large", 32), ("Extra", 48),
]

let kNotificationCategory = "MESSAGE"

// ⌘R — summon and dismiss from anywhere, per his workflow: "I can be typing
// something, press CMD R to bring up whatsapp, type, type CMD R again and return
// to work."
//
// NOTE, and it is a real trade-off: a global ⌘R is swallowed everywhere while this
// app runs, so Reload in browsers and Run in editors stop responding to it. He
// asked for ⌘R specifically. To take it back, change kHotKeyMods below to
// `cmdKey | optionKey | controlKey` and Reload returns to every other app.
let kHotKeyCode = UInt32(kVK_ANSI_R)
let kHotKeyMods = UInt32(cmdKey)

// Kept as a second, conflict-free way in.
let kHotKeyCode2 = UInt32(kVK_ANSI_W)
let kHotKeyMods2 = UInt32(cmdKey | optionKey | controlKey)

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
    var compact: Bool
    var alwaysOnTop: Bool
    var fadeInactive: Bool
    var fontTitle: String        // which Font-menu entry is ticked
    var fontCSS: String          // the font-family it maps to ("" = theme's own)
    var nameFontTitle: String    // contact names can use a different typeface
    var nameFontCSS: String
    var msgSize: Double          // 0 = WhatsApp's own size
    var nameSize: Double         // contact names + chat list, 0 = WhatsApp's own
    var msgGap: Double           // extra space between messages, 0 = none
    var edgeGap: Double          // how far a bubble sits from the window edge
    var menuBar: Bool
    var quietFrom: Int           // -1 = quiet hours off
    var quietTo: Int
    var sounds: Bool              // false = silent, the default he asked for

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
            notifications: d.object(forKey: "notifications") as? Bool ?? true,
            // Companion mode is never restored on launch: opening into a tiny
            // floating sliver would be disorienting. It is a per-session mode.
            compact: false,
            alwaysOnTop: d.bool(forKey: "alwaysOnTop"),
            fadeInactive: d.bool(forKey: "fadeInactive"),
            fontTitle: d.string(forKey: "fontTitle") ?? "Theme Default",
            fontCSS: d.string(forKey: "fontCSS") ?? "",
            nameFontTitle: d.string(forKey: "nameFontTitle") ?? "Same as Chat",
            nameFontCSS: d.string(forKey: "nameFontCSS") ?? "",
            msgSize: d.object(forKey: "msgSize") as? Double ?? 0,
            nameSize: d.object(forKey: "nameSize") as? Double ?? 0,
            msgGap: d.object(forKey: "msgGap") as? Double ?? 0,
            edgeGap: d.object(forKey: "edgeGap") as? Double ?? 6,
            menuBar: d.object(forKey: "menuBar") as? Bool ?? true,
            quietFrom: d.object(forKey: "quietFrom") as? Int ?? -1,
            quietTo: d.object(forKey: "quietTo") as? Int ?? -1,
            // Silent by default: WhatsApp's own beep is loud enough to be a
            // reason not to use the app. He can switch it back on.
            sounds: d.object(forKey: "sounds") as? Bool ?? false
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
        d.set(alwaysOnTop, forKey: "alwaysOnTop")
        d.set(fadeInactive, forKey: "fadeInactive")
        d.set(fontTitle, forKey: "fontTitle")
        d.set(fontCSS, forKey: "fontCSS")
        d.set(nameFontTitle, forKey: "nameFontTitle")
        d.set(nameFontCSS, forKey: "nameFontCSS")
        d.set(msgSize, forKey: "msgSize")
        d.set(nameSize, forKey: "nameSize")
        d.set(msgGap, forKey: "msgGap")
        d.set(edgeGap, forKey: "edgeGap")
        d.set(menuBar, forKey: "menuBar")
        d.set(quietFrom, forKey: "quietFrom")
        d.set(quietTo, forKey: "quietTo")
        d.set(sounds, forKey: "sounds")
    }

    /// True when now falls inside the quiet window (which may wrap past midnight).
    var inQuietHours: Bool {
        guard quietFrom >= 0, quietTo >= 0 else { return false }
        let h = Calendar.current.component(.hour, from: Date())
        return quietFrom <= quietTo ? (h >= quietFrom && h < quietTo)
                                    : (h >= quietFrom || h < quietTo)
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

// MARK: - a window that may leave the screen

/// AppKit keeps a titled window's title bar on screen: it runs every frame change
/// through `constrainFrameRect` and clamps anything that would put the title bar out
/// of reach. That is why ⌘R left a sliver of the window visible instead of parking
/// it fully off the edge. Focus mode wants it gone, so opt out.
final class SlidingWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

// MARK: - app

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate,
                         WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler,
                         WKDownloadDelegate, UNUserNotificationCenterDelegate {

    var window: NSWindow!
    var web: WKWebView!
    var settings = Settings.load()

    private var themeItems: [NSMenuItem] = []
    private var hideItems: [String: NSMenuItem] = [:]
    private var fontItems: [NSMenuItem] = []
    private var quietItems: [NSMenuItem] = []
    private var nameSizeItems: [NSMenuItem] = []
    private var msgGapItems: [NSMenuItem] = []
    private var edgeGapItems: [NSMenuItem] = []
    private var nameFontItems: [NSMenuItem] = []
    private var privacyItem: NSMenuItem!
    private var notifyItem: NSMenuItem!
    private var soundItem: NSMenuItem!
    private var companionItem: NSMenuItem!
    private var onTopItem: NSMenuItem!
    private var fadeItem: NSMenuItem!
    private var menuBarItem: NSMenuItem!
    private var pinItems: [NSMenuItem] = []
    private var unpinMenu: NSMenu!
    private var hotKeyRef: EventHotKeyRef?
    private var notificationsReady = false
    private var notificationsDenied = false
    private var statusItem: NSStatusItem?
    private var unread = 0
    private var fullFrame: NSRect?          // where the window was before companion mode
    private var recovered = false           // guards the off-WhatsApp recovery
    private var activity: NSObjectProtocol? // the App Nap assertion
    private var fitWork: DispatchWorkItem?  // debounces the companion re-fit
    private var slidOut = false             // parked off the right edge
    private var programmaticFrameChange = false   // suppresses frame persistence
    private var homeFrame: NSRect?          // where to slide back to
    private var previousApp: NSRunningApplication?   // what to hand focus back to
    private var hotKeyRef2: EventHotKeyRef?

    // ---- lifecycle ----

    func applicationDidFinishLaunching(_ note: Notification) {
        gDelegate = self

        // THE most important line in this file for what he actually wants.
        // He built this so he never has to look at his phone while working on the
        // Mac — which means the page must keep receiving messages while the window
        // is hidden or buried. App Nap will otherwise suspend a background app and
        // its timers, and WhatsApp goes quiet. This assertion is held for the whole
        // lifetime of the app; it is not a leak.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .suddenTerminationDisabled],
            reason: "Staying connected to WhatsApp so notifications arrive")

        buildMenu()
        buildWindow()
        registerHotKey()
        prepareNotifications()
        rebuildStatusItem()
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
        if let ref = hotKeyRef2 { UnregisterEventHotKey(ref) }
    }

    // ---- window & web view ----

    private func buildWindow() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()      // persistent: the WhatsApp link survives quit
        cfg.userContentController.add(self, name: "shell")
        if #available(macOS 12.0, *) { cfg.preferences.isElementFullscreenEnabled = true }
        // THE fix for "absurdly loud noise". WhatsApp plays its message beep
        // itself, and patching HTMLMediaElement.play in the page only gets what
        // JavaScript routes through that one method. This tells WebKit that NO
        // media may start without a real user action, so the beep cannot fire at
        // all — enforced by the engine, not by a heuristic. Voice notes and
        // attachments still play, because pressing play IS a user action.
        // Always on: the Notification Sound switch governs the macOS sound, which
        // is a sound he can actually control, rather than WhatsApp's own.
        cfg.mediaTypesRequiringUserActionForPlayback = .all
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
        let w = SlidingWindow(contentRect: v.frame,
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        w.title = kAppName
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.contentView = v
        // "I want it really small if I want it to be." WhatsApp's own layout is
        // the only remaining floor, and fitCompact() zooms out to meet it.
        w.minSize = NSSize(width: 200, height: 220)
        w.setFrameAutosaveName("ShellMainWindow")
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.makeKeyAndOrderFront(nil)
        // Two ways the restored frame can be wrong, both seen:
        //  1. saved while in focus mode → the FULL layout crammed into a sliver;
        //  2. saved while PARKED off screen by ⌘R → the window comes back invisible.
        //     SlidingWindow overrides constrainFrameRect, so macOS no longer drags a
        //     stray window back onto the display; nothing would ever bring it back.
        let vis = (w.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let onScreen = w.frame.intersection(vis)
        if w.frame.width < 760 || w.frame.height < 560
            || onScreen.width < 200 || onScreen.height < 200 {
            w.setContentSize(NSSize(width: 1180, height: 820))
            w.center()
        }
        self.window = w
        tintWindow()
        applyWindowLevel()

        v.load(URLRequest(url: kHome))
    }

    /// Injected before WhatsApp's own bundle runs: the config, the stylesheet
    /// text, then shell.js. Rebuilt whenever settings change so that a reload
    /// comes up in the state he last chose rather than the launch state.
    private func installUserScripts(into ucc: WKUserContentController) {
        ucc.removeAllUserScripts()

        let hideJSON = (try? JSONSerialization.data(withJSONObject: settings.hide))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let pinsJSON = (try? JSONSerialization.data(withJSONObject: settings.pins.filter { !$0.isEmpty }))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let config = """
        window.__SHELL_CONFIG = { theme: \(jsLiteral(settings.theme)), \
        hide: \(hideJSON), privacy: \(settings.privacy ? "true" : "false"), \
        compact: \(settings.compact ? "true" : "false"), \
        font: \(jsLiteral(settings.fontCSS)), msgSize: \(settings.msgSize), \
        nameFont: \(jsLiteral(settings.nameFontCSS)), \
        nameSize: \(settings.nameSize), msgGap: \(settings.msgGap), \
        sounds: \(settings.sounds ? "true" : "false"), edgeGap: \(settings.edgeGap), \
        pins: \(pinsJSON) };
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

    // ---- window behaviour: companion mode, always on top, fade ----

    private func applyWindowLevel() {
        guard let w = window else { return }
        // Companion mode implies floating — that is the point of it.
        w.level = (settings.alwaysOnTop || settings.compact) ? .floating : .normal
        w.alphaValue = (settings.fadeInactive && !w.isKeyWindow) ? 0.82 : 1.0
    }

    /// Shrink to a floating panel showing only the open conversation, and back.
    /// One webview, reused: WhatsApp Web permits a single active session per
    /// browser, so a second webview would be told "WhatsApp is open in another
    /// window" and fight this one for the connection.
    @objc private func toggleCompanion(_ sender: Any?) {
        guard let w = window else { return }
        settings.compact.toggle()

        if settings.compact {
            fullFrame = w.frame
            js("__shell.setCompact(true)")
            applyTitle()                       // style mask BEFORE the frame: changing
                                               // it afterwards resizes the window again
            let target = savedCompanionFrame() ?? defaultCompanionFrame()
            withProgrammaticFrame { w.setFrame(target, display: true, animate: true) }
            // Let the CSS reflow land, then scale to whatever width WhatsApp still
            // insists on — otherwise a narrow window just clips a wide layout.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.fitCompact() }
        } else {
            js("__shell.setCompact(false)")
            applyTitle()                       // drop fullSizeContentView first
            web?.pageZoom = CGFloat(settings.zoom)          // restore his real zoom
            withProgrammaticFrame { w.setFrame(normalFrame(), display: true, animate: true) }
        }
        applyWindowLevel()
        applyOpacity()
        settings.save()
        syncMenuState()
    }

    /// The web view is normally transparent (so there is no white flash before the
    /// page paints). In focus mode that means anything the compositor puts behind
    /// it can show through, which is one of the few remaining explanations for the
    /// stray vertical lines. So in focus mode it paints its own background.
    private func applyOpacity() {
        web?.setValue(!settings.compact, forKey: "drawsBackground")
        guard let w = window else { return }
        if settings.compact, w.backgroundColor == nil { w.backgroundColor = .black }
    }

    /// He asked for the mode to be named in the title bar. In focus mode the
    /// window shows FOCUS; otherwise the title is hidden and the bar is bare.
    private func applyTitle() {
        guard let w = window else { return }
        w.title = settings.compact ? "FOCUS" : kAppName
        // In focus mode the injected bar IS the title bar: the content runs under
        // the title bar area and the bar reserves 76px for the traffic lights. Two
        // stacked bars cost 66px of a ~360px-tall panel, which is a lot of nothing.
        // The mode's name moves into the bar as a small FOCUS chip.
        if settings.compact {
            w.styleMask.insert(.fullSizeContentView)
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true      // still draggable by the bar
        } else {
            w.styleMask.remove(.fullSizeContentView)
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = false
        }
    }

    /// Append a line to ~/Library/Application Support/<app>/diagnostics.log.
    /// NSLog from this app does not surface in `log show`, which left me guessing
    /// at what the page was actually doing. A file always works.
    private func diag(_ line: String) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent(kAppName)
        guard let dir = dir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("diagnostics.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        guard let data = ("[\(stamp)] " + line + "\n").data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: file) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: file)
        }
    }

    /// Make companion mode ADAPT rather than crop.
    ///
    /// WhatsApp Web is built for desktop widths. theme.css strips its minimum
    /// widths so the conversation can reflow, but some of the layout still refuses
    /// to go below a certain width — and when it does, a small window does not
    /// shrink the layout, it CLIPS it: you get the top-left corner of a wide page.
    /// So ask the page how much width it actually took, and zoom out just enough
    /// that all of it fits. Runs a couple of passes because reflowing at the new
    /// zoom can change the answer.
    private func fitCompact(pass: Int = 0) {
        guard settings.compact, let web = web else { return }
        web.evaluateJavaScript("window.__shell ? JSON.stringify(__shell.compactMetrics()) : null") { [weak self] result, _ in
            guard let self = self, let s = result as? String, let d = s.data(using: .utf8),
                  let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                  let inner = (o["inner"] as? NSNumber)?.doubleValue,
                  let scroll = (o["scroll"] as? NSNumber)?.doubleValue,
                  inner > 0, scroll > 0 else { return }

            // Log what the page reported: if the rail or list never got tagged,
            // that — not the zoom — is why companion mode looks wrong.
            if pass == 0 { self.diag("focus fit zoom=\(String(format: "%.2f", Double(web.pageZoom))) " + s) }

            let current = Double(web.pageZoom)
            if scroll <= inner + 2 {
                // It fits. If we had zoomed out for a narrower panel, ease back
                // toward 1 so widening the window recovers full size.
                if current < 0.995 {
                    web.pageZoom = CGFloat(min(1.0, current * 1.06))
                    if pass < 3 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.fitCompact(pass: pass + 1) }
                    }
                }
                return
            }
            // 0.55 floor: below that the text stops being readable, and an
            // unreadable panel is no better than a cropped one.
            let target = max(0.55, min(1.0, current * (inner / scroll) * 0.99))
            guard abs(target - current) > 0.01 else { return }
            web.pageZoom = CGFloat(target)
            if pass < 2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.fitCompact(pass: pass + 1) }
            }
        }
    }

    /// The remembered focus frame, and ONLY if he resized it himself. Twice now a
    /// programmatically-produced frame (clamped, or mid-style-mask-change) has been
    /// persisted and quietly replaced the full-height default. So the saved value is
    /// ignored unless `focusResized` says a live resize put it there.
    private func savedCompanionFrame() -> NSRect? {
        guard UserDefaults.standard.bool(forKey: "focusResized"),
              let s = UserDefaults.standard.string(forKey: "companionFrameV5") else { return nil }
        let r = NSRectFromString(s)
        guard r.width > 200, r.height > 200 else { return nil }
        // A height that reaches the top of the display cannot have come from a drag —
        // AppKit will not let him drag a title bar under the menu bar. Reject it.
        if let scr = window?.screen ?? NSScreen.main {
            let maxSane = scr.frame.height - NSStatusBar.system.thickness + 2
            if r.height > maxSane { return nil }
        }
        return r
    }

    /// A frame for normal (non-focus) mode that fits on screen. Leaving focus mode
    /// used to restore the full-height focus frame, which then spilled over the top
    /// because a normal window sits inside the visible area, not the whole display.
    private func normalFrame() -> NSRect {
        let vis = (window?.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var f = fullFrame ?? NSRect(x: 0, y: 0, width: 1180, height: 820)
        f.size.width = min(f.width, vis.width)
        f.size.height = min(f.height, vis.height)
        if f.maxY > vis.maxY { f.origin.y = vis.maxY - f.height }
        if f.minY < vis.minY { f.origin.y = vis.minY }
        if f.maxX > vis.maxX { f.origin.x = vis.maxX - f.width }
        if f.minX < vis.minX { f.origin.x = vis.minX }
        return f
    }

    /// True once the app has parked the window off screen at least once, so the
    /// remembered frame is known to be his and not a clamped leftover.
    private var hasUserFrame: Bool { UserDefaults.standard.string(forKey: "companionFrameV5") != nil }

    private func defaultCompanionFrame() -> NSRect {
        let scr = window?.screen ?? NSScreen.main
        let full = scr?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let vis = scr?.visibleFrame ?? full
        let width = max(kCompanionMinWidth, (full.width * kCompanionWidthFraction).rounded())
        // Top: just under the menu bar. Using the display's own top put the bar
        // BEHIND the menu bar, which draws above every ordinary window — the result
        // was the focus bar tangled up in the menu bar. Bottom: the very bottom of
        // the display, under the Dock, so there is no gap down there either.
        // With "automatically hide the menu bar" on, visibleFrame reports the FULL
        // height, so subtracting it gave zero inset and the focus bar ended up
        // tangled in the menu bar whenever it appeared. Take whichever is larger:
        // the real inset, or the status bar's own thickness.
        let menuHeight = max(full.maxY - vis.maxY, NSStatusBar.system.thickness)
        let top = full.maxY - menuHeight
        let bottom = full.minY
        return NSRect(x: full.maxX - width, y: bottom, width: width, height: top - bottom)
    }

    /// Slide the window off the right edge and back, rather than blinking it in and
    /// out of existence. The window stays alive and connected the whole time — it is
    /// only parked past the screen edge — so nothing is missed while it is away.
    @objc private func toggleSlide(_ sender: Any?) {
        guard let w = window else { return }
        let visible = (w.screen ?? NSScreen.main)?.frame ?? .zero

        if slidOut {
            // Coming back: remember what he was working in, so the next press can
            // return him there rather than leaving him in WhatsApp.
            let front = NSWorkspace.shared.frontmostApplication
            if front?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = front }
            let target = homeFrame ?? defaultCompanionFrame()
            slidOut = false
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            slide(w, to: target)
            // Caret straight into the message box: the whole point is to type.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [weak self] in
                self?.js("__shell.focusComposer()")
            }
        } else {
            homeFrame = w.frame
            slidOut = true
            var target = w.frame
            target.origin.x = visible.maxX          // left edge on the screen edge: fully gone
            slide(w, to: target)
            // Back to work, in the app he came from.
            if let prev = previousApp, prev.bundleIdentifier != Bundle.main.bundleIdentifier {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { prev.activate() }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { NSApp.hide(nil) }
            }
        }
    }

    /// Any frame change the app makes itself. windowDidEndLiveResize fires for
    /// ANIMATED programmatic resizes as well as for real drags, so without this flag
    /// the app's own moves get recorded as his — which is exactly how a full-display
    /// height got saved and left the focus bar sitting on top of the menu bar.
    private func withProgrammaticFrame(_ body: () -> Void) {
        programmaticFrameChange = true
        body()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.programmaticFrameChange = false }
    }

    private func slide(_ w: NSWindow, to target: NSRect) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            w.animator().setFrame(target, display: true)
        }
    }

    @objc private func toggleAlwaysOnTop(_ sender: Any?) {
        settings.alwaysOnTop.toggle()
        settings.save()
        applyWindowLevel()
        syncMenuState()
    }

    @objc private func toggleFade(_ sender: Any?) {
        settings.fadeInactive.toggle()
        settings.save()
        applyWindowLevel()
        syncMenuState()
    }

    // Remember the companion frame as he resizes it, so it comes back the size
    // he left it — resizing is one of the things he asked for.
    // ONLY a live, user-driven resize may overwrite the remembered frame.
    // windowDidResize/windowDidMove also fire for programmatic changes — the slide
    // animation and entering focus mode — and one of those saved a clamped height,
    // which is why it stopped opening at full height. windowDidEndLiveResize fires
    // only after he has finished dragging an edge himself.
    func windowDidEndLiveResize(_ note: Notification) { rememberFrame() }

    private func rememberFrame() {
        guard let w = window, settings.compact, !slidOut, !programmaticFrameChange else { return }
        UserDefaults.standard.set(true, forKey: "focusResized")
        UserDefaults.standard.set(NSStringFromRect(w.frame), forKey: "companionFrameV5")
        // Re-fit after he stops dragging, not on every frame of the drag.
        fitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fitCompact() }
        fitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func windowDidBecomeKey(_ note: Notification) { applyWindowLevel() }
    func windowDidResignKey(_ note: Notification) { applyWindowLevel() }

    // Closing the window must not kill the connection — that would mean missing
    // messages, which is the one thing this app exists to prevent.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    // ---- the menu-bar glance ----

    private func rebuildStatusItem() {
        if !settings.menuBar {
            if let s = statusItem { NSStatusBar.system.removeStatusItem(s) }
            statusItem = nil
            return
        }
        if statusItem == nil {
            // Keep it NARROW — a wide status item lands under the notch on a
            // notched Mac and shoves its neighbours into hiding.
            let s = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            s.button?.target = self
            s.button?.action = #selector(statusItemClicked(_:))
            s.button?.toolTip = "\(kAppName) — click to show or hide"
            statusItem = s
        }
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let b = statusItem?.button else { return }
        b.title = unread > 0 ? String(unread) : "◦"
        b.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: unread > 0 ? .bold : .regular)
    }

    @objc private func statusItemClicked(_ sender: Any?) { toggleVisibility() }

    @objc private func toggleMenuBar(_ sender: Any?) {
        settings.menuBar.toggle()
        settings.save()
        rebuildStatusItem()
        syncMenuState()
    }

    // ---- navigation policy ----

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.allow); return }

        // Send a link he CLICKED to the real browser — links friends send, the
        // FAQ, OAuth pages — which also means a hostile link can't navigate the
        // logged-in session somewhere else.
        //
        // Scoped hard to main-frame link activations, and this scoping is the
        // whole point: this delegate is called for SUBFRAMES too, so an earlier
        // version that keyed only on the host yanked any iframe WhatsApp loaded
        // from a Meta domain out of the app and opened it in Chrome, which then
        // showed Meta's "Content Not Found" page. Never widen this again.
        let isMainFrame = action.targetFrame?.isMainFrame ?? false
        let clicked = action.navigationType == .linkActivated
        if clicked, isMainFrame, let host = url.host, !kAllowedHosts.contains(host),
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
        // Safety net: if the main frame has ended up off WhatsApp for any reason,
        // come back instead of leaving him staring at someone else's error page.
        // Once per excursion, so a stubborn redirect can't spin.
        if let host = webView.url?.host, !kAllowedHosts.contains(host) {
            if !recovered { recovered = true; goHome(nil); return }
        } else {
            recovered = false
        }
        applyAllToPage()
    }

    @objc private func goHome(_ sender: Any?) { web?.load(URLRequest(url: kHome)) }

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

    // WKWebView answers alert() with nothing and confirm()/prompt() with
    // false/nil unless the app implements these three — so any WhatsApp flow
    // built on a confirmation ("Delete message?", "Log out?") silently does
    // nothing. Learned the hard way in PICA; not repeating it here.

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = NSAlert()
        a.messageText = kAppName
        a.informativeText = message
        a.addButton(withTitle: "OK")
        if let w = window { a.beginSheetModal(for: w) { _ in completionHandler() } }
        else { a.runModal(); completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = NSAlert()
        a.messageText = kAppName
        a.informativeText = message
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")
        if let w = window {
            a.beginSheetModal(for: w) { completionHandler($0 == .alertFirstButtonReturn) }
        } else {
            completionHandler(a.runModal() == .alertFirstButtonReturn)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let a = NSAlert()
        a.messageText = kAppName
        a.informativeText = prompt
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        a.accessoryView = field
        let finish: (NSApplication.ModalResponse) -> Void = { r in
            completionHandler(r == .alertFirstButtonReturn ? field.stringValue : nil)
        }
        if let w = window { a.beginSheetModal(for: w, completionHandler: finish) }
        else { finish(a.runModal()) }
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
            unread = (body["count"] as? Int) ?? 0
            // No badge on the Dock icon — he does not want it there. The count still
            // shows in the menu bar and on the focus bar's pill.
            NSApp.dockTile.badgeLabel = nil
            updateStatusItem()
        case "exitCompact":
            // The "‹" button on the companion bar: back to the full window and
            // the whole chat list.
            if settings.compact { toggleCompanion(nil) }
        case "linked":
            applyAllToPage()
        case "pageerror":
            // A WKWebView has no visible console, so page errors would otherwise
            // vanish. Logged here and asserted on by the smoke test.
            let kind = body["kind"] as? String ?? "error"
            let msg = body["message"] as? String ?? ""
            diag("page \(kind): \(msg)")
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
        js("__shell.setFont(\(jsLiteral(settings.fontCSS)))")
        js("__shell.setMsgSize(\(settings.msgSize))")
        js("__shell.setNameSize(\(settings.nameSize))")
        js("__shell.setNameFont(\(jsLiteral(settings.nameFontCSS)))")
        js("__shell.setMsgGap(\(settings.msgGap))")
        js("__shell.setEdgeGap(\(settings.edgeGap))")
        js("__shell.setSounds(\(settings.sounds ? "true" : "false"))")
        js("__shell.setCompact(\(settings.compact ? "true" : "false"))")
    }

    // ---- typography ----

    @objc private func chooseFontFromMenu(_ sender: NSMenuItem) {
        let f = kFonts[sender.tag]
        settings.fontTitle = f.title
        settings.fontCSS = f.css
        settings.save()
        reinstallUserScripts()
        js("__shell.setFont(\(jsLiteral(settings.fontCSS)))")
        syncMenuState()
    }

    /// Any installed font, through the system panel. It carries a size too, so
    /// one panel sets both the family and the message text size.
    @objc private func chooseFontPanel(_ sender: Any?) {
        let fm = NSFontManager.shared
        fm.target = self
        let current = NSFont(name: settings.fontTitle, size: settings.msgSize > 0 ? settings.msgSize : kMsgSizeBase)
            ?? NSFont.systemFont(ofSize: settings.msgSize > 0 ? settings.msgSize : kMsgSizeBase)
        fm.setSelectedFont(current, isMultiple: false)
        fm.orderFrontFontPanel(self)
    }

    @objc func changeFont(_ sender: Any?) {
        guard let fm = sender as? NSFontManager else { return }
        let chosen = fm.convert(NSFont.systemFont(ofSize: settings.msgSize > 0 ? settings.msgSize : kMsgSizeBase))
        let family = chosen.familyName ?? chosen.fontName
        settings.fontTitle = family
        settings.fontCSS = "\"\(family)\""
        settings.msgSize = min(max(Double(chosen.pointSize), kMsgSizeMin), kMsgSizeMax)
        settings.save()
        reinstallUserScripts()
        js("__shell.setFont(\(jsLiteral(settings.fontCSS)))")
        js("__shell.setMsgSize(\(settings.msgSize))")
        syncMenuState()
    }

    @objc private func chooseNameSize(_ sender: NSMenuItem) {
        settings.nameSize = kNameSizes[sender.tag].px
        settings.save(); reinstallUserScripts()
        js("__shell.setNameSize(\(settings.nameSize))")
        js("__shell.setNameFont(\(jsLiteral(settings.nameFontCSS)))")
        syncMenuState()
    }

    @objc private func chooseNameFont(_ sender: NSMenuItem) {
        let f = kNameFonts[sender.tag]
        settings.nameFontTitle = f.title
        settings.nameFontCSS = f.css
        settings.save(); reinstallUserScripts()
        js("__shell.setNameFont(\(jsLiteral(settings.nameFontCSS)))")
        syncMenuState()
    }

    @objc private func chooseEdgeGap(_ sender: NSMenuItem) {
        settings.edgeGap = kEdgeGaps[sender.tag].px
        settings.save(); reinstallUserScripts()
        js("__shell.setEdgeGap(\(settings.edgeGap))")
        syncMenuState()
    }

    @objc private func chooseMsgGap(_ sender: NSMenuItem) {
        settings.msgGap = kMsgGaps[sender.tag].px
        settings.save(); reinstallUserScripts()
        js("__shell.setMsgGap(\(settings.msgGap))")
        js("__shell.setEdgeGap(\(settings.edgeGap))")
        js("__shell.setSounds(\(settings.sounds ? "true" : "false"))")
        syncMenuState()
    }

    @objc private func msgBigger(_ sender: Any?)  { stepMsgSize(+1) }
    @objc private func msgSmaller(_ sender: Any?) { stepMsgSize(-1) }
    @objc private func msgReset(_ sender: Any?) {
        settings.msgSize = 0
        settings.save(); reinstallUserScripts()
        js("__shell.setMsgSize(0)")
        syncMenuState()
    }

    private func stepMsgSize(_ delta: Double) {
        let from = settings.msgSize > 0 ? settings.msgSize : kMsgSizeBase
        settings.msgSize = min(max(from + delta, kMsgSizeMin), kMsgSizeMax)
        settings.save(); reinstallUserScripts()
        js("__shell.setMsgSize(\(settings.msgSize))")
        syncMenuState()
    }

    // ---- focus mode & quiet hours ----


    @objc private func chooseQuietHours(_ sender: NSMenuItem) {
        let p = kQuietPresets[sender.tag]
        settings.quietFrom = p.from
        settings.quietTo = p.to
        settings.save()
        syncMenuState()
    }

    // ---- notifications ----

    private func prepareNotifications() {
        guard Bundle.main.bundleIdentifier != nil else { return }   // not in a bundle: skip
        let centre = UNUserNotificationCenter.current()
        centre.delegate = self

        // A notification he can answer without leaving what he is doing.
        let reply = UNTextInputNotificationAction(identifier: "REPLY", title: "Reply",
                                                 options: [],
                                                 textInputButtonTitle: "Send",
                                                 textInputPlaceholder: "Reply…")
        centre.setNotificationCategories([
            UNNotificationCategory(identifier: kNotificationCategory, actions: [reply],
                                   intentIdentifiers: [], options: [])
        ])

        centre.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.notificationsReady = granted
                self?.notificationsDenied = !granted
                self?.syncMenuState()
                // Silent notification failure is total failure for this app — it
                // sends him back to his phone, the one thing it exists to stop. So
                // it is surfaced rather than swallowed.
                if !granted { self?.warnNotificationsBlocked(atLaunch: true) }
            }
        }
    }

    private func warnNotificationsBlocked(atLaunch: Bool) {
        let a = NSAlert()
        a.messageText = "\(kAppName) can't show notifications"
        a.informativeText = """
        macOS has notifications turned off for \(kAppName), so you won't be told \
        about new messages — which defeats the point of the app.

        Open System Settings ▸ Notifications ▸ \(kAppName) and turn on \
        "Allow notifications".
        """
        a.alertStyle = .warning
        a.addButton(withTitle: "Open Notification Settings")
        a.addButton(withTitle: atLaunch ? "Later" : "OK")
        if a.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func checkNotifications(_ sender: Any?) {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] s in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let ok = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
                self.notificationsReady = ok
                self.notificationsDenied = !ok
                self.syncMenuState()
                if !ok { self.warnNotificationsBlocked(atLaunch: false); return }
                // Prove it end to end, so he never has to wonder.
                self.notify(title: "\(kAppName) is working",
                            body: "Notifications will arrive like this. You can reply from here too.",
                            id: "selftest-\(Int(Date().timeIntervalSince1970))",
                            chat: nil, force: true)
            }
        }
    }

    private func notify(title: String, body: String, id: String, chat: String?, force: Bool = false) {
        guard notificationsReady else { return }
        if !force && settings.inQuietHours { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = settings.sounds ? .default : nil
        if let chat = chat {
            content.userInfo = ["chat": chat, "jsId": id]
            content.categoryIdentifier = kNotificationCategory   // gives it the Reply field
        }
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
        let chat = info["chat"] as? String ?? ""

        // Typed a reply into the notification: send it without coming to the front,
        // so answering costs him nothing at all.
        if let textResponse = response as? UNTextInputNotificationResponse {
            let text = textResponse.userText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty && !chat.isEmpty { sendReply(to: chat, text: text) }
            completionHandler()
            return
        }

        showWindow()
        if let jsId = info["jsId"] as? String {
            js("__shell.notificationClicked(\(jsLiteral(jsId)), \(jsLiteral(chat)))")
        }
        completionHandler()
    }

    /// Send a reply typed into a notification. The page verifies the composer
    /// holds exactly this text before pressing send and refuses otherwise — a
    /// wrong message to a real person is not a recoverable error — and whatever
    /// happens is reported back rather than assumed.
    private func sendReply(to chat: String, text: String) {
        let call = "__shell.replyTo(\(jsLiteral(chat)), \(jsLiteral(text)))" +
                   ".then(r => JSON.stringify(r))"
        web?.evaluateJavaScript("window.__shell && \(call)") { [weak self] result, error in
            guard let self = self else { return }
            var ok = false
            var reason = error?.localizedDescription ?? "the page did not answer"
            if let s = result as? String, let d = s.data(using: .utf8),
               let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                ok = (o["ok"] as? Bool) ?? false
                reason = (o["reason"] as? String) ?? reason
            }
            if !ok {
                // Never pretend it went. Tell him, and leave the text in the box.
                self.notify(title: "Reply to \(chat) not sent",
                            body: "\(reason). It's still in the message box.",
                            id: "replyfail-\(Int(Date().timeIntervalSince1970))",
                            chat: nil, force: true)
                self.showWindow()
            }
        }
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
        let id2 = EventHotKeyID(signature: OSType(0x53484C4C /* 'SHLL' */), id: 2)
        RegisterEventHotKey(kHotKeyCode2, kHotKeyMods2, id2, GetApplicationEventTarget(), 0, &hotKeyRef2)
    }

    /// ⌘R, one key, three states — his spec: "CMD R moves it straight into focus
    /// view if it isn't. Then pops it off screen if it is. Then pops it back."
    ///
    ///   parked off screen        → slide back
    ///   not in focus mode        → switch into it (opening the top chat if needed)
    ///   in focus mode, on screen → park it off screen
    ///
    /// ⌘⇧R remains the way out of focus mode altogether.
    @objc func summon(_ sender: Any? = nil) {
        // Remember what he was working in before we take the foreground, so parking
        // the window later can hand focus straight back.
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = front }

        if slidOut { toggleSlide(nil); return }

        if !settings.compact {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            toggleCompanion(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                self?.js("__shell.focusComposer()")
            }
            return
        }

        toggleSlide(nil)
    }

    func toggleVisibility() { summon(nil) }

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

    @objc private func toggleSounds(_ sender: Any?) {
        settings.sounds.toggle()
        settings.save()
        reinstallUserScripts()
        js("__shell.setSounds(\(settings.sounds ? "true" : "false"))")
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
        soundItem?.state = settings.sounds ? .on : .off
        companionItem?.state = settings.compact ? .on : .off
        onTopItem?.state = settings.alwaysOnTop ? .on : .off
        fadeItem?.state = settings.fadeInactive ? .on : .off
        menuBarItem?.state = settings.menuBar ? .on : .off

        for (i, item) in fontItems.enumerated() {
            item.state = kFonts[i].title == settings.fontTitle ? .on : .off
        }
        // A font picked from the panel isn't in the list; show it as the ticked one.
        if !kFonts.contains(where: { $0.title == settings.fontTitle }) {
            for item in fontItems { item.state = .off }
        }
        for (i, item) in nameSizeItems.enumerated() {
            item.state = kNameSizes[i].px == settings.nameSize ? .on : .off
        }
        for (i, item) in nameFontItems.enumerated() {
            item.state = kNameFonts[i].title == settings.nameFontTitle ? .on : .off
        }
        for (i, item) in edgeGapItems.enumerated() {
            item.state = kEdgeGaps[i].px == settings.edgeGap ? .on : .off
        }
        for (i, item) in msgGapItems.enumerated() {
            item.state = kMsgGaps[i].px == settings.msgGap ? .on : .off
        }
        for (i, item) in quietItems.enumerated() {
            item.state = (kQuietPresets[i].from == settings.quietFrom
                          && kQuietPresets[i].to == settings.quietTo) ? .on : .off
        }

        // If macOS has blocked notifications, say so where he'll see it rather
        // than leaving him wondering why the app went quiet.
        notifyItem?.title = notificationsDenied
            ? "Notifications — BLOCKED by macOS"
            : (settings.notifications ? "Notifications" : "Notifications (muted here)")

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
        soundItem = item("Notification Sound", #selector(toggleSounds(_:)))
        appMenu.addItem(soundItem)
        appMenu.addItem(item("Check Notifications Work…", #selector(checkNotifications(_:))))
        let quietMenu = NSMenu(title: "Quiet Hours")
        for (i, p) in kQuietPresets.enumerated() {
            let it = item(p.title, #selector(chooseQuietHours(_:)))
            it.tag = i
            quietMenu.addItem(it)
            quietItems.append(it)
        }
        let quietItem = NSMenuItem(title: "Quiet Hours", action: nil, keyEquivalent: "")
        quietItem.submenu = quietMenu
        appMenu.addItem(quietItem)
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
        fileMenu.addItem(item("Focus / Away", #selector(summon(_:)), "r"))
        fileMenu.addItem(item("Reload", #selector(reload(_:)), "r", [.command, .option]))
        fileMenu.addItem(item("Back to WhatsApp", #selector(goHome(_:)), "h", [.command, .shift]))
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

        // Companion mode and its window behaviour — the reason he asked for this
        // round: one chat, small, floating beside whatever he's working on.
        companionItem = item("Focus Mode", #selector(toggleCompanion(_:)), "r", [.command, .shift])
        viewMenu.addItem(companionItem)
        onTopItem = item("Always on Top", #selector(toggleAlwaysOnTop(_:)), "p", [.command, .option])
        viewMenu.addItem(onTopItem)
        fadeItem = item("Fade When Inactive", #selector(toggleFade(_:)))
        viewMenu.addItem(fadeItem)
        viewMenu.addItem(.separator())

        // Font
        let fontMenu = NSMenu(title: "Font")
        for (i, f) in kFonts.enumerated() {
            let it = item(f.title, #selector(chooseFontFromMenu(_:)))
            it.tag = i
            fontMenu.addItem(it)
            fontItems.append(it)
        }
        fontMenu.addItem(.separator())
        fontMenu.addItem(item("Choose…", #selector(chooseFontPanel(_:))))
        let fontItem = NSMenuItem(title: "Font", action: nil, keyEquivalent: "")
        fontItem.submenu = fontMenu
        viewMenu.addItem(fontItem)

        viewMenu.addItem(item("Bigger Message Text", #selector(msgBigger(_:)), "+", [.command, .option]))
        viewMenu.addItem(item("Smaller Message Text", #selector(msgSmaller(_:)), "-", [.command, .option]))
        viewMenu.addItem(item("Default Message Text", #selector(msgReset(_:)), "0", [.command, .option]))

        let nameMenu = NSMenu(title: "Contact Name Size")
        for (i, n) in kNameSizes.enumerated() {
            let it = item(n.title, #selector(chooseNameSize(_:)))
            it.tag = i; nameMenu.addItem(it); nameSizeItems.append(it)
        }
        let nameItem = NSMenuItem(title: "Contact Name Size", action: nil, keyEquivalent: "")
        nameItem.submenu = nameMenu
        viewMenu.addItem(nameItem)

        let nameFontMenu = NSMenu(title: "Contact Name Font")
        for (i, f) in kNameFonts.enumerated() {
            let it = item(f.title, #selector(chooseNameFont(_:)))
            it.tag = i; nameFontMenu.addItem(it); nameFontItems.append(it)
        }
        let nameFontItem = NSMenuItem(title: "Contact Name Font", action: nil, keyEquivalent: "")
        nameFontItem.submenu = nameFontMenu
        viewMenu.addItem(nameFontItem)

        let edgeMenu = NSMenu(title: "Message Margin")
        for (i, g) in kEdgeGaps.enumerated() {
            let it = item(g.title, #selector(chooseEdgeGap(_:)))
            it.tag = i; edgeMenu.addItem(it); edgeGapItems.append(it)
        }
        let edgeItem = NSMenuItem(title: "Message Margin", action: nil, keyEquivalent: "")
        edgeItem.submenu = edgeMenu
        viewMenu.addItem(edgeItem)

        let gapMenu = NSMenu(title: "Space Between Messages")
        for (i, g) in kMsgGaps.enumerated() {
            let it = item(g.title, #selector(chooseMsgGap(_:)))
            it.tag = i; gapMenu.addItem(it); msgGapItems.append(it)
        }
        let gapItem = NSMenuItem(title: "Space Between Messages", action: nil, keyEquivalent: "")
        gapItem.submenu = gapMenu
        viewMenu.addItem(gapItem)
        viewMenu.addItem(.separator())

        privacyItem = item("Privacy Blur", #selector(togglePrivacy(_:)), "b", [.command, .shift])
        viewMenu.addItem(privacyItem)
        menuBarItem = item("Show in Menu Bar", #selector(toggleMenuBar(_:)))
        viewMenu.addItem(menuBarItem)
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
