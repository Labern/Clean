// PICA.app — a native macOS shell around the PICA editor.
//
// The point of this file is to make PICA a real application: its own Dock tile, its own
// ⌘-Tab slot, a real menu bar, and offline operation. It does not reimplement the editor —
// index.html is bundled verbatim and served over a private `pica://` scheme, which (unlike
// file://) gives the page a stable origin, so localStorage persists across launches. That
// persistence is the whole reason for the scheme handler: scripts must never be lost.
import Cocoa
import WebKit
import UniformTypeIdentifiers

// MARK: - serving the bundled app

final class ResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    private let root: URL
    private let rootPath: String
    // Files opened natively are staged here and fetched by the page over pica://.
    // Handing bytes to JS as a base64 literal does not survive evaluateJavaScript at
    // real screenplay sizes — the call is dropped silently — so never do that.
    private var inbox: [String: (data: Data, mime: String)] = [:]
    private let lock = NSLock()

    init(root: URL) {
        self.root = root.standardizedFileURL
        self.rootPath = self.root.path
    }

    func stage(_ data: Data, mime: String) -> String {
        let id = UUID().uuidString
        lock.lock(); inbox[id] = (data, mime); lock.unlock()
        return id
    }
    private func take(_ id: String) -> (data: Data, mime: String)? {
        lock.lock(); defer { lock.unlock() }
        return inbox.removeValue(forKey: id)
    }

    private func mime(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs":   return "text/javascript; charset=utf-8"
        case "css":         return "text/css; charset=utf-8"
        case "json":        return "application/json; charset=utf-8"
        case "ttf":         return "font/ttf"
        case "otf":         return "font/otf"
        case "woff2":       return "font/woff2"
        case "svg":         return "image/svg+xml"
        case "png":         return "image/png"
        case "pdf":         return "application/pdf"
        default:            return "application/octet-stream"
        }
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL)); return
        }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }

        if serveWebProxy(task: task, url: url, path: path) { return }

        if path.hasPrefix("/__inbox/") {
            let id = String(path.dropFirst("/__inbox/".count))
            if let item = take(id) {
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                    "Content-Type": item.mime, "Content-Length": "\(item.data.count)"])!
                task.didReceive(resp); task.didReceive(item.data); task.didFinish()
            } else {
                let resp = HTTPURLResponse(url: url, statusCode: 410, httpVersion: "HTTP/1.1", headerFields: nil)!
                task.didReceive(resp); task.didReceive(Data()); task.didFinish()
            }
            return
        }

        let file = root.appendingPathComponent(path).standardizedFileURL

        guard file.path == rootPath || file.path.hasPrefix(rootPath + "/"),
              let data = try? Data(contentsOf: file) else {
            // 404 rather than an error, so the page's own fallbacks (e.g. CDN pdf.js) can run
            let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/plain"])!
            task.didReceive(resp); task.didReceive(Data()); task.didFinish(); return
        }
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": mime(file.pathExtension),
            "Content-Length": "\(data.count)",
            "Cache-Control": "no-cache",
        ])!
        task.didReceive(resp); task.didReceive(data); task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

// MARK: - the screenplay browser: browse the libraries, click a PDF, it imports

final class BrowserPanel: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, NSTextFieldDelegate {
    weak var host: AppDelegate?
    var window: NSWindow?
    var web: WKWebView!
    var urlField: NSTextField!
    private var pendingFile: URL?
    private var pendingName = "script.pdf"

    init(host: AppDelegate) { self.host = host }

    func show() {
        if window == nil { build() }
        window?.makeKeyAndOrderFront(nil)
        if web.url == nil { go("https://scriptslug.com") }
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .accessoryBarAction
        b.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        return b
    }

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 800),
                         styleMask: [.titled, .closable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "Find Screenplays"
        w.isReleasedWhenClosed = false
        let root = NSView(frame: w.contentLayoutRect)
        root.autoresizingMask = [.width, .height]

        let strip = NSView(frame: NSRect(x: 0, y: root.bounds.height - 42, width: root.bounds.width, height: 42))
        strip.autoresizingMask = [.width, .minYMargin]

        let back = button("‹", #selector(goBack)); back.frame = NSRect(x: 10, y: 8, width: 30, height: 26)
        let fwd = button("›", #selector(goFwd)); fwd.frame = NSRect(x: 42, y: 8, width: 30, height: 26)
        urlField = NSTextField(frame: NSRect(x: 80, y: 10, width: strip.bounds.width - 420, height: 22))
        urlField.autoresizingMask = [.width]
        urlField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        urlField.placeholderString = "address"
        urlField.delegate = self
        urlField.target = self; urlField.action = #selector(goTyped)
        var x = strip.bounds.width - 330
        for (t, u) in [("SLUG", "https://scriptslug.com"),
                       ("SAVANT", "https://thescriptsavant.com"),
                       ("IMSDB", "https://imsdb.com")] {
            let b = button(t, #selector(goHome(_:)))
            b.frame = NSRect(x: x, y: 8, width: 100, height: 26)
            b.autoresizingMask = [.minXMargin]
            b.toolTip = u
            strip.addSubview(b)
            x += 106
        }
        strip.addSubview(back); strip.addSubview(fwd); strip.addSubview(urlField)

        let cfg = WKWebViewConfiguration()
        let v = WKWebView(frame: NSRect(x: 0, y: 0, width: root.bounds.width, height: root.bounds.height - 42), configuration: cfg)
        v.autoresizingMask = [.width, .height]
        v.navigationDelegate = self
        v.uiDelegate = self          // "Read" buttons open PDFs in a new tab; route them here
        web = v

        root.addSubview(v); root.addSubview(strip)
        w.contentView = root
        w.center()
        window = w
    }

    @objc private func goBack() { web.goBack() }
    @objc private func goFwd() { web.goForward() }
    @objc private func goHome(_ sender: NSButton) { if let u = sender.toolTip { go(u) } }
    @objc private func goTyped() {
        var t = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        if !t.contains("://") { t = "https://" + t }
        go(t)
    }
    private func go(_ u: String) { if let url = URL(string: u) { web.load(URLRequest(url: url)) } }

    // target=_blank / window.open lands in the same view — where PDFs get captured
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, url.absoluteString != "about:blank" {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    // ---- the capture: any PDF response becomes an import, never a page ----
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.response.mimeType?.lowercased() == "application/pdf" {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        urlField?.stringValue = webView.url?.absoluteString ?? ""
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pica-browse", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(UUID().uuidString + "-" + suggestedFilename)
        pendingFile = dest
        pendingName = suggestedFilename
        completionHandler(dest)
    }
    func downloadDidFinish(_ download: WKDownload) {
        guard let f = pendingFile, let data = try? Data(contentsOf: f) else { return }
        try? FileManager.default.removeItem(at: f)
        host?.importDownloaded(data, name: pendingName)
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let a = NSAlert(); a.messageText = "PICA"; a.informativeText = "Could not fetch that PDF: \(error.localizedDescription)"
        a.runModal()
    }
}

// MARK: - app

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate,
                         WKUIDelegate, WKScriptMessageHandler {
    var window: NSWindow!
    var web: WKWebView!
    var browser: BrowserPanel?
    private var handler: ResourceSchemeHandler!
    private var pendingOpen: [URL] = []
    private var ready = false
    private var didAutoFullScreen = false

    // ---- lifecycle ----

    // THE APP CHECKS ITSELF, OR NOTHING IS CHECKED.
    //
    //   PICA.app/Contents/MacOS/PICA --verify-import <file.pdf> [--report out.json]
    //
    // Imports the file through THIS binary — this window, this scheme handler, this
    // bridge — prints what came out and quits. Written because a test harness that
    // reimplements the app's own seams proves the harness: The Hateful Eight passed
    // two suites and a smoke test while the real app produced one page of gibberish.
    // Never activates, so it cannot take focus from whatever is in front.
    private var verifyPath: String? = nil
    private var reportPath: String? = nil
    private var beforeId = ""
    private var splash: Splash?
    private var shotPath: String? = nil

    func applicationDidFinishLaunching(_ note: Notification) {
        let argv = ProcessInfo.processInfo.arguments
        if let i = argv.firstIndex(of: "--verify-import"), i + 1 < argv.count {
            verifyPath = argv[i + 1]
            if let r = argv.firstIndex(of: "--report"), r + 1 < argv.count { reportPath = argv[r + 1] }
            NSApp.setActivationPolicy(.prohibited)
        }
        // --splash-only [--shot out.png]: put the card up, photograph it, quit. The card
        // is the one part of this app with no other way to be checked — you have to look
        // at it — and looking at it must not mean launching the app over and over.
        if argv.contains("--splash-only") {
            if let r = argv.firstIndex(of: "--shot"), r + 1 < argv.count { shotPath = argv[r + 1] }
            // .accessory, not .prohibited: a prohibited app is defined as one that
            // presents no interface, and ordering the panel front under it never
            // returns. .accessory shows the card with no Dock tile and no activation,
            // which is exactly the behaviour being checked anyway.
            NSApp.setActivationPolicy(.accessory)
            splash = Splash(); splash?.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { self.shootSplash() }
            return
        }
        buildMenu()
        // The card goes up BEFORE the editor is built, which is the whole effect: the
        // studio signs the work while the work is still opening.
        if verifyPath == nil && ProcessInfo.processInfo.environment["PICA_NO_SPLASH"] == nil {
            splash = Splash(); splash?.show()
        }
        buildWindow()
        if verifyPath == nil { NSApp.activate(ignoringOtherApps: true) }
    }

    private func shootSplash() {
        guard let p = splash?.panelWindow, let v = p.contentView else {
            FileHandle.standardError.write(Data("splash: no panel\n".utf8)); exit(1)
        }
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { exit(1) }
        v.cacheDisplay(in: v.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]), let path = shotPath {
            try? png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path) — \(Int(v.bounds.width))×\(Int(v.bounds.height))")
        }
        exit(0)
    }

    private func runVerify(_ path: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            FileHandle.standardError.write(Data("cannot read \(path)\n".utf8)); exit(2)
        }
        let name = URL(fileURLWithPath: path).lastPathComponent
            .replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: "'", with: "")
        print("verify: \(name) — \(data.count / 1024)KB")
        let id = handler.stage(data, mime: "application/pdf")
        // The app reopens the script you were last on, so at the instant the import
        // starts there is ALREADY a document in the window — and a check that just asks
        // "is there a document?" answers yes about the wrong one. It must be THIS import:
        // remember which document is open, and wait for it to be a different one.
        web.evaluateJavaScript("(window.__pica && window.__pica.docId) || ''") { [weak self] r, _ in
            guard let self = self else { return }
            self.beforeId = (r as? String) ?? ""
            self.js("PICA_API.importUrl('/__inbox/\(id)', '\(name)')")
            self.pollVerify(0)
        }
    }

    private func pollVerify(_ n: Int) {
        // twenty minutes: a photographed feature is read a page at a time
        if n > 2400 { report(["ok": false, "why": "timed out"]); return }
        let probe = """
        (() => { const S = window.__pica; if (!S || !S.doc) return JSON.stringify({stage:'no doc'});
          const log = document.getElementById('importLog');
          const card = document.querySelector('#overlay.show .card');
          const t = {}; for (const e of S.doc.elements) t[e.type] = (t[e.type] || 0) + 1;
          return JSON.stringify({
            busy: !!card, stage: log ? log.textContent : '',
            failed: !!(card && /failed/i.test(card.textContent || '')),
            cardText: card ? (card.textContent || '').slice(0, 160) : '',
            toast: (document.getElementById('toast') || {}).textContent || '',
            title: S.doc.title, src: S.doc.src || '', byEye: !!(S.doc.__read && S.doc.__read.ocr),
            pages: S.res ? S.res.count : 0, elements: S.doc.elements.length, types: t,
            errs: (window.__errs || []).slice(0, 6), docId: S.docId || '',
            head: S.doc.elements.slice(0, 8).map(e => e.type + '::' + e.text.slice(0, 60)),
          });
        })()
        """
        web.evaluateJavaScript(probe) { [weak self] res, err in
            guard let self = self else { return }
            var o = (res as? String).flatMap { $0.data(using: .utf8) }
                .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
            if let e = err { o = ["stage": "EVALERR " + String(describing: e)] }
            let busy = o["busy"] as? Bool ?? false
            let els = o["elements"] as? Int ?? 0
            if o["failed"] as? Bool == true { o["ok"] = false; self.report(o); return }
            let isNew = (o["docId"] as? String ?? "") != self.beforeId
            if !busy && isNew && els > 1 { o["ok"] = true; self.report(o); return }
            if n % 20 == 0 { print("  … \(o["stage"] as? String ?? "")  [\(els) elements]") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.pollVerify(n + 1) }
        }
    }

    private func report(_ o: [String: Any]) {
        let d = (try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        if let p = reportPath { try? d.write(to: URL(fileURLWithPath: p)) }
        print(String(data: d, encoding: .utf8) ?? "{}")
        exit(o["ok"] as? Bool == true ? 0 : 1)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window?.makeKeyAndOrderFront(nil) }
        return true
    }

    func applicationWillTerminate(_ note: Notification) {
        // give the page a chance to flush its autosave
        web?.evaluateJavaScript("window.PICA_API && PICA_API.save()")
        Thread.sleep(forTimeInterval: 0.15)
    }

    func application(_ sender: NSApplication, openFiles files: [String]) {
        pendingOpen.append(contentsOf: files.map { URL(fileURLWithPath: $0) })
        if ready { drainPendingOpens() }
        sender.reply(toOpenOrPrint: .success)
    }

    // ---- window & web view ----

    private func buildWindow() {
        let cfg = WKWebViewConfiguration()
        let webRoot = Bundle.main.resourceURL!.appendingPathComponent("web")
        handler = ResourceSchemeHandler(root: webRoot)
        cfg.setURLSchemeHandler(handler, forURLScheme: "pica")
        cfg.websiteDataStore = .default()          // persistent: localStorage survives quit
        cfg.userContentController.add(self, name: "pica")

        let v = WKWebView(frame: NSRect(x: 0, y: 0, width: 1320, height: 900), configuration: cfg)
        v.navigationDelegate = self
        v.uiDelegate = self
        v.allowsMagnification = false
        v.setValue(false, forKey: "drawsBackground")   // no white flash before the page paints
        // inspectable WebKit claims ⌘⇧C for its element picker — dev-only, opt in:
        // PICA_INSPECT=1 /Applications/PICA.app/Contents/MacOS/PICA
        if #available(macOS 13.3, *), ProcessInfo.processInfo.environment["PICA_INSPECT"] != nil { v.isInspectable = true }
        // The UI is sized in rem, so it follows the browser's default font size. Labern's
        // Chrome is set to 24px rather than the usual 16px; WKWebView always uses 16px, which
        // made the app render two-thirds the size of the web build. Zoom to match.
        // If the app ever looks off next to the browser again, re-measure
        // getComputedStyle(document.documentElement).fontSize in both and reset this ratio.
        // The page now sets its own root font size (Settings → Interface size), so the app
        // and the browser agree without zooming. Left overridable for a quick nudge:
        // defaults write com.labern.pica uiZoom -float 1.1
        v.pageZoom = UserDefaults.standard.object(forKey: "uiZoom") as? Double ?? 1.0
        self.web = v

        // No system title bar above the app: the page runs full-height and PICA's own header
        // *is* the title bar, with the traffic lights floating over it. The page is told how
        // much room to leave for them via --titlebar-inset.
        let w = NSWindow(contentRect: v.frame,
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "PICA"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.contentView = v
        w.minSize = NSSize(width: 820, height: 560)
        w.setFrameAutosaveName("PicaMainWindow")
        w.isReleasedWhenClosed = false
        // A verify run still needs a window — a page WebKit considers hidden never
        // paints, and half the import is drawing — but it must never come to the front.
        if verifyPath != nil { w.orderBack(nil) } else { w.makeKeyAndOrderFront(nil) }
        if w.frame.width < 800 { w.center() }
        self.window = w

        for (name, _) in [(NSWindow.didEnterFullScreenNotification, 0),
                          (NSWindow.didExitFullScreenNotification, 0)] {
            NotificationCenter.default.addObserver(self, selector: #selector(syncTitlebarInset),
                                                  name: name, object: w)
        }

        v.load(URLRequest(url: URL(string: "pica://app/index.html")!))
    }

    // Leave room for the traffic lights when they are on screen; reclaim it in full screen.
    // pageZoom scales CSS pixels, so the device-point inset has to be divided by it.
    @objc private func syncTitlebarInset() {
        guard let w = window, let v = web else { return }
        let full = w.styleMask.contains(.fullScreen)
        let js = full
            ? "document.documentElement.style.removeProperty('--titlebar-inset')"
            : "document.documentElement.style.setProperty('--titlebar-inset', '\(82.0 / v.pageZoom)px')"
        v.evaluateJavaScript(js, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        syncTitlebarInset()
        if let p = verifyPath { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.runVerify(p) }; return }
        drainPendingOpens()
        // Open filling the screen — a zoomed window, NOT a separate full-screen Space:
        // the state you get by entering full screen and pressing Esc.
        if !didAutoFullScreen {
            didAutoFullScreen = true
            let want = UserDefaults.standard.object(forKey: "openMaximized") as? Bool ?? true
            if want, let w = window, !w.styleMask.contains(.fullScreen),
               let screen = w.screen ?? NSScreen.main {
                w.setFrame(screen.visibleFrame, display: true, animate: false)
            }
        }
    }

    // JS dialogs: a WKWebView silently answers false/nil to confirm()/prompt() unless the
    // app supplies these — which made Delete, Rename and snapshot-restore do nothing.
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = NSAlert(); a.messageText = "PICA"; a.informativeText = message
        a.addButton(withTitle: "OK")
        _ = a.runModal(); completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = NSAlert(); a.messageText = "PICA"; a.informativeText = message
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        completionHandler(a.runModal() == .alertFirstButtonReturn)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let a = NSAlert(); a.messageText = "PICA"; a.informativeText = prompt
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        a.accessoryView = field
        a.window.initialFirstResponder = field
        completionHandler(a.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
    }

    // let the page's own <input type=file> present a normal open panel
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        if #available(macOS 11.0, *) { panel.allowedContentTypes = [UTType.pdf, UTType.json] }
        panel.begin { completionHandler($0 == .OK ? panel.urls : nil) }
    }

    // ---- native → page ----

    private func drainPendingOpens() {
        guard ready, !pendingOpen.isEmpty else { return }
        let urls = pendingOpen; pendingOpen = []
        for url in urls { open(url) }
    }

    private func open(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            present(error: "Could not read \(url.lastPathComponent)."); return
        }
        let name = url.lastPathComponent.replacingOccurrences(of: "\\", with: "\\\\")
                                        .replacingOccurrences(of: "'", with: "\\'")
        let isJSON = url.pathExtension.lowercased() == "json"
        let id = handler.stage(data, mime: isJSON ? "application/json" : "application/pdf")
        js("PICA_API.importUrl('/__inbox/\(id)', '\(name)')")
    }

    @discardableResult
    private func js(_ code: String) -> Bool {
        web?.evaluateJavaScript("window.PICA_API && (\(code))", completionHandler: nil)
        return true
    }

    private func present(error: String) {
        let a = NSAlert(); a.messageText = "PICA"; a.informativeText = error
        a.alertStyle = .warning; a.runModal()
    }

    // page → native (window title follows the script)
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if let title = body["title"] as? String, !title.isEmpty {
            window?.title = title
        }
        // links to script libraries open in the real browser, not inside the editor
        if let s = body["openURL"] as? String, let u = URL(string: s),
           u.scheme == "https" || u.scheme == "http" {
            NSWorkspace.shared.open(u)
        }
        if body["exportPdf"] as? Bool == true {
            exportPDF(suggestedName: body["name"] as? String ?? "script")
        }
        // A scan with no text in it at all: the page hands over the file and asks for the
        // words back. Reading happens off the main thread — 168 photographed pages take
        // about half a minute — and the result is staged like any other file rather than
        // pushed through evaluateJavaScript, because a megabyte of JSON does not belong
        // in a string literal.
        if let job = body["ocr"] as? [String: Any],
           let token = (job["token"] as? String)?.filter({ $0.isLetter || $0.isNumber }),
           let b64 = job["data"] as? String, let pdf = Data(base64Encoded: b64) {
            let pages = (job["pages"] as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue } ?? []
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var last = 0
                let json = OCR.json(data: pdf, pages: pages) { done, total in
                    // one message a page would be thousands of hops across the bridge
                    guard done == total || done - last >= 4 else { return }
                    last = done
                    DispatchQueue.main.async { self?.js("PICA_API.ocrProgress('\(token)',\(done),\(total))") }
                }
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    let id = self.handler.stage(Data(json.utf8), mime: "application/json")
                    self.js("PICA_API.ocrDone('\(token)','/__inbox/\(id)')")
                }
            }
        }
        if body["browse"] as? Bool == true {
            if browser == nil { browser = BrowserPanel(host: self) }
            browser?.show()
        }
    }

    // a PDF captured by the screenplay browser goes straight into the importer
    func importDownloaded(_ data: Data, name: String) {
        let clean = name.replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: "'", with: "")
        let id = handler.stage(data, mime: "application/pdf")
        js("PICA_API.importUrl('/__inbox/\(id)', '\(clean)')")
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Export → PDF: the same identical pages, written straight to a file.
    func exportPDF(suggestedName: String) {
        let panel = NSSavePanel()
        if #available(macOS 11.0, *) { panel.allowedContentTypes = [UTType.pdf] }
        panel.nameFieldStringValue = suggestedName + ".pdf"
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard let self = self, resp == .OK, let url = panel.url else { return }
            self.web.evaluateJavaScript("JSON.stringify(PICA_API.preparePrint())") { res, _ in
                var w = 612.0, h = 792.0
                if let s = res as? String, let d = s.data(using: .utf8),
                   let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                    w = (o["w"] as? Double) ?? w; h = (o["h"] as? Double) ?? h
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    let info = NSPrintInfo(dictionary: [:])
                    info.paperSize = NSSize(width: w, height: h)
                    info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
                    info.horizontalPagination = .fit
                    info.verticalPagination = .automatic
                    info.jobDisposition = .save
                    info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
                    let op = self.web.printOperation(with: info)
                    op.showsPrintPanel = false
                    op.showsProgressPanel = true
                    // The page box the web app lays out is CSS PIXELS (96 to the inch);
                    // the sheet is points (72 to the inch). The view has to be big enough to
                    // hold the whole box, and .fit then scales it onto the paper — sizing
                    // the view in points clipped it to three quarters of its width.
                    let cssScale = 96.0 / 72.0
                    op.view?.frame = NSRect(x: 0, y: 0, width: w * cssScale, height: h * cssScale)
                    op.runModal(for: self.window, delegate: self,
                                didRun: #selector(self.pdfDidExport(_:success:info:)), contextInfo: nil)
                }
            }
        }
    }

    @objc func pdfDidExport(_ op: NSPrintOperation, success: Bool, info: UnsafeMutableRawPointer?) {
        js("PICA_API.endPrint()")
        if success, let url = op.printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] as? URL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    // any target=_blank link likewise goes to the browser
    func webView(_ webView: WKWebView, createWebViewWith config: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = action.request.url, u.scheme == "https" || u.scheme == "http" {
            NSWorkspace.shared.open(u)
        }
        return nil
    }

    // ---- menu actions ----

    @objc func newScript(_ s: Any?)     { js("PICA_API.newDoc()") }
    @objc func importScript(_ s: Any?)  { js("PICA_API.importPdf()") }
    @objc func exportScript(_ s: Any?)  { js("PICA_API.exportMenu()") }
    @objc func exportPdfMenu(_ s: Any?) {
        web.evaluateJavaScript("PICA_API.title()") { [weak self] res, _ in
            let name = ((res as? String) ?? "script").lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted).joined()
            self?.exportPDF(suggestedName: name.isEmpty ? "script" : name)
        }
    }
    @objc func saveNow(_ s: Any?)       { js("PICA_API.save()") }
    @objc func picaUndo(_ s: Any?)      { js("PICA_API.undo()") }
    @objc func picaRedo(_ s: Any?)      { js("PICA_API.redo()") }
    @objc func toggleSidebar(_ s: Any?) { js("PICA_API.toggleRail()") }
    @objc func toggleTitlePage(_ s: Any?) { js("PICA_API.toggleTitlePage()") }
    @objc func toggleReader(_ s: Any?) { js("PICA_API.toggleReader()") }
    @objc func toggleAnnotate(_ s: Any?) { js("PICA_API.toggleAnnotate()") }
    @objc func toggleStoryboard(_ s: Any?) { js("PICA_API.toggleStoryboard()") }
    @objc func escapePanel(_ s: Any?) { js("PICA_API.escape()") }
    @objc func invertTheme(_ s: Any?)   { js("PICA_API.toggleTheme()") }
    @objc func zoomIn(_ s: Any?)        { js("PICA_API.zoom(0.1)") }
    @objc func zoomOut(_ s: Any?)       { js("PICA_API.zoom(-0.1)") }
    @objc func zoomFit(_ s: Any?)       { js("PICA_API.zoomFit()") }
    @objc func elementMenu(_ s: Any?)   { js("PICA_API.elementMenu()") }
    @objc func showGrammar(_ s: Any?)   { js("PICA_API.settings()") }
    @objc func markBold(_ s: Any?)      { js("PICA_API.mark('b')") }
    @objc func markItalic(_ s: Any?)    { js("PICA_API.mark('i')") }
    @objc func markUnderline(_ s: Any?) { js("PICA_API.mark('u')") }

    @objc func openDocument(_ s: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Open a screenplay PDF (or a PICA .json)"
        if #available(macOS 11.0, *) { panel.allowedContentTypes = [UTType.pdf, UTType.json] }
        panel.begin { [weak self] r in
            guard r == .OK else { return }
            for u in panel.urls { self?.open(u) }
        }
    }

    // Print through WebKit's own paginator, at true page size, using the document's
    // real dimensions (US Letter, A4, whatever the imported script used).
    @objc func printDocument(_ sender: Any?) {
        web.evaluateJavaScript("window.PICA_API ? JSON.stringify(PICA_API.preparePrint()) : null") { [weak self] res, _ in
            guard let self = self else { return }
            var w = 612.0, h = 792.0
            if let s = res as? String, let d = s.data(using: .utf8),
               let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                w = (o["w"] as? Double) ?? w
                h = (o["h"] as? Double) ?? h
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let info = NSPrintInfo(dictionary: [:])
                info.paperSize = NSSize(width: w, height: h)
                info.topMargin = 0; info.bottomMargin = 0
                info.leftMargin = 0; info.rightMargin = 0
                info.horizontalPagination = .fit
                info.verticalPagination = .automatic
                info.isHorizontallyCentered = false
                info.isVerticallyCentered = false
                let op = self.web.printOperation(with: info)
                op.showsPrintPanel = true
                op.showsProgressPanel = true
                // The page box the web app lays out is CSS PIXELS (96 to the inch); the sheet
                // is points (72 to the inch). Sizing the view in points gave it three
                // quarters of the width it had to hold, so the script printed squashed into
                // the left of the sheet. .fit then scales the full box onto the paper.
                let cssScale = 96.0 / 72.0
                op.view?.frame = NSRect(x: 0, y: 0, width: w * cssScale, height: h * cssScale)
                op.runModal(for: self.window, delegate: self,
                            didRun: #selector(self.printDidRun(_:success:info:)), contextInfo: nil)
            }
        }
    }

    @objc func printDidRun(_ op: NSPrintOperation, success: Bool, info: UnsafeMutableRawPointer?) {
        js("PICA_API.endPrint()")
    }

    // ---- menu bar ----

    private func item(_ title: String, _ sel: Selector?, _ key: String,
                      _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        i.target = sel == nil ? nil : self
        return i
    }

    private func buildMenu() {
        let main = NSMenu()

        // App
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About PICA", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide PICA", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit PICA", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu; main.addItem(appItem)

        // File
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(item("New Script", #selector(newScript(_:)), "n"))
        fileMenu.addItem(item("Open…", #selector(openDocument(_:)), "o"))
        fileMenu.addItem(item("Import PDF…", #selector(importScript(_:)), "i"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("Save", #selector(saveNow(_:)), "s"))
        fileMenu.addItem(item("Export…", #selector(exportScript(_:)), "e"))
        fileMenu.addItem(item("Export PDF…", #selector(exportPdfMenu(_:)), "e", [.command, .shift]))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("Print…", #selector(printDocument(_:)), "p"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileItem = NSMenuItem(); fileItem.submenu = fileMenu; main.addItem(fileItem)

        // Edit — undo/redo route to PICA's own model history, not WebKit's
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(item("Undo", #selector(picaUndo(_:)), "z"))
        editMenu.addItem(item("Redo", #selector(picaRedo(_:)), "z", [.command, .shift]))
        let redoY = item("Redo", #selector(picaRedo(_:)), "y")
        redoY.isHidden = true                  // ⌘Y, the second spelling
        editMenu.addItem(redoY)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(); editItem.submenu = editMenu; main.addItem(editItem)

        // Format
        let fmtMenu = NSMenu(title: "Format")
        fmtMenu.addItem(item("Element…", #selector(elementMenu(_:)), "\\"))
        fmtMenu.addItem(.separator())
        fmtMenu.addItem(item("Bold", #selector(markBold(_:)), "b"))
        fmtMenu.addItem(item("Italic", #selector(markItalic(_:)), "i"))
        fmtMenu.addItem(item("Underline", #selector(markUnderline(_:)), "u"))
        fmtMenu.addItem(.separator())
        fmtMenu.addItem(item("Settings & Shortcuts", #selector(showGrammar(_:)), ","))
        let fmtItem = NSMenuItem(); fmtItem.submenu = fmtMenu; main.addItem(fmtItem)

        // View
        let viewMenu = NSMenu(title: "View")
        let escItem = NSMenuItem(title: "Close Panel", action: #selector(escapePanel(_:)), keyEquivalent: "\u{1B}")
        escItem.keyEquivalentModifierMask = []
        escItem.target = self
        escItem.isHidden = true                 // a key binding, not a menu entry
        viewMenu.addItem(escItem)
        viewMenu.addItem(item("Reader", #selector(toggleReader(_:)), "r"))
        viewMenu.addItem(item("Annotate", #selector(toggleAnnotate(_:)), "a", [.command, .shift]))
        viewMenu.addItem(item("Storyboard", #selector(toggleStoryboard(_:)), "s", [.command, .shift]))
        viewMenu.addItem(item("Hide Sidebar", #selector(toggleSidebar(_:)), "t"))
        viewMenu.addItem(item("Show Title Page", #selector(toggleTitlePage(_:)), "t", [.command, .shift]))
        viewMenu.addItem(item("Invert Theme", #selector(invertTheme(_:)), "j"))
        viewMenu.addItem(.separator())
        viewMenu.addItem(item("Zoom In", #selector(zoomIn(_:)), "+"))
        viewMenu.addItem(item("Zoom Out", #selector(zoomOut(_:)), "-"))
        viewMenu.addItem(item("Fit Page", #selector(zoomFit(_:)), "0"))
        viewMenu.addItem(.separator())
        let full = NSMenuItem(title: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
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
    }
}

@main
struct PicaApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)      // Dock tile + ⌘-Tab slot: the whole point
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
