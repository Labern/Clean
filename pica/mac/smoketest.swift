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
        // the very proxy the app ships, so the step below proves the app's network path
        if serveWebProxy(task: task, url: url, path: p) { return }

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
var trialInbox = ""
// The title-alignment audit lives in its own file — tests/title-audit.js — rather than
// inside the app, so the app ships no test code and the check is readable on its own.
// Injected into the page before the steps run; the step then calls window.__titleAudit().
let auditJS: String = (try? String(contentsOf: here.appendingPathComponent("../tests/title-audit.js")
    .standardizedFileURL, encoding: .utf8)) ?? ""

let handler = Handler(root: webRoot)
// A second copy of the PDF, staged now, for the find-a-screenplay step: that step stubs
// the network so the DECISION is what gets tested, not the internet.
if let trialPdf = try? Data(contentsOf: URL(fileURLWithPath: pdfPath)) { trialInbox = handler.stage(trialPdf) }
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
      const L = S && S.doc ? S.doc.layout : null;
      return JSON.stringify({ done: !!(S && S.res && S.res.count > 1), failed,
        pages: S && S.res ? S.res.count : 0, els: S && S.doc ? S.doc.elements.length : 0,
        title: S && S.doc ? S.doc.title : '',
        // an import must arrive in Final Draft's typesetting, never the source's
        fd: !!(L && L.pageW === 612 && L.charW === 7.2 && L.rowH === 12
               && L.widths && L.widths.action === 60 && L.widths.dialogue === 35
               && L.cols && L.cols.character === 252),
        geom: L ? [L.pageW, L.charW, L.rowH, L.widths && L.widths.action].join('/') : '',
        src: S && S.doc ? (S.doc.src || '') : '',
        flowed: S && S.doc ? S.doc.elements.filter(e => e.type === 'dialogue' && !e.dual && e.text.indexOf(String.fromCharCode(10)) >= 0).length : -1 });
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
        // Tenet conformed to FD Letter paginates at 156 script pages (the rendered
        // array adds the title page); at the source's own geometry it was 147
        if (o["pages"] as? Int ?? 0) >= 150 {
            let pages = o["pages"] as? Int ?? 0
            let els = o["els"] as? Int ?? 0
            let title = o["title"] as? String ?? ""
            check("PDF imported offline with bundled pdf.js", true,
                  "\(pages) script pages · \(els) elements · “\(title)”")
            check("import produced the expected document", pages == 156 && els > 3500 && title == "TENET",
                  "expected 156 pages / >3500 elements / TENET")
            check("import lands in Final Draft's typesetting, not the source's",
                  o["fd"] as? Bool == true, o["geom"] as? String ?? "")
            check("import is stamped as imported (never re-geometried as a typed doc)",
                  (o["src"] as? String) == "pdf", o["src"] as? String ?? "")
            check("speeches flow — no source line breaks left inside dialogue",
                  (o["flowed"] as? Int ?? -1) == 0, String(o["flowed"] as? Int ?? -1))
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
    // ⌘B/I/U must PAINT (pageSig once ignored marks — set but never rendered),
    // and anticipation styles what you type next at a collapsed caret.
    Step(desc: "emphasis renders: selection ⌘U paints, anticipation ⌘B styles typed text",
         js: "await T.reset(); T.caret(0,0); T.type('INT. U - DAY'); T.esc(); T.enter(); T.type('Underline these words here.'); T.esc(); const line = [...document.querySelectorAll('.line')].find(d => d.textContent.startsWith('Underline')); getSelection().setBaseAndExtent(line.firstChild, 10, line.firstChild, 15); document.querySelector('#pages').dispatchEvent(new KeyboardEvent('keydown', { key: 'u', metaKey: true, bubbles: true, cancelable: true })); await new Promise(r => setTimeout(r, 120)); const u = document.querySelectorAll('.page u').length; T.caret(1, window.__pica.doc.elements[1].text.length); await new Promise(r => setTimeout(r, 40)); document.querySelector('#pages').dispatchEvent(new KeyboardEvent('keydown', { key: 'b', metaKey: true, bubbles: true, cancelable: true })); T.type(' STRONG'); await new Promise(r => setTimeout(r, 100)); return u + '/' + document.querySelectorAll('.page b').length",
         expect: "1/1"),
    // Typing through a wrap/page boundary must never teleport the caret or
    // scramble the text (the restoreCaret first-line fallback once sent typing
    // a hundred characters back).
    Step(desc: "typing across the page boundary keeps text and caret intact",
         js: "await T.reset(); T.caret(0,0); T.type('INT. SPLIT - DAY'); T.esc(); for (let i = 0; i < 23; i++) { T.enter(); T.type('Filler action line number ' + i + '.'); T.esc(); } T.enter(); T.tab(false); T.type('SAM'); T.esc(); T.enter(); const id = window.__pica.caret.el; let typed = ''; const msg = 'This is a very long speech. It keeps going with more sentences. And more still after that. It should split across the page cleanly now. Still typing away here at the end.'; for (const ch of msg) { T.type(ch); typed += ch; } const el = window.__pica.doc.elements.find(e => e.id === id); return String(el.text === typed && window.__pica.caret.el === id && window.__pica.caret.off === typed.length)",
         expect: "true"),
    // The title sits on the doc's own cue axis from the FIRST cue; a margin note
    // follows its words through a split; a stale id never resurrects a ghost.
    Step(desc: "title on cue axis (2 cues); note follows split; no ghost from stale id",
         js: "await T.reset(); T.caret(0,0); T.type('INT. STAGE - NIGHT'); T.esc(); T.enter(); T.tab(false); T.type('WRITER'); T.esc(); T.enter(); T.type('Begin now friend.'); T.esc(); T.enter(); T.tab(false); T.type('CHAIR'); T.esc(); T.enter(); T.type('Sit.'); T.esc(); await new Promise(r => setTimeout(r, 250)); const axisOk = T.titleDelta(); window.__pica.doc.elements[2].notes = [{ id: 'q1', off: 6, len: 3, text: 'yes' }]; T.caret(2, 5); T.enter(); const carried = JSON.stringify((window.__pica.doc.elements[3].notes || [])[0] || null); const n0 = JSON.parse(localStorage.getItem('pica.index')).length; const id0 = window.__pica.docId; await T.openId('no-such-doc'); const n1 = JSON.parse(localStorage.getItem('pica.index')).length; return axisOk + '/' + carried + '/' + (n1 - n0) + '/' + (window.__pica.docId === id0)",
         expect: "true/{\"id\":\"q1\",\"off\":0,\"len\":3,\"text\":\"yes\"}/0/true"),
    // Backward drag-selection from blank paper (the natural bottom-right grip)
    Step(desc: "drag-selection from blank paper selects backwards",
         js: "await T.reset(); T.caret(0,0); T.type('INT. B - DAY'); T.esc(); T.enter(); T.type('First action line here.'); T.esc(); T.enter(); T.type('Second action line here.'); T.esc(); await new Promise(r => setTimeout(r, 150)); const lines = [...document.querySelectorAll('.line')]; const l2 = lines.find(d => d.textContent.startsWith('Second')); const l1 = lines.find(d => d.textContent.startsWith('First')); const r2 = l2.getBoundingClientRect(), r1 = l1.getBoundingClientRect(); const fire = (ty, x, y) => (document.elementFromPoint(x, y) || document.querySelector('#pages')).dispatchEvent(new MouseEvent(ty, { bubbles: true, cancelable: true, clientX: x, clientY: y, button: 0 })); fire('mousedown', r2.right + 60, r2.top + 4); fire('mousemove', (r1.left + r1.right) / 2, r1.top + 4); fire('mouseup', (r1.left + r1.right) / 2, r1.top + 4); await new Promise(r => setTimeout(r, 60)); const sel = getSelection(); return String(!sel.isCollapsed && sel.toString().length > 10)",
         expect: "true"),
    // FD keeps emphasis through splits and merges; Tab acts from anywhere
    Step(desc: "bold survives split and merge; Tab acts mid-paragraph",
         js: "await T.reset(); T.caret(0,0); T.type('INT. Q - DAY'); T.esc(); T.enter(); T.type('Bold words here now.'); T.esc(); window.__pica.doc.elements[1].marks = [[5, 19, 'b']]; T.caret(1, 12); T.enter(); const sp = JSON.stringify(window.__pica.doc.elements[1].marks) + JSON.stringify(window.__pica.doc.elements[2].marks); T.caret(2, 0); document.querySelector('#pages').dispatchEvent(new InputEvent('beforeinput', { inputType: 'deleteContentBackward', bubbles: true, cancelable: true })); const mg = JSON.stringify(window.__pica.doc.elements[1].marks); T.caret(1, 4); T.tab(false); return sp + '¤' + mg + '¤' + window.__pica.doc.elements[2].type",
         expect: "[[5,12,\"b\"]][[0,7,\"b\"]]¤[[5,19,\"b\"]]¤character"),
    // Input must NEVER be eaten: macOS substitutions (double-space→period, smart
    // quotes) arrive as insertReplacementText; ⌥⌫ as deleteWordBackward; dead keys
    // via composition. All must land in the model.
    Step(desc: "input never eaten: replacement text, word delete, composition",
         js: "await T.reset(); T.caret(0,0); T.type('INT. Z - DAY'); T.esc(); T.enter(); T.type('Hello'); T.esc(); const bi = (ty, d) => document.querySelector('#pages').dispatchEvent(new InputEvent('beforeinput', { inputType: ty, data: d, bubbles: true, cancelable: true })); bi('insertReplacementText', '. '); T.type('word'); T.esc(); bi('deleteWordBackward'); const P = document.querySelector('#pages'); P.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true })); P.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true, data: 'é' })); return JSON.stringify(window.__pica.doc.elements[1].text)",
         expect: "\"Hello. é\""),
    // Tab from a BLANK dialogue must give a visible \"()\" with the caret inside
    Step(desc: "Tab on blank dialogue shows () immediately",
         js: "await T.reset(); T.caret(0,0); T.type('INT. Y - DAY'); T.esc(); T.enter(); T.tab(false); T.type('SAM'); T.esc(); T.enter(); T.tab(false); const els = window.__pica.doc.elements; const el = els[els.length - 1]; return el.type + '|' + el.text + '|' + T.caretAt()",
         expect: "paren|()|2:1"),
    // THE bug he hit: same speaker again + Enter must append (CONT'D) to the cue
    // and land in dialogue — never split the cue into a stray "(CONT'D)" element.
    Step(desc: "auto-(CONT'D): appended to the cue, caret lands in dialogue",
         js: "await T.reset(); T.caret(0,0); T.type('INT. A - DAY'); T.esc(); T.enter(); T.tab(false); T.type('SAM'); T.esc(); T.enter(); T.type('Hello there.'); T.esc(); T.enter(); T.type('He waits.'); T.esc(); T.tab(false); T.type('SAM'); T.esc(); T.enter(); const after = T.state().slice(1).join('§') + '¶' + T.caretAt(); window.PICA_API.undo(); const undone = T.state().slice(1).join('§'); window.PICA_API.redo(); return after + '¤' + undone",
         expect: "character|SAM§dialogue|Hello there.§action|He waits.§character|SAM (CONT'D)§dialogue|¶5:0¤character|SAM§dialogue|Hello there.§action|He waits.§character|SAM"),
    // Enter on a blank Character with no list open falls back to Action
    Step(desc: "Enter on a blank Character (no list) gives Action",
         js: "await T.reset(); T.caret(0,0); T.type('INT. B - DAY'); T.esc(); T.enter(); T.tab(false); T.esc(); T.enter(); return T.state().slice(1).join('§')",
         expect: "action|"),
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
    // The row a context menu belongs to marks itself (so Delete can never look like it
    // landed on the wrong script), and the list animates into its new shape afterwards.
    Step(desc: "index: the right-clicked row marks itself; the list animates after a delete",
         js: "window.confirm = () => true; const rows = () => [...document.querySelectorAll('#docList .doc-item')]; for (const n of ['ONE','TWO','THREE']) { await T.reset(); T.caret(0,0); T.type('INT. ' + n + ' - DAY'); } await new Promise(r => setTimeout(r, 60)); const ids = rows().every(x => !!x.dataset.doc); const r2 = rows()[1]; r2.dispatchEvent(new MouseEvent('contextmenu', {bubbles:true, cancelable:true, clientX:60, clientY:140})); await new Promise(r => setTimeout(r, 40)); const marked = document.querySelectorAll('#docList .doc-item.menuing').length + '/' + r2.classList.contains('menuing'); const del = [...document.querySelectorAll('.pop *')].find(n => /^delete/i.test(n.textContent.trim())); if (!del) return 'no-delete-item'; del.dispatchEvent(new MouseEvent('mousedown', {bubbles:true, cancelable:true})); del.dispatchEvent(new MouseEvent('click', {bubbles:true, cancelable:true})); await new Promise(r => setTimeout(r, 30)); const moving = rows().filter(x => x.getAnimations && x.getAnimations().length).length > 0; await new Promise(r => setTimeout(r, 400)); const cleared = document.querySelectorAll('#docList .doc-item.menuing').length === 0; return ids + '/' + marked + '/' + moving + '/' + cleared",
         expect: "true/1/true/true/true"),
    // THE APP'S WINDOW ON THE WEB. A WKWebView on a custom scheme is subject to CORS, so
    // without this proxy the search cannot reach an archive at all. This goes online for
    // real: it asks an archive's index page for its links and counts the PDFs.
    Step(desc: "find: the app can reach the web and read an archive's index",
         js: "try { const r = await fetch('pica://app/__web/' + encodeURIComponent('https://www.dailyscript.com/movie.html')); if (!r.ok) return 'HTTP ' + r.status; const t = await r.text(); const pdfs = (t.match(/href=\"[^\"]+\\.pdf\"/gi) || []).length; return pdfs > 100 ? 'reached' : 'only ' + pdfs + ' pdfs'; } catch (e) { return 'threw: ' + (e.message || e); }",
         expect: "reached"),
    // A REAL search, over the real web, inside the app: what does it find for a film?
    // Reported, not asserted — the network is not something an install should hang on.
    Step(desc: "find: a live search (reported, not gated)",
         js: "try { const c = await window.PICA_API.test.search('Pulp Fiction'); return c.length ? ('found ' + c.length + ': ' + c.slice(0,3).map(x => x.host).join(', ')) : 'found none'; } catch (e) { return 'threw: ' + (e.message || e); }",
         expect: "*"),
    // THE WHOLE CHAIN, LIVE: search the web, download the winner, import it, put it on
    // screen. Reported rather than asserted — an install must not hang on the weather —
    // but this is the one that answers "does it actually work".
    Step(desc: "find: the whole chain, live (reported, not gated)",
         js: "try { const T3 = window.PICA_API.test; const before = JSON.parse(localStorage.getItem('pica.index')||'[]').length; await T3.find('Pulp Fiction'); const d = window.__pica.doc; const shown = document.getElementById('trialBar').hidden === false; const from = (document.getElementById('tbFrom')||{}).textContent || ''; const held = JSON.parse(localStorage.getItem('pica.index')||'[]').length === before; const out = shown ? ('SHOWING \\\"' + d.title + '\\\" ' + window.__pica.res.count + 'pp ' + d.elements.length + ' elements · ' + from + ' · librarySafe=' + held) : ('nothing shown'); document.getElementById('tbCancel').click(); await new Promise(r=>setTimeout(r,500)); return out; } catch (e) { return 'threw: ' + (e.message || e); }",
         expect: "*"),
    // FIND A SCREENPLAY: the promise is that nothing reaches the library unless he
    // accepts it. Cancel must put back what he was reading and leave no trace — the
    // first cut of this saved the rejected script anyway, because openDoc flushes a
    // save of the document it is leaving and the guard had already been lifted.
    Step(desc: "find: a trial stays out of the library; cancel restores; accept keeps",
         js: "const T2 = window.PICA_API.test; const idx = () => JSON.parse(localStorage.getItem('pica.index') || '[]'); const buf = await (await fetch('pica://app/__inbox/\(trialInbox)')).arrayBuffer(); T2.stubNet({ candidates: async () => ([{url:'stub://one', host:'stub.test', label:'', score:99}]), bytes: async () => buf.slice(0) }); const before = idx().length; const openBefore = window.__pica.docId; await T2.find('A Script'); await new Promise(r => setTimeout(r, 300)); const during = idx().length; const tid = T2.trialId(); const shown = document.getElementById('trialBar').hidden === false; document.getElementById('tbCancel').click(); await new Promise(r => setTimeout(r, 500)); const afterCancel = idx().length; const backTo = window.__pica.docId === openBefore; await T2.find('A Script'); await new Promise(r => setTimeout(r, 300)); const tid2 = T2.trialId(); const br = document.getElementById('trialBar').getBoundingClientRect(); const pr = document.querySelector('#pages .pageWrap').getBoundingClientRect(); const masks = br.width > 0 && pr.width > 0 && br.left <= pr.left && br.right >= pr.right; document.getElementById('tbAccept').click(); await new Promise(r => setTimeout(r, 400)); const kept = idx().some(d => d.id === tid2); T2.stubNet(null); return ['shown=' + shown, 'idxHeld=' + (during === before), 'trial=' + !!tid, 'cancelClean=' + (afterCancel === before), 'restored=' + backTo, 'accepted=' + kept, 'masks=' + masks].join(' ')",
         expect: "shown=true idxHeld=true trial=true cancelClean=true restored=true accepted=true masks=true"),
    // THE TITLE SITS ON THE CHARACTER COLUMN. Reported three times; never again.
    // titleAudit() walks everything that moves the page under the title — the sidebar,
    // zoom, the title page, a long title, scrolling — and measures the title's FIRST
    // CHARACTER against a cue as actually DRAWN, not against the formula that places it
    // (which is exactly how a misaligned title passed this suite for days). It also
    // fails if the placement is being done by centring again.
    Step(desc: "title: first character sits on the cue column, through rail/zoom/titlepage/scroll",
         js: auditJS.isEmpty ? "return 'MISSING tests/title-audit.js'" : (auditJS + "\n; return await window.__titleAudit()"),
         expect: "aligned"),
    // Deleting the script that is OPEN used to do nothing at all: the delete filtered
    // the index, then openDoc() flushed a save of the outgoing document and put the row
    // straight back. The index must lose the row, and keep having lost it after the
    // save debounce has had its chance.
    Step(desc: "delete: the open script leaves the index and stays gone",
         js: "window.confirm = () => true; const ix0 = () => JSON.parse(localStorage.getItem('pica.index') || '[]'); await T.reset(); T.caret(0,0); T.type('INT. ONE - DAY'); await T.reset(); T.caret(0,0); T.type('INT. TWO - DAY'); await new Promise(r => setTimeout(r, 60)); const before = ix0().length; const openId = window.__pica.docId; const rows = [...document.querySelectorAll('#docList .doc-item')]; const at = ix0().findIndex(d => d.id === openId); const row = rows[at] || rows[0]; row.dispatchEvent(new MouseEvent('contextmenu', {bubbles:true, cancelable:true, clientX:60, clientY:140})); await new Promise(r => setTimeout(r, 40)); const del = [...document.querySelectorAll('.pop *')].find(n => /^delete/i.test(n.textContent.trim())); if (!del) return 'no-delete-item'; del.dispatchEvent(new MouseEvent('mousedown', {bubbles:true, cancelable:true})); del.dispatchEvent(new MouseEvent('click', {bubbles:true, cancelable:true})); await new Promise(r => setTimeout(r, 80)); const mid = ix0(); const goneNow = !mid.some(d => d.id === openId); await new Promise(r => setTimeout(r, 900)); const stillGone = !ix0().some(d => d.id === openId); return (before >= 2) + '/' + goneNow + '/' + stillGone",
         expect: "true/true/true"),
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
        // expect "*" means REPORT, do not gate — used for the live web, which an install
        // should not hang on
        if s.expect == "*" { print("  ·· " + s.desc + " — " + got) }
        else { check("grammar: " + s.desc, got == s.expect, got == s.expect ? "" : "got “\(got)” want “\(s.expect)”") }
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
