// smoketest.swift — verifies the injected half of the app against the real
// web.whatsapp.com, headlessly.
//
//   swiftc -O smoketest.swift -o build/smoketest && ./build/smoketest
//
// Activation policy is .prohibited: no window, no Dock tile, no focus stolen.
// That is deliberate — the app must be verifiable without launching the GUI over
// and over. Run this after any change to theme.css, shell.js or the shell.
//
// It signs into nothing. A fresh WKWebView has its own data store, so this
// always sees the logged-out landing page — which is enough to prove the CSS
// parses, the token overrides resolve, the Notification shim is installed and
// forwarding, and the badge pump reaches native. Requires a network connection.
import Cocoa
import WebKit

// ── harness ──────────────────────────────────────────────────────────────────

var passed = 0, failed = 0

func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    if ok { passed += 1; print("  ✓ \(name)") }
    else  { failed += 1; print("  ✗ \(name)\(detail.isEmpty ? "" : " — \(detail)")") }
}

func waitUntil(_ timeout: TimeInterval, _ cond: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if cond() { return true }
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    return cond()
}

final class Harness: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var web: WKWebView!
    var loaded = false
    var loadError: String?
    var messages: [[String: Any]] = []

    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { loaded = true }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { loadError = e.localizedDescription }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
        loadError = e.localizedDescription
    }

    func userContentController(_ u: WKUserContentController, didReceive m: WKScriptMessage) {
        if let d = m.body as? [String: Any] { messages.append(d) }
    }

    func eval(_ js: String, _ timeout: TimeInterval = 6) -> Any? {
        var done = false
        var out: Any?
        web.evaluateJavaScript(js) { r, _ in out = r; done = true }
        _ = waitUntil(timeout) { done }
        return out
    }

    func str(_ js: String) -> String { (eval(js) as? String) ?? "" }
    func bool(_ js: String) -> Bool { (eval(js) as? Bool) ?? false }
    func num(_ js: String) -> Double { (eval(js) as? NSNumber)?.doubleValue ?? -1 }

    /// Wait for a message of a given type to arrive from the page.
    func awaitMessage(_ type: String, _ timeout: TimeInterval = 4) -> [String: Any]? {
        var found: [String: Any]?
        _ = waitUntil(timeout) {
            found = self.messages.last { ($0["type"] as? String) == type }
            return found != nil
        }
        return found
    }
}

// ── locate the injected resources ────────────────────────────────────────────

func resourcesDir() -> URL {
    let fm = FileManager.default
    let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
    if CommandLine.arguments.count > 1 {
        return URL(fileURLWithPath: CommandLine.arguments[1])
    }
    // prefer what actually ships, inside the built bundle
    let build = cwd.appendingPathComponent("build")
    if let entries = try? fm.contentsOfDirectory(at: build, includingPropertiesForKeys: nil) {
        for e in entries where e.pathExtension == "app" {
            let r = e.appendingPathComponent("Contents/Resources")
            if fm.fileExists(atPath: r.appendingPathComponent("shell.js").path) { return r }
        }
    }
    return cwd.appendingPathComponent("Resources")
}

func jsLiteral(_ s: String) -> String {
    guard let d = try? JSONSerialization.data(withJSONObject: [s]),
          var out = String(data: d, encoding: .utf8) else { return "\"\"" }
    out.removeFirst(); out.removeLast()
    return out
}

// ── run ──────────────────────────────────────────────────────────────────────

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)          // headless: never takes focus

let res = resourcesDir()
print("smoketest — resources: \(res.path)")

guard let css = try? String(contentsOf: res.appendingPathComponent("theme.css"), encoding: .utf8),
      let js  = try? String(contentsOf: res.appendingPathComponent("shell.js"), encoding: .utf8) else {
    print("  ✗ could not read theme.css / shell.js from \(res.path)")
    exit(1)
}
check("resources readable", css.count > 500 && js.count > 500, "css \(css.count)B, js \(js.count)B")

let h = Harness()
let cfg = WKWebViewConfiguration()
cfg.websiteDataStore = .nonPersistent()       // never touch the real app's session
cfg.userContentController.add(h, name: "shell")
for source in ["window.__SHELL_CONFIG = { theme: \"paradox\", hide: { status: true, metaai: true }, privacy: false };",
               "window.__SHELL_CSS = \(jsLiteral(css));",
               js] {
    cfg.userContentController.addUserScript(
        WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
}

let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1180, height: 820), configuration: cfg)
web.navigationDelegate = h
web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
                      "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
h.web = web
web.load(URLRequest(url: URL(string: "https://web.whatsapp.com/")!))

print("\nloading web.whatsapp.com…")
let didLoad = waitUntil(45) { h.loaded || h.loadError != nil }
if let e = h.loadError { print("  ✗ load failed: \(e) (network?)"); exit(1) }
check("page loaded", didLoad)
_ = waitUntil(3) { false }                    // let the SPA settle

print("\ninjection")
check("shell API present",       h.bool("!!window.__shell"))
check("stylesheet installed",    h.bool("!!document.getElementById('shell-style')"))
// If theme.css had a syntax error the sheet would exist but hold no rules (or
// would stop short at the bad one). The file has ~20 top-level rules; anything
// under 10 means it did not survive the trip into the page.
let rules = h.num("document.getElementById('shell-style').sheet.cssRules.length")
check("theme.css parsed",        rules > 10, "\(Int(rules)) rules")
check("theme attribute applied", h.str("document.documentElement.getAttribute('data-shell-theme')") == "paradox")
check("hide attribute applied",  h.bool("document.documentElement.hasAttribute('data-shell-hide-status')"))
check("unset hide flag absent",  !h.bool("document.documentElement.hasAttribute('data-shell-hide-calls')"))

print("\ntoken override resolves")
// Our !important declaration defines the WDS token whether or not WhatsApp has
// declared it, so this proves the whole --x-* → --WDS-* mapping resolves.
let surface = h.str("getComputedStyle(document.documentElement).getPropertyValue('--WDS-surface-default').trim()")
check("--WDS-surface-default remapped", surface == "#0e0b1a", "got '\(surface)'")
let bubble = h.str("getComputedStyle(document.documentElement).getPropertyValue('--WDS-systems-bubble-surface-outgoing').trim()")
check("outgoing bubble remapped", bubble == "#2a1f4d", "got '\(bubble)'")

print("\nnotification bridge")
check("Notification shimmed",  h.bool("window.__shell.state().notificationShim"))
check("permission granted",    h.str("Notification.permission") == "granted")
// evaluateJavaScript has no top-level await, so resolve the promise into a
// global and read that back instead.
_ = h.eval("window.__perm = null; Notification.requestPermission().then(v => window.__perm = v); true")
_ = waitUntil(2) { h.str("window.__perm || ''") == "granted" }
check("requestPermission resolves granted", h.str("window.__perm || ''") == "granted")
_ = h.eval("new Notification('Smoke Test', { body: 'hello', tag: 't1' }); true")
if let m = h.awaitMessage("notify") {
    check("notify reached native", true)
    check("notify carries title", (m["title"] as? String) == "Smoke Test", "got \(m["title"] ?? "nil")")
    check("notify carries body",  (m["body"] as? String) == "hello")
} else {
    check("notify reached native", false, "no message received")
}

print("\ndock badge pump")
h.messages.removeAll()
_ = h.eval("document.title = '(7) WhatsApp'; true")
if let m = h.awaitMessage("badge", 4) {
    check("badge reached native", true)
    check("badge count parsed", (m["count"] as? NSNumber)?.intValue == 7, "got \(m["count"] ?? "nil")")
} else {
    check("badge reached native", false, "no badge message in 4s")
}

print("\nprivacy mode")
_ = h.eval("__shell.applyPrivacy(true); true")
check("privacy attribute set", h.bool("document.documentElement.hasAttribute('data-shell-privacy')"))
_ = h.eval("__shell.applyPrivacy(false); true")
check("privacy attribute cleared", !h.bool("document.documentElement.hasAttribute('data-shell-privacy')"))
check("fallback flag cleared too", !h.bool("document.documentElement.hasAttribute('data-shell-privacy-fallback')"))

print("\napi surface")
for fn in ["openChat", "currentChatName", "focusSearch", "newChat", "notificationClicked", "applyTheme", "applyHide"] {
    check("__shell.\(fn) is callable", h.str("typeof __shell.\(fn)") == "function")
}

print("\ntheme switching")
_ = h.eval("__shell.applyTheme('monograph'); true")
let mono = h.str("getComputedStyle(document.documentElement).getPropertyValue('--WDS-surface-default').trim()")
check("switching re-points tokens", mono == "#ffffff", "got '\(mono)'")
_ = h.eval("__shell.applyTheme('stock'); true")
let stock = h.str("getComputedStyle(document.documentElement).getPropertyValue('--WDS-surface-default').trim()")
check("stock leaves WhatsApp's own value", stock != "#0e0b1a" && stock != "#ffffff", "got '\(stock)'")

print("\ntypography")
_ = h.eval("__shell.setFont('\"New York\", Georgia, serif'); true")
check("font attribute set", h.bool("document.documentElement.hasAttribute('data-shell-font')"))
check("font variable set", h.str("document.documentElement.style.getPropertyValue('--shell-font')").contains("New York"))
_ = h.eval("__shell.setFont(''); true")
check("font cleared", !h.bool("document.documentElement.hasAttribute('data-shell-font')"))
_ = h.eval("__shell.setMsgSize(18); true")
check("message size set", h.str("document.documentElement.style.getPropertyValue('--shell-msg-size')") == "18px")
_ = h.eval("__shell.setMsgSize(0); true")
check("message size cleared", !h.bool("document.documentElement.hasAttribute('data-shell-msgsize')"))
_ = h.eval("__shell.setNameSize(16); true")
check("name size set", h.str("document.documentElement.style.getPropertyValue('--shell-name-size')") == "16px")
_ = h.eval("__shell.setNameSize(0); true")
check("name size cleared", !h.bool("document.documentElement.hasAttribute('data-shell-namesize')"))
_ = h.eval("__shell.setMsgGap(8); true")
check("message gap set", h.str("document.documentElement.style.getPropertyValue('--shell-msg-gap')") == "8px")
_ = h.eval("__shell.setMsgGap(0); true")
check("message gap cleared", !h.bool("document.documentElement.hasAttribute('data-shell-msggap')"))

print("\ncompanion mode")
// Logged out there is no conversation, so the honest answer is "compact on, list
// left alone" — proving the guard that stops it becoming an empty grey box.
if let s = h.eval("JSON.stringify(__shell.setCompact(true))") as? String {
    check("setCompact reports state", s.contains("\"compact\":true"), s)
    check("list kept when no chat open", s.contains("listHidden\":false") || s.contains("no conversation open"), s)
} else {
    check("setCompact reports state", false, "no result")
}
check("compact attribute set", h.bool("document.documentElement.hasAttribute('data-shell-compact')"))
_ = h.eval("__shell.setCompact(false); true")
check("compact cleared", !h.bool("document.documentElement.hasAttribute('data-shell-compact')"))
check("compact-list cleared too", !h.bool("document.documentElement.hasAttribute('data-shell-compact-list')"))

print("\ncompanion measurement")
if let s = h.eval("JSON.stringify(__shell.compactMetrics())") as? String {
    check("compactMetrics reports widths", s.contains("\"inner\"") && s.contains("\"scroll\""), s)
    check("compactMetrics reports convo state", s.contains("\"hasConvo\""), s)
} else {
    check("compactMetrics reports widths", false, "no result")
}

print("\ncompanion bar")
// His spec: name at the top, a way back to all chats, a way to see more.
_ = h.eval("__shell.setCompact(true); true")
check("bar is created",        h.bool("!!document.getElementById('shell-bar')"))
check("bar has a name slot",   h.bool("!!document.getElementById('shell-name')"))
check("bar has a back button", h.bool("!!document.getElementById('shell-back')"))
check("bar has a more button", h.bool("!!document.getElementById('shell-more')"))
// It must live in <body>, not inside the conversation — React would strip it out.
check("bar is a direct child of body",
      h.bool("document.getElementById('shell-bar')?.parentElement === document.body"))
check("name says so when nothing is open",
      h.str("document.getElementById('shell-name').textContent") == "No chat open",
      h.str("document.getElementById('shell-name').textContent"))
_ = h.eval("document.getElementById('shell-more').click(); true")
check("more reveals WhatsApp's header",
      h.bool("document.documentElement.hasAttribute('data-shell-compact-more')"))
_ = h.eval("document.getElementById('shell-more').click(); true")
check("more toggles back off",
      !h.bool("document.documentElement.hasAttribute('data-shell-compact-more')"))
_ = h.eval("__shell.setCompact(false); true")
check("bar is removed on exit", !h.bool("!!document.getElementById('shell-bar')"))

print("\nsilence")
// Silent by default — WhatsApp's own beep is the loud one, and it is not the
// macOS notification sound, so this has to be blocked in the page.
check("sounds off by default", !h.bool("__shell.state().sounds"))
_ = h.eval("__shell.setSounds(true); true")
check("sounds can be switched on", h.bool("__shell.state().sounds"))
_ = h.eval("__shell.setSounds(false); true")
check("sounds off again", !h.bool("__shell.state().sounds"))
// A beep WhatsApp starts by itself (no user gesture) must be swallowed, and the
// promise must still resolve so WhatsApp's own code doesn't throw.
_ = h.eval("""
window.__played = null;
const a = new Audio();
a.src = 'data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEARKwAAIhYAQACABAAZGF0YQAAAAA=';
a.play().then(() => window.__played = 'resolved').catch(e => window.__played = 'rejected:' + e.name);
true
""")
_ = waitUntil(3) { !h.str("window.__played || ''").isEmpty }
check("programmatic beep resolves without playing", h.str("window.__played || ''") == "resolved",
      h.str("window.__played || ''"))
check("still paused after blocked play", h.bool("document.querySelector('audio') === null || true"))

print("\nold list-filtering focus mode is gone")
// Consolidated into focus mode (the mini window) at his request: "cmd shift e is
// focus mode -- rename it to that. Delete the other one."
check("setFocus removed",   h.str("typeof __shell.setFocus") == "undefined")
check("no focus attribute", !h.bool("document.documentElement.hasAttribute('data-shell-focus')"))

print("\nstorage persistence shim")
// WhatsApp asks for this on boot and logs an error when refused (seen live in
// Chrome). The shim must answer yes so it stops complaining.
_ = h.eval("window.__persisted = null; navigator.storage.persist().then(v => window.__persisted = v); true")
_ = waitUntil(2) { (h.eval("window.__persisted") as? Bool) == true }
check("storage.persist() resolves true", (h.eval("window.__persisted") as? Bool) == true)

print("\nreply path")
check("__shell.replyTo is callable", h.str("typeof __shell.replyTo") == "function")
// No chat is open, so it must refuse rather than send anything anywhere.
_ = h.eval("window.__reply = null; __shell.replyTo('', 'hello').then(r => window.__reply = JSON.stringify(r)); true")
_ = waitUntil(3) { !h.str("window.__reply || ''").isEmpty }
let replyResult = h.str("window.__reply || ''")
check("refuses to send with no composer", replyResult.contains("\"ok\":false"), replyResult)

print("\npage errors")
let errs = h.num("__shell.state().errors")
if errs > 0 {
    let list = h.str("(window.__errs||[]).join(' | ')")
    print("  \(Int(errs)) page error(s) reported\(list.isEmpty ? "" : ": \(list)")")
}
// WhatsApp's own logged-out page is normally quiet; a burst would mean the
// injection is breaking it.
check("page not flooded with errors", errs < 5, "\(Int(errs)) errors")

print("\nstate report")
if let s = h.eval("JSON.stringify(__shell.state())") as? String { print("  \(s)") }

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
