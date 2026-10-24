// Imports a real screenplay PDF headlessly and reports the geometry the importer
// measured — then asks what store.upgradeTypedLayout would do to it. Written to
// catch exactly one class of bug: an import having its column widths rewritten
// underneath it, which silently moves every wrap point in the script.
//
//   swiftc -O import-check.swift -o /tmp/pica-import && /tmp/pica-import ~/Downloads/Foo.pdf
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
let pdfPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "fixtures/Tenet.pdf"
// a global, not a guard-let local — the navigation delegate's closure captures it
let pdf: Data = (try? Data(contentsOf: URL(fileURLWithPath: (pdfPath as NSString).expandingTildeInPath)))
    ?? { print("FAIL: cannot read \(pdfPath)"); exit(1) }()

let handler = Handler(root: webRoot)
let cfg = WKWebViewConfiguration()
cfg.setURLSchemeHandler(handler, forURLScheme: "pica")
cfg.websiteDataStore = .nonPersistent()
let web = WKWebView(frame: .init(x: 0, y: 0, width: 1200, height: 900), configuration: cfg)

final class Nav: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { doImport() }
    }
}
let nav = Nav()
web.navigationDelegate = nav

func doImport() {
    let id = handler.stage(pdf)
    let js = """
    (async () => {
      const errs = [];
      addEventListener('unhandledrejection', e => errs.push(String(e.reason && (e.reason.stack || e.reason.message) || e.reason)));
      window.__unwrapDebug = [];
      const __t0 = Date.now();
      let thrown = null;
      try { await window.PICA_API.importUrl('pica://app/__inbox/\(id)', 'probe.pdf'); }
      catch (e) { thrown = String(e && (e.stack || e.message) || e); }
      // the import resolves before the document is necessarily open — wait for it
      for (let i = 0; i < 400; i++) {
        const d = window.__pica && window.__pica.doc;
        if (d && d.elements.length > 1) break;
        await new Promise(r => setTimeout(r, 50));
      }
      const S = window.__pica;
      const doc = S.doc;
      const L = doc.layout;
      // what upgradeTypedLayout thinks of this document
      const before = JSON.stringify({cols: L.cols, widths: L.widths, transRight: L.transRight, parenHang: L.parenHang});
      const copy = JSON.parse(JSON.stringify(doc));
      window.__picaStore ? null : null;
      try { return JSON.stringify({
        title: doc.title,
        elements: doc.elements.length,
        pages: S.res && S.res.count,
        importNote: doc.importNote || null,
        layoutKeys: Object.keys(L).sort(),
        cols: L.cols, widths: L.widths, transRight: L.transRight,
        revX: L.revX == null ? null : L.revX,
        charW: L.charW, rowH: L.rowH, pageW: L.pageW, fontPt: L.fontPt,
        titlePageHasX: (doc.titlePage || []).some(t => t.x != null),
        elHasGeom: doc.elements.some(e => e.xOverride != null || e.align || e.spaceBefore != null || e.rev || e.dual),
        before, thrown, errs: errs.slice(0,3),
        firstEls: doc.elements.slice(0,6).map(e => e.type + '|' + e.text.slice(0,60)),
        nXOverride: doc.elements.filter(e => e.xOverride != null).length,
        nAlign: doc.elements.filter(e => e.align).length,
        nDual: doc.elements.filter(e => e.dual).length,
        nRev: doc.elements.filter(e => e.rev).length,
        nMarks: doc.elements.filter(e => e.marks).length,
        nSpaceBefore: doc.elements.filter(e => e.spaceBefore != null).length,
        xOverrideSample: doc.elements.filter(e => e.xOverride != null).slice(0,5).map(e => e.type+'@'+e.xOverride+'|'+e.text.slice(0,32)),
        rows: L.rows, pageH: L.pageH, y0: L.y0,
        importMs: Date.now() - __t0,
        markKinds: (() => {
          const c = {};
          for (const e of doc.elements) for (const m of e.marks || []) {
            const k = e.type + ':' + m[2];
            c[k] = (c[k] || 0) + 1;
          }
          return c;
        })(),
        underlineSample: doc.elements.filter(e => (e.marks||[]).some(m=>m[2]==='u')).slice(0,4).map(e => e.type+'|'+e.text.slice(0,50)),
        unwrapDebug: (window.__unwrapDebug || []).slice(0, 6),
        find: (() => {
          const q = 'I do my own drilling';
          const out = [];
          doc.elements.forEach((e, i) => {
            if (e.text.indexOf(q) >= 0) {
              for (let j = Math.max(0, i - 2); j <= Math.min(doc.elements.length - 1, i + 4); j++)
                out.push(j + ' ' + doc.elements[j].type + ' :: ' + JSON.stringify(doc.elements[j].text));
            }
          });
          return out.slice(0, 12);
        })(),
        nHardBreak: doc.elements.filter(e => e.text.indexOf(String.fromCharCode(10)) >= 0).length,
        hardBreakSample: doc.elements.filter(e => e.text.indexOf(String.fromCharCode(10)) >= 0).slice(0,3).map(e => e.type + '|' + e.text.slice(0,110)),
        breakDiag: doc.elements.filter(e => e.text.indexOf(String.fromCharCode(10)) >= 0).slice(0,3).map(e => ({
          type: e.type,
          lines: e.text.split(String.fromCharCode(10)).map(l => l.length + ':' + JSON.stringify(l.slice(0,72))),
        })),
        longestAction: doc.elements.filter(e=>e.type==='action').reduce((M,e)=>Math.max(M, e.text.split(String.fromCharCode(10)).reduce((m,l)=>Math.max(m,l.length),0)),0),
        longestDialogue: doc.elements.filter(e=>e.type==='dialogue').reduce((M,e)=>Math.max(M, e.text.split(String.fromCharCode(10)).reduce((m,l)=>Math.max(m,l.length),0)),0),
      }); } catch (e) { return JSON.stringify({probeError: String(e && (e.stack||e.message) || e)}); }
    })()
    """
    web.callAsyncJavaScript("return await " + js, arguments: [:], in: nil, in: .page) { r in
        switch r {
        case .failure(let e): print("FAIL import: \(e.localizedDescription)"); exit(1)
        case .success(let v):
            print(((v as? String) ?? "?"))
            exit(0)
        }
    }
}

web.load(URLRequest(url: URL(string: "pica://app/index.html")!))
let deadline = Date().addingTimeInterval(1500)
while Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1)) }
print("FAIL: import timed out"); exit(1)
