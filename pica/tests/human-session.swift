// Drives tests/human-session.js against the app in a headless WKWebView.
//
// No window, no Dock tile, .prohibited activation policy — it cannot steal focus
// or disturb anything on screen. Points at the worktree's pica/index.html by
// default so it can be re-run without rebuilding the bundle; set PICA_WEB_ROOT
// to aim it at a built PICA.app's web/ directory instead.
//
//   swiftc -O human-session.swift -o /tmp/pica-human && /tmp/pica-human
import Cocoa
import WebKit

final class Handler: NSObject, WKURLSchemeHandler {
    let root: URL
    init(root: URL) { self.root = root.standardizedFileURL }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { task.didFailWithError(URLError(.badURL)); return }
        var p = url.path; if p.isEmpty || p == "/" { p = "/index.html" }
        let f = root.appendingPathComponent(p).standardizedFileURL
        let mimes = ["html": "text/html; charset=utf-8", "mjs": "text/javascript", "js": "text/javascript",
                     "ttf": "font/ttf", "json": "application/json"]
        guard f.path.hasPrefix(root.path), let d = try? Data(contentsOf: f) else {
            let r = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            task.didReceive(r); task.didReceive(Data()); task.didFinish(); return
        }
        let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": mimes[f.pathExtension.lowercased()] ?? "application/octet-stream",
            "Content-Length": "\(d.count)"])!
        task.didReceive(r); task.didReceive(d); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let webRoot = ProcessInfo.processInfo.environment["PICA_WEB_ROOT"].map { URL(fileURLWithPath: $0) }
    ?? here.deletingLastPathComponent()   // tests/ → pica/
guard FileManager.default.fileExists(atPath: webRoot.appendingPathComponent("index.html").path) else {
    print("FAIL: no index.html under \(webRoot.path)"); exit(1)
}
// a global, not a guard-let local — the navigation delegate's closure captures it
let session: String = (try? String(contentsOf: here.appendingPathComponent("human-session.js"), encoding: .utf8))
    ?? (try? String(contentsOf: webRoot.appendingPathComponent("tests/human-session.js"), encoding: .utf8))
    ?? { print("FAIL: human-session.js not found"); exit(1) }()

let handler = Handler(root: webRoot)
let cfg = WKWebViewConfiguration()
cfg.setURLSchemeHandler(handler, forURLScheme: "pica")
cfg.userContentController.addUserScript(WKUserScript(source: """
window.__errs = [];
addEventListener('error', e => window.__errs.push('error: ' + (e.message || e.type)));
addEventListener('unhandledrejection', e => window.__errs.push('rejection: ' + (e.reason && (e.reason.stack || e.reason.message) || e.reason)));
(() => { const r = console.error; console.error = (...a) => { window.__errs.push('console.error: ' + a.join(' ')); r(...a); }; })();
""", injectionTime: .atDocumentStart, forMainFrameOnly: false))
cfg.websiteDataStore = .nonPersistent()
let web = WKWebView(frame: .init(x: 0, y: 0, width: 1200, height: 900), configuration: cfg)

final class Nav: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { run() }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
        print("FAIL provisional navigation: \(e.localizedDescription)"); exit(1)
    }
}
let nav = Nav()
web.navigationDelegate = nav

func run() {
    // ";void 0" so the file's last expression (a function) isn't returned to Swift
    web.evaluateJavaScript(session + "\n;void 0;") { _, e in
        if let e = e { print("FAIL injecting session: \(e.localizedDescription)"); exit(1) }
        web.callAsyncJavaScript("return await window.__humanSession();",
                                arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .failure(let e):
                print("FAIL running session: \(e.localizedDescription)"); exit(1)
            case .success(let v):
                guard let s = v as? String, let d = s.data(using: .utf8),
                      let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
                    print("FAIL: unreadable session result: \(String(describing: v))"); exit(1)
                }
                let ok = (o["log"] as? [String]) ?? []
                let bad = (o["err"] as? [String]) ?? []
                for l in ok { print("  " + l) }
                for l in bad { print("  " + l) }
                print("")
                if bad.isEmpty {
                    print("the typist found nothing wrong — \(ok.count) checks")
                    exit(0)
                } else {
                    print("\(bad.count) FAILED of \(ok.count + bad.count) checks")
                    exit(1)
                }
            }
        }
    }
}

web.load(URLRequest(url: URL(string: "pica://app/index.html")!))
let deadline = Date().addingTimeInterval(45)
while Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1)) }
// a hang should name the beat it hung on, not just die
print("FAIL: session timed out")
web.evaluateJavaScript("JSON.stringify(window.__hsProgress || [])") { v, _ in
    print("  reached: " + ((v as? String) ?? "nothing"))
    exit(1)
}
RunLoop.main.run(until: Date().addingTimeInterval(3))
exit(1)
