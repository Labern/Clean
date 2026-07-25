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

// MARK: - app

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate,
                         WKUIDelegate, WKScriptMessageHandler {
    var window: NSWindow!
    var web: WKWebView!
    private var handler: ResourceSchemeHandler!
    private var pendingOpen: [URL] = []
    private var ready = false

    // ---- lifecycle ----

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMenu()
        buildWindow()
        NSApp.activate(ignoringOtherApps: true)
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

        let v = WKWebView(frame: NSRect(x: 0, y: 0, width: 1180, height: 860), configuration: cfg)
        v.navigationDelegate = self
        v.uiDelegate = self
        v.allowsMagnification = false
        v.setValue(false, forKey: "drawsBackground")   // no white flash before the page paints
        if #available(macOS 13.3, *) { v.isInspectable = true }
        self.web = v

        let w = NSWindow(contentRect: v.frame,
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "PICA"
        w.titlebarAppearsTransparent = false
        w.contentView = v
        w.minSize = NSSize(width: 720, height: 520)
        w.setFrameAutosaveName("PicaMainWindow")
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        if w.frame.width < 800 { w.center() }
        self.window = w

        v.load(URLRequest(url: URL(string: "pica://app/index.html")!))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        drainPendingOpens()
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
    }

    // ---- menu actions ----

    @objc func newScript(_ s: Any?)     { js("PICA_API.newDoc()") }
    @objc func importScript(_ s: Any?)  { js("PICA_API.importPdf()") }
    @objc func exportScript(_ s: Any?)  { js("PICA_API.exportMenu()") }
    @objc func saveNow(_ s: Any?)       { js("PICA_API.save()") }
    @objc func picaUndo(_ s: Any?)      { js("PICA_API.undo()") }
    @objc func picaRedo(_ s: Any?)      { js("PICA_API.redo()") }
    @objc func toggleSidebar(_ s: Any?) { js("PICA_API.toggleRail()") }
    @objc func invertTheme(_ s: Any?)   { js("PICA_API.toggleTheme()") }
    @objc func zoomIn(_ s: Any?)        { js("PICA_API.zoom(0.1)") }
    @objc func zoomOut(_ s: Any?)       { js("PICA_API.zoom(-0.1)") }
    @objc func zoomFit(_ s: Any?)       { js("PICA_API.zoomFit()") }
    @objc func elementMenu(_ s: Any?)   { js("PICA_API.elementMenu()") }
    @objc func showGrammar(_ s: Any?)   { js("PICA_API.showKeys()") }

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
                op.view?.frame = NSRect(x: 0, y: 0, width: w, height: h)
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
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("Print…", #selector(printDocument(_:)), "p"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileItem = NSMenuItem(); fileItem.submenu = fileMenu; main.addItem(fileItem)

        // Edit — undo/redo route to PICA's own model history, not WebKit's
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(item("Undo", #selector(picaUndo(_:)), "z"))
        editMenu.addItem(item("Redo", #selector(picaRedo(_:)), "z", [.command, .shift]))
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
        fmtMenu.addItem(item("The Grammar", #selector(showGrammar(_:)), "/"))
        let fmtItem = NSMenuItem(); fmtItem.submenu = fmtMenu; main.addItem(fmtItem)

        // View
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(item("Hide Sidebar", #selector(toggleSidebar(_:)), "b"))
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
