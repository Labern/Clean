// Imports a PDF and photographs the pages PICA actually draws, so an import can be
// compared with its source the way a person compares them — by looking. Headless:
// no window, no focus stolen.
//
//   swiftc -O render-check.swift -o /tmp/pica-render && /tmp/pica-render ~/Downloads/X.pdf 8 9
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
        if p.hasPrefix("/__inbox/"), let d = inbox.removeValue(forKey: String(p.dropFirst(9))) {
            let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/pdf", "Content-Length": "\(d.count)"])!
            task.didReceive(r); task.didReceive(d); task.didFinish(); return
        }
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
    ?? here.deletingLastPathComponent()
let outDir = ProcessInfo.processInfo.environment["PICA_OUT"] ?? "/tmp"
let pdfPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "fixtures/Tenet.pdf"
let wanted: [Int] = CommandLine.arguments.count > 2
    ? CommandLine.arguments.dropFirst(2).compactMap { Int($0) } : [1]
let pdf: Data = (try? Data(contentsOf: URL(fileURLWithPath: (pdfPath as NSString).expandingTildeInPath)))
    ?? { print("FAIL: cannot read \(pdfPath)"); exit(1) }()

let handler = Handler(root: webRoot)
let cfg = WKWebViewConfiguration()
cfg.setURLSchemeHandler(handler, forURLScheme: "pica")
cfg.websiteDataStore = .nonPersistent()
let web = WKWebView(frame: .init(x: 0, y: 0, width: 1400, height: 1100), configuration: cfg)

final class Nav: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { doImport() }
    }
}
let nav = Nav()
web.navigationDelegate = nav

var queue: [Int] = []

func doImport() {
    let id = handler.stage(pdf)
    let js = """
    (async () => {
      await window.PICA_API.importUrl('pica://app/__inbox/\(id)', 'probe.pdf');
      for (let i = 0; i < 600; i++) {
        const d = window.__pica && window.__pica.doc;
        if (d && d.elements.length > 1) break;
        await new Promise(r => setTimeout(r, 50));
      }
      // full zoom-to-width off; draw at a fixed scale so pages are legible
      window.PICA_API.zoomFit();
      return JSON.stringify({pages: window.__pica.res.count, elements: window.__pica.doc.elements.length});
    })()
    """
    web.callAsyncJavaScript("return await " + js, arguments: [:], in: nil, in: .page) { r in
        if case .failure(let e) = r { print("FAIL import: \(e.localizedDescription)"); exit(1) }
        if case .success(let v) = r { print("imported: " + ((v as? String) ?? "?")) }
        queue = wanted
        shoot()
    }
}

func shoot() {
    guard let n = queue.first else { exit(0) }
    queue.removeFirst()
    // scroll the wanted page to the top of the canvas, then photograph it
    let js = """
    (async () => {
      // the print path draws every page at true size — no lazy windowing to fight
      if (!window.__printed) { window.PICA_API.preparePrint(); window.__printed = 1;
        await new Promise(r => setTimeout(r, 1200)); }
      const wraps = document.querySelectorAll('.pageWrap');
      const pe = wraps[\(n) - 1];
      if (!pe) return 'no-page';
      pe.scrollIntoView();
      await new Promise(r => setTimeout(r, 400));
      const b = pe.getBoundingClientRect();
      return JSON.stringify({x: b.left, y: b.top, w: b.width, h: b.height, count: wraps.length});
    })()
    """
    web.callAsyncJavaScript("return await " + js, arguments: [:], in: nil, in: .page) { r in
        guard case .success(let v) = r, let s = v as? String, s != "no-page",
              let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Double] else {
            print("  page \(n): not rendered"); shoot(); return
        }
        let cfgS = WKSnapshotConfiguration()
        cfgS.rect = CGRect(x: o["x"] ?? 0, y: o["y"] ?? 0, width: o["w"] ?? 0, height: o["h"] ?? 0)
        cfgS.snapshotWidth = NSNumber(value: 900)
        web.takeSnapshot(with: cfgS) { img, err in
            if let img = img, let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                let path = outDir + "/pica-p\(n).png"
                try? png.write(to: URL(fileURLWithPath: path))
                print("  wrote \(path)")
            } else {
                print("  page \(n): snapshot failed \(err?.localizedDescription ?? "")")
            }
            shoot()
        }
    }
}

web.load(URLRequest(url: URL(string: "pica://app/index.html")!))
let deadline = Date().addingTimeInterval(300)
while Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1)) }
print("FAIL: render timed out"); exit(1)
