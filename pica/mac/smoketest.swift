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
// the bundle build.sh actually produced: PICA_BUILD_DIR, else /tmp/pica-build (the
// default since builds moved out of the iCloud-synced tree), else the old mac/build
let buildDir = ProcessInfo.processInfo.environment["PICA_BUILD_DIR"].map { URL(fileURLWithPath: $0) }
    ?? (FileManager.default.fileExists(atPath: "/tmp/pica-build/PICA.app/Contents/Resources/web/index.html")
        ? URL(fileURLWithPath: "/tmp/pica-build") : here.appendingPathComponent("build"))
let webRoot = buildDir.appendingPathComponent("PICA.app/Contents/Resources/web")
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

// ---- the typing grammar, checked against Final Draft's table ----
// Each step: do something, then assert the resulting element types/text.
struct Step { let desc: String; let js: String; let expect: String }

let grammarSteps: [Step] = [
    // Scene Heading + Enter → Action
    Step(desc: "slug typed, Enter gives Action",
         js: "await T.reset(); T.caret(0,0); T.type('INT. HOUSE - DAY'); T.esc(); T.enter(); return T.state().join('§')",
         expect: "scene|INT. HOUSE - DAY§action|"),
    // Action + Enter → Action
    Step(desc: "Action + Enter gives Action",
         js: "T.type('He waits.'); T.esc(); T.enter(); return T.state().slice(1).join('§')",
         expect: "action|He waits.§action|"),
    // Tab on a blank Action → Character
    Step(desc: "Tab in a blank Action gives Character",
         js: "T.tab(false); T.esc(); return T.state().slice(2).join('§')",
         expect: "character|"),
    // Character + Enter → Dialogue  (the bug: SmartType used to swallow Return)
    Step(desc: "Character + Enter gives Dialogue",
         js: "T.type('SAM'); T.enter(); T.esc(); return T.state().slice(2).join('§')",
         expect: "character|SAM§dialogue|"),
    // Dialogue + Tab → Parenthetical, ready to type inside the brackets
    Step(desc: "Dialogue + Tab gives a Parenthetical",
         js: "T.type('Hello.'); T.esc(); T.tab(false); return T.state().slice(3).join('§')",
         expect: "dialogue|Hello.§paren|()"),
    // typing inside the brackets, then Tab → Dialogue  (the bug he found)
    Step(desc: "Tab from inside a written Parenthetical gives Dialogue",
         js: "T.type('beat'); T.esc(); T.tab(false); return T.state().slice(4).join('§')",
         expect: "paren|(beat)§dialogue|"),
    // Parenthetical + Enter → Dialogue
    Step(desc: "Enter from inside a Parenthetical gives Dialogue",
         js: "await T.reset(); T.caret(0,0); T.type('INT. X - DAY'); T.esc(); T.enter(); T.tab(false); T.type('SAM'); T.esc(); T.enter(); T.tab(false); T.type('beat'); T.esc(); T.enter(); return T.state().slice(2).join('§')",
         expect: "paren|(beat)§dialogue|"),
    // Dialogue + Enter → Action
    Step(desc: "Dialogue + Enter gives Action",
         js: "T.type('Hi.'); T.esc(); T.enter(); return T.state().slice(3).join('§')",
         expect: "dialogue|Hi.§action|"),
    // int. typed in Action promotes to a Scene Heading
    Step(desc: "typing int. in Action promotes it to a Scene Heading",
         js: "T.type('int. barn'); T.esc(); return T.state().slice(4).join('§')",
         expect: "scene|INT. BARN"),
    // Transition + Enter → Scene Heading
    Step(desc: "Transition + Enter gives a Scene Heading",
         js: "await T.reset(); T.caret(0,0); T.type('INT. X - DAY'); T.esc(); T.enter(); T.tab(false); T.tab(false); T.esc(); T.type('CUT TO:'); T.esc(); T.enter(); return T.state().slice(1).join('§')",
         expect: "transition|CUT TO:§scene|"),
    // Annotation: hidden until the mode is on (zero interference); then the box +
    // wash render, the span shifts with typing ahead of it, and delete clears.
    Step(desc: "annotation: mode-gated, box renders, span shifts, delete clears",
         js: "await T.reset(); T.caret(0,0); T.type('INT. NOTE - DAY'); T.esc(); T.enter(); T.type('He waits a long moment before answering.'); T.esc(); T.note(1, 3, 5, 'love this'); const gated = T.noteBoxes(); window.PICA_API.toggleAnnotate(); const b1 = T.noteBoxes(); T.caret(1, 0); T.type('XX'); const n = JSON.parse(T.notes(1))[0]; const shifted = n.off + ',' + n.len + ',' + n.text; T.delNote(1, n.id); const b2 = T.noteBoxes(); window.PICA_API.toggleAnnotate(); return gated + '/' + b1 + '/' + shifted + '/' + b2",
         expect: "0:0/1:1/5,5,love this/0:0"),
    // A note can cover a cue AND its dialogue: washes on both elements, ONE box,
    // and delete clears every segment.
    Step(desc: "annotation: multi-element note — two washes, one box, delete clears all",
         js: "await T.reset(); T.caret(0,0); T.type('INT. TWO - DAY'); T.esc(); T.enter(); T.tab(false); T.type('SAM'); T.esc(); T.enter(); T.type('We were never here.'); T.esc(); window.PICA_API.toggleAnnotate(); const nid = T.noteMulti(1, 0, 2, 8); const b1 = T.noteBoxes(); T.delNote(0, nid); const b2 = T.noteBoxes(); window.PICA_API.undo(); const b3 = T.noteBoxes(); const back = JSON.parse(T.notes(1)).length + JSON.parse(T.notes(2)).length; window.PICA_API.redo(); const b4 = T.noteBoxes(); window.PICA_API.toggleAnnotate(); return b1 + '/' + b2 + '/' + b3 + '/' + back + '/' + b4",
         expect: "1:2/0:0/1:2/2/0:0"),
    // Storyboard: same gating; a panel anchors at a position, shifts with typing,
    // hides when the mode turns off, returns when it turns on, deletes clean.
    Step(desc: "storyboard: mode-gated, panel anchors, shifts, survives toggling, deletes",
         js: "await T.reset(); T.caret(0,0); T.type('INT. BOARD - DAY'); T.esc(); T.enter(); T.type('The cab rolls through the empty intersection.'); T.esc(); T.panel(1, 4); const gated = T.sbCount(); window.PICA_API.toggleStoryboard(); const on = T.sbCount(); T.caret(1, 0); T.type('XX'); const off = JSON.parse(T.panels(1))[0].off; window.PICA_API.toggleStoryboard(); const hidden = T.sbCount(); window.PICA_API.toggleStoryboard(); const back = T.sbCount(); const pid = JSON.parse(T.panels(1))[0].id; T.delPanel(1, pid); const after = T.sbCount(); window.PICA_API.undo(); const restored = T.sbCount(); window.PICA_API.toggleStoryboard(); return gated + '/' + on + '/' + off + '/' + hidden + '/' + back + '/' + after + '/' + restored",
         expect: "0/1/6/0/1/0/1"),
]

func runGrammar(_ i: Int) {
    if i >= grammarSteps.count { finishAll(); return }
    let s = grammarSteps[i]
    let body = "try { const T = window.PICA_API.test; " + s.js + " } catch(e) { return 'ERR: ' + (e && e.message || e); }"
    web.callAsyncJavaScript(body, arguments: [:], in: nil, in: .page) { result in
        var got = "<no result>"
        if case .success(let v) = result { got = (v as? String) ?? "<no result>" }
        if case .failure(let e) = result { got = "EVALERR: " + String(describing: e) }
        check("grammar: " + s.desc, got == s.expect, got == s.expect ? "" : "got “\(got)” want “\(s.expect)”")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { runGrammar(i + 1) }
    }
}

func finish() {
    print("  … checking the typing grammar against Final Draft's table")
    runGrammar(0)
}

func finishAll() {
    print(failures == 0 ? "\nPICA.app verified — the bundle runs standalone" : "\n\(failures) FAILURE(S)")
    exit(failures == 0 ? 0 : 1)
}

web.load(URLRequest(url: URL(string: "pica://app/index.html")!))
DispatchQueue.main.asyncAfter(deadline: .now() + 120) { print("TIMEOUT"); exit(3) }
app.run()
