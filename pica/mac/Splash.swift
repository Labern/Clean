// The studio card — ★★★★★ × PARADOX — shown for a beat when the app opens.
//
// The card itself is not written here. It lives at ~/Desktop/★★★★★/brand/studio-card.html,
// is copied into the bundle by build.sh, and is the SAME file every product loads: a mark
// that exists twice starts drifting the moment one copy is edited. This file only puts a
// window under it and takes the window away again.
//
// Two rules it must never break:
//   · it never becomes key, so it cannot swallow a keystroke meant for the script;
//   · it never survives its welcome — timer, click or keypress, whichever comes first.
import Cocoa
import WebKit

final class Splash: NSObject, WKNavigationDelegate {

    private var panel: NSPanel?
    private var web: WKWebView?
    private var timer: Timer?
    private var monitors: [Any] = []
    private var dismissed = false

    /// for the --splash-only check, which has to photograph the card's own view
    var panelWindow: NSPanel? { panel }

    /// Total time on screen, matched by the card's own animation.
    private let lifetime: TimeInterval = 1.94
    private let fade: TimeInterval = 0.32

    static func cardURL() -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent("web/studio-card.html")
    }

    /// Nothing to show if the card was not bundled — a missing brand asset is never a
    /// reason for an app not to open.
    func show() {
        guard let card = Splash.cardURL(), FileManager.default.fileExists(atPath: card.path) else { return }

        let size = NSSize(width: 460, height: 300)
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = NSRect(
            x: (screen?.frame.midX ?? 400) - size.width / 2,
            y: (screen?.frame.midY ?? 300) - size.height / 2,
            width: size.width, height: size.height)

        // .nonactivatingPanel is the whole reason this is a panel and not a window: it can
        // be on screen without the app taking over from whatever was in front.
        let p = NSPanel(contentRect: frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear          // so the card's rounded corners are corners
        p.hasShadow = true
        p.ignoresMouseEvents = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.isMovableByWindowBackground = false

        let info = Bundle.main.infoDictionary ?? [:]
        let product = (info["CFBundleName"] as? String) ?? "PICA"
        let year = Calendar.current.component(.year, from: Date())

        let cfg = WKWebViewConfiguration()

        // The card is handed over as a STRING, not as a file URL. It is entirely
        // self-contained — the logo is inlined as data — so it needs no origin, and a
        // file:// request carrying a query string never returns from WebKit at all.
        // The parameters go in ahead of it as a script at document start.
        // The app's own logo travels as data: the card is loaded as a string with no
        // origin, so a relative src would have nothing to be relative to.
        var iconURI = ""
        if let icon = Bundle.main.resourceURL?.appendingPathComponent("web/app-icon.png"),
           let bytes = try? Data(contentsOf: icon) {
            iconURI = "data:image/png;base64," + bytes.base64EncodedString()
        }
        let params: [String: String] = [
            "variant": iconURI.isEmpty ? "wordmark" : "icon",
            "product": product, "icon": iconURI,
            "year": String(year), "mode": "panel", "ms": String(Int(lifetime * 1000)),
        ]
        if let json = try? JSONSerialization.data(withJSONObject: params),
           let js = String(data: json, encoding: .utf8) {
            cfg.userContentController.addUserScript(
                WKUserScript(source: "window.PARADOX_PARAMS = \(js);",
                             injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let v = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: cfg)
        v.navigationDelegate = self
        v.setValue(false, forKey: "drawsBackground")
        v.autoresizingMask = [.width, .height]
        if let html = try? String(contentsOf: card, encoding: .utf8) {
            v.loadHTMLString(html, baseURL: nil)
        }

        p.contentView = v
        p.alphaValue = 0
        p.orderFrontRegardless()            // never makeKey — see the rules at the top
        p.animator().alphaValue = 1

        self.panel = p
        self.web = v

        timer = Timer.scheduledTimer(withTimeInterval: lifetime, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
        // A click anywhere on the card, or any key struck while it is up, sends it away.
        // The key monitor is local: it watches this app's own events and does not consume
        // them, so the keystroke still reaches the editor underneath.
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] ev in
            if ev.window === self?.panel { self?.dismiss(); return nil }
            self?.dismiss(); return ev
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] ev in
            self?.dismiss(); return ev
        } as Any)
    }

    func dismiss() {
        guard !dismissed, let p = panel else { return }
        dismissed = true
        timer?.invalidate(); timer = nil
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fade
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            p.orderOut(nil)
            p.contentView = nil
            self?.web = nil
            self?.panel = nil
        })
    }
}
