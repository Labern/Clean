// Runs tests/ops-probe.js against a PDF in a headless web view and prints its report.
//   swiftc -O ops-check.swift -o /tmp/pica-ops && /tmp/pica-ops ~/Downloads/X.pdf 8
import Cocoa
import WebKit

final class Handler: NSObject, WKURLSchemeHandler {
    let root: URL
    var inbox: [String: Data] = [:]
    init(root: URL) { self.root = root.standardizedFileURL }
    func stage(_ d: Data) -> String { let id = UUID().uuidString; inbox[id] = d; return id }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { task.didFailWithError(URLError(.badURL)); return }
        var p = url.path; if p.isEmpty || p == "/" { p = "/index.html" }
        if p.hasPrefix("/__inbox/"), let d = inbox[String(p.dropFirst(9))] {
            let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/pdf", "Content-Length": "\(d.count)"])!
            task.didReceive(r); task.didReceive(d); task.didFinish(); return
        }
        let f = root.appendingPathComponent(p).standardizedFileURL
        guard f.path.hasPrefix(root.path), let d = try? Data(contentsOf: f) else {
            let r = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            task.didReceive(r); task.didReceive(Data()); task.didFinish(); return
        }
        let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": f.pathExtension == "html" ? "text/html; charset=utf-8" : "application/octet-stream",
            "Content-Length": "\(d.count)"])!
        task.didReceive(r); task.didReceive(d); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let webRoot = here.deletingLastPathComponent()
let pdfPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "fixtures/Tenet.pdf"
let pageNo = CommandLine.arguments.count > 2 ? (Int(CommandLine.arguments[2]) ?? 1) : 1
let pdf: Data = (try? Data(contentsOf: URL(fileURLWithPath: (pdfPath as NSString).expandingTildeInPath)))
    ?? { print("FAIL: cannot read \(pdfPath)"); exit(1) }()
let probe: String = (try? String(contentsOf: here.appendingPathComponent("ops-probe.js"), encoding: .utf8))
    ?? { print("FAIL: ops-probe.js missing"); exit(1) }()

let handler = Handler(root: webRoot)
let cfg = WKWebViewConfiguration()
cfg.setURLSchemeHandler(handler, forURLScheme: "pica")
cfg.websiteDataStore = .nonPersistent()
let web = WKWebView(frame: .init(x: 0, y: 0, width: 1200, height: 900), configuration: cfg)

final class Nav: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { go() }
    }
}
let nav = Nav()
web.navigationDelegate = nav

func go() {
    let id = handler.stage(pdf)
    web.evaluateJavaScript(probe + "\n;void 0;") { _, e in
        if let e = e { print("FAIL inject: \(e.localizedDescription)"); exit(1) }
        web.callAsyncJavaScript(
            "return await window.__\(ProcessInfo.processInfo.environment["PROBE"] ?? "opsProbe")('pica://app/__inbox/\(id)', \(pageNo), \(ProcessInfo.processInfo.environment["RS"] ?? "2"));",
            arguments: [:], in: nil, in: .page) { r in
            switch r {
            case .failure(let e): print("FAIL probe: \(e.localizedDescription)"); exit(1)
            case .success(let v): print((v as? String) ?? "?"); exit(0)
            }
        }
    }
}

web.load(URLRequest(url: URL(string: "pica://app/index.html")!))
let deadline = Date().addingTimeInterval(180)
while Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1)) }
print("FAIL: timed out"); exit(1)
