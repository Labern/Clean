// Headless verification of the BUILT PICA.app bundle — loads the packaged web app through
// the same pica:// scheme the real app uses, then exercises it. Runs with activation policy
// .prohibited: no window, no Dock tile, never steals focus.
//
//   swiftc -O smoketest.swift -o build/smoketest && ./build/smoketest [path/to/Tenet.pdf]
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
let webRoot = here.appendingPathComponent("build/PICA.app/Contents/Resources/web")
guard FileManager.default.fileExists(atPath: webRoot.appendingPathComponent("index.html").path) else {
    print("FAIL: build/PICA.app not found — run ./build.sh first"); exit(1)
}
let pdfPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "../tests/fixtures/Tenet.pdf"

let handler = Handler(root: webRoot)
let cfg = WKWebViewConfiguration()
cfg.setURLSchemeHandler(handler, forURLScheme: "pica")
// capture anything the page throws, so a failure names its own cause
let collector = WKUserScript(source: """
window.__errs = [];
addEventListener('error', e => window.__errs.push('error: ' + (e.message || e.type)));
addEventListener('unhandledrejection', e => window.__errs.push('rejection: ' + (e.reason && (e.reason.stack || e.reason.message) || e.reason)));
(() => { const w = console.warn, r = console.error;
  console.warn = (...a) => { window.__errs.push('warn: ' + a.join(' ')); w(...a); };
  console.error = (...a) => { window.__errs.push('console.error: ' + a.join(' ')); r(...a); }; })();
""", injectionTime: .atDocumentStart, forMainFrameOnly: false)
cfg.userContentController.addUserScript(collector)
// an isolated store, so the smoke test never touches the real app's saved scripts
cfg.websiteDataStore = .nonPersistent()
let web = WKWebView(frame: .init(x: 0, y: 0, width: 1200, height: 900), configuration: cfg)

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "  ok " : "FAIL ") + name + (detail.isEmpty ? "" : " — " + detail))
    if !ok { failures += 1 }
}

func eval(_ js: String, _ done: @escaping (Any?) -> Void) {
    web.evaluateJavaScript(js) { res, err in
        if let err = err { print("  js error: \(err.localizedDescription)") }
        done(res)
    }
}

final class Nav: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // let boot() run
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { stage1() }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError e: Error) {
        print("FAIL navigation: \(e.localizedDescription)"); exit(1)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
        print("FAIL provisional navigation: \(e.localizedDescription)"); exit(1)
    }
}
let nav = Nav()
web.navigationDelegate = nav

func stage1() {
    eval("""
    (() => {
      const S = window.__pica;
      return JSON.stringify({
        engine: typeof PicaEngine === 'object',
        api: typeof window.PICA_API === 'object',
        apiKeys: Object.keys(window.PICA_API || {}).length,
        booted: !!(S && S.doc),
        pages: document.querySelectorAll('.pageWrap').length,
        origin: location.origin,
        ls: (() => { try { localStorage.setItem('smoke','1'); return localStorage.getItem('smoke') === '1'; } catch(e){ return false; } })(),
        courier: getComputedStyle(document.querySelector('.page') || document.body).fontFamily.includes('Courier'),
        title: document.title,
        metrics: {
          rootFont: getComputedStyle(document.documentElement).fontSize,
          bodyFont: getComputedStyle(document.body).fontSize,
          hbtn: getComputedStyle(document.querySelector('.hbtn')).fontSize,
          statusFont: getComputedStyle(document.querySelector('#stType')).fontSize,
          pageFont: getComputedStyle(document.querySelector('.page') || document.body).fontSize,
          dpr: devicePixelRatio, innerW: innerWidth, innerH: innerHeight,
          canvasW: (document.querySelector('#canvas')||{}).clientWidth,
          zoom: (window.__pica||{}).zoom, k: (window.__pica||{}).k,
        },
      });
    })()
    """) { res in
        guard let s = res as? String, let d = s.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else {
            print("FAIL: page did not respond"); exit(1)
        }
        check("engine present in bundled index.html", o["engine"] as? Bool == true)
        check("PICA_API exposed for the native menus", o["api"] as? Bool == true,
              "\(o["apiKeys"] as? Int ?? 0) methods")
        check("app booted with a document", o["booted"] as? Bool == true)
        check("pages rendered", (o["pages"] as? Int ?? 0) >= 1, "\(o["pages"] as? Int ?? 0) page shells")
        check("localStorage available on pica:// origin", o["ls"] as? Bool == true,
              o["origin"] as? String ?? "?")
        check("script page is set in Courier", o["courier"] as? Bool == true)
        if let m = o["metrics"] { print("  METRICS: \(m)") }
        stage2()
    }
}

// fonts must resolve from the bundle, with no network at all
func stage2(attempts: Int = 0) {
    eval("""
    (() => {
      const local = document.fonts.check('12pt "Courier Prime Local"');
      const loaded = [];
      document.fonts.forEach(f => { if (f.status === 'loaded') loaded.push(f.family); });
      return JSON.stringify({ local, status: document.fonts.status, loaded: [...new Set(loaded)] });
    })()
    """) { res in
        var local = false, detail = ""
        if let s = res as? String, let d = s.data(using: .utf8),
           let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
            local = o["local"] as? Bool == true
            detail = ((o["loaded"] as? [String]) ?? []).joined(separator: ", ")
        }
        if !local && attempts < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { stage2(attempts: attempts + 1) }
            return
        }
        check("Courier Prime loads from the bundle (offline)", local, detail)
        probe()
    }
}

// a non-PDF must be rejected with a readable message rather than failing silently
func probe() {
    let id = handler.stage(Data("definitely not a pdf".utf8))
    eval("PICA_API.importUrl('/__inbox/\(id)', 'bad.pdf'); true") { _ in
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            eval("((document.querySelector('#overlay.show .card h2')||{}).textContent||'')") { r in
                let msg = (r as? String) ?? ""
                check("a non-PDF is rejected with a clear message", msg.contains("failed"), msg)
                eval("document.getElementById('overlay').classList.remove('show'); true") { _ in stage3() }
            }
        }
    }
}

// the real test: import a PDF with the bundled pdf.js, no network
func stage3() {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: pdfPath)) else {
        print("  -- skipping import test, no PDF at \(pdfPath)")
        finish(); return
    }
    print("  … importing \(URL(fileURLWithPath: pdfPath).lastPathComponent) offline via bundled pdf.js")
    let id = handler.stage(data)
    eval("PICA_API.importUrl('/__inbox/\(id)', 'Tenet.pdf'); true") { _ in
        poll(attempts: 0)
    }
}

func poll(attempts: Int) {
    if attempts > 60 {
        eval("JSON.stringify({errs:(window.__errs||[]).slice(0,8), overlay:(document.querySelector('#overlay .card')||{}).textContent||''})") { r in
            print("  diagnostics: " + ((r as? String) ?? "none"))
            check("PDF import completed", false, "timed out")
            finish()
        }
        return
    }
    eval("""
    (() => { const S = window.__pica;
      const failed = !!document.querySelector('#overlay.show .card h2') &&
                     document.querySelector('#overlay.show .card h2').textContent.includes('failed');
      return JSON.stringify({ done: !!(S && S.res && S.res.count > 1), failed,
        pages: S && S.res ? S.res.count : 0, els: S && S.doc ? S.doc.elements.length : 0,
        title: S && S.doc ? S.doc.title : '' });
    })()
    """) { res in
        guard let s = res as? String, let d = s.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { poll(attempts: attempts + 1) }; return
        }
        if o["failed"] as? Bool == true {
            check("PDF import completed offline", false, "importer reported failure")
            finish(); return
        }
        // res.count is script pages (147); the rendered array adds the title page (148)
        if (o["pages"] as? Int ?? 0) >= 147 {
            let pages = o["pages"] as? Int ?? 0
            let els = o["els"] as? Int ?? 0
            let title = o["title"] as? String ?? ""
            check("PDF imported offline with bundled pdf.js", true,
                  "\(pages) script pages · \(els) elements · “\(title)”")
            check("import produced the expected document", pages == 147 && els > 3500 && title == "TENET",
                  "expected 147 pages / >3500 elements / TENET")
            finish(); return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { poll(attempts: attempts + 1) }
    }
}

func finish() {
    print(failures == 0 ? "\nPICA.app verified — the bundle runs standalone" : "\n\(failures) FAILURE(S)")
    exit(failures == 0 ? 0 : 1)
}

web.load(URLRequest(url: URL(string: "pica://app/index.html")!))
DispatchQueue.main.asyncAfter(deadline: .now() + 120) { print("TIMEOUT"); exit(3) }
app.run()
