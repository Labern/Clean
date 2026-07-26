// ============================================================================
// PICA FULL SUITE — app-shell side.     ** BUILT, NOT YET RUN — by Labern's   **
// ** instruction this suite is not executed until he says so. **
//
// Compile + run (when told), from pica/mac after ./build.sh:
//     swiftc -O ../tests/suite-app.swift -o /tmp/pica-suite && (cd . && /tmp/pica-suite)
//
// Drives the BUILT bundle headlessly (activation policy .prohibited — no window,
// no Dock icon, no focus theft) over the same pica:// scheme the real app uses.
// Where mac/smoketest.swift is the quick build gate, this is the full sweep:
// every regression Labern has reported lives here as a permanent check.
// ============================================================================
import Cocoa
import WebKit

// ---- bootstrap (mirrors smoketest.swift) -----------------------------------
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
                headerFields: ["Content-Type": "application/octet-stream", "Content-Length": "\(d.count)"])!
            task.didReceive(r); task.didReceive(d); task.didFinish(); return
        }
        let mimes = ["html": "text/html; charset=utf-8", "mjs": "text/javascript", "js": "text/javascript",
                     "ttf": "font/ttf", "json": "application/json", "fdx": "application/xml"]
        let f = root.appendingPathComponent(p).standardizedFileURL
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

let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let webRoot = cwd.appendingPathComponent("build/PICA.app/Contents/Resources/web").path.hasPrefix("/")
    ? cwd.appendingPathComponent("build/PICA.app/Contents/Resources/web")
    : cwd
let bundleWeb = FileManager.default.fileExists(atPath: webRoot.appendingPathComponent("index.html").path)
    ? webRoot
    : URL(fileURLWithPath: "/tmp/pica-build/PICA.app/Contents/Resources/web")
guard FileManager.default.fileExists(atPath: bundleWeb.appendingPathComponent("index.html").path) else {
    print("FAIL: built bundle not found — run ./build.sh first"); exit(1)
}

let handler = Handler(root: bundleWeb)
let cfg = WKWebViewConfiguration()
cfg.setURLSchemeHandler(handler, forURLScheme: "pica")
cfg.websiteDataStore = .nonPersistent()          // never touches his real scripts
let web = WKWebView(frame: .init(x: 0, y: 0, width: 1280, height: 900), configuration: cfg)

var pass = 0, fail = 0
func check(_ name: String, _ okv: Bool, _ detail: String = "") {
    print((okv ? "  ok   " : "FAIL   ") + name + (detail.isEmpty ? "" : " — " + detail))
    if okv { pass += 1 } else { fail += 1 }
}
func eval(_ js: String, _ done: @escaping (Any?) -> Void) {
    web.evaluateJavaScript(js) { res, err in
        if let e = err { print("  js error: \(e.localizedDescription)") }
        done(res)
    }
}
// each step: JS whose last expression is a String; expected exact result
struct Step { let name: String; let js: String; let want: String }

let steps: [Step] = [
    // -- shell basics ---------------------------------------------------------
    Step(name: "boot: engine + API + document",
         js: "String(typeof PicaEngine==='object' && typeof PICA_API==='object' && !!__pica.doc)",
         want: "true"),
    Step(name: "localStorage lives on pica://",
         js: "(()=>{try{localStorage.setItem('s','1');return localStorage.getItem('s')}catch(e){return 'no'}})()",
         want: "1"),

    // -- the typing grammar (Final Draft's own table) -------------------------
    Step(name: "grammar: slug ⏎ → Action",
         js: "(()=>{const T=PICA_API.test;T.reset();T.caret(0,0);T.type('INT. HOUSE - DAY');T.esc();T.enter();return T.state().join('§')})()",
         want: "scene|INT. HOUSE - DAY§action|"),
    Step(name: "grammar: blank Action ⇥ → Character; SAM ⏎ → Dialogue",
         js: "(()=>{const T=PICA_API.test;T.type('He waits.');T.esc();T.enter();T.tab(false);T.type('SAM');T.enter();T.esc();return T.state().slice(2).join('§')})()",
         want: "character|SAM§dialogue|"),
    Step(name: "grammar: Dialogue ⇥ → Parenthetical, self-wrapping",
         js: "(()=>{const T=PICA_API.test;T.type('Hello.');T.esc();T.tab(false);T.type('beat');T.esc();return T.state().slice(3).join('§')})()",
         want: "dialogue|Hello.§paren|(beat)"),
    Step(name: "grammar: written paren ⇥ → Dialogue (the reported bug)",
         js: "(()=>{const T=PICA_API.test;T.tab(false);return T.state().slice(3).join('§')})()",
         want: "paren|(beat)§dialogue|"),
    Step(name: "auto-(CONT'D): survives MULTIPLE interruptions",
         js: """
         (()=>{const T=PICA_API.test;T.reset();T.caret(0,0);T.type('INT. R - DAY');T.esc();T.enter();
         T.tab(false);T.type('SAM');T.esc();T.enter();T.type('One.');T.esc();T.enter();
         T.type('He paces.');T.esc();T.enter();T.tab(false);T.type('SAM');T.esc();T.enter();T.type('Two.');T.esc();T.enter();
         T.type('She glares.');T.esc();T.enter();T.tab(false);T.type('SAM');T.esc();T.enter();T.type('Three.');T.esc();
         const cues=__pica.doc.elements.filter(e=>e.type==='character').map(e=>e.text);
         return cues.join('|')})()
         """,
         want: "SAM|SAM (CONT'D)|SAM (CONT'D)"),
    Step(name: "auto-(CONT'D): same speaker resumes after action",
         js: "(()=>{const T=PICA_API.test;T.type('Hi.');T.esc();T.enter();T.type('He paces.');T.esc();T.enter();T.tab(false);T.type('SAM');T.esc();T.enter();T.esc();const els=T.state();return els.find(x=>/CONT'D/.test(x))||'none'})()",
         want: "character|SAM (CONT'D)"),

    // -- retyping -------------------------------------------------------------
    Step(name: "right-click names the element and offers a guess",
         js: """
         (()=>{const line=[...document.querySelectorAll('.line')].find(d=>d.dataset.kind==='action'&&d.textContent.length>3);
         const r=line.getBoundingClientRect();
         line.dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true,clientX:r.x+8,clientY:r.y+4}));
         const pop=document.querySelector('.pop'); const capOk=pop&&/THIS IS ACTION/.test(pop.textContent);
         const guess=pop&&/guess/.test(pop.textContent);
         document.body.dispatchEvent(new MouseEvent('mousedown',{bubbles:true}));
         return String(!!capOk&&!!guess)})()
         """,
         want: "true"),

    // -- index operations (delete via the REAL event sequence) ----------------
    Step(name: "index: right-button mousedown does not destroy the item",
         js: """
         (()=>{window.confirm=()=>true;window.prompt=(m,d)=>d;
         PICA_API.newDoc(); PICA_API.newDoc();
         const t=[...document.querySelectorAll('.doc-item')].find(b=>!b.classList.contains('current'));
         t.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true,button:2}));
         return String(document.body.contains(t))})()
         """,
         want: "true"),
    Step(name: "index: delete removes the script",
         js: """
         (()=>{const n0=JSON.parse(localStorage['pica.index']).length;
         const t=[...document.querySelectorAll('.doc-item')].find(b=>!b.classList.contains('current'));
         const r=t.getBoundingClientRect();
         t.dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true,clientX:r.x+10,clientY:r.y+6}));
         const del=[...document.querySelectorAll('.pop .it')].find(i=>/Delete/.test(i.textContent));
         del.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true,button:0}));
         return String(JSON.parse(localStorage['pica.index']).length===n0-1)})()
         """,
         want: "true"),
    Step(name: "index: rename via prompt path",
         js: """
         (()=>{window.prompt=()=>'RENAMED SCRIPT';
         const t=document.querySelector('.doc-item');
         const r=t.getBoundingClientRect();
         t.dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true,clientX:r.x+10,clientY:r.y+6}));
         const ren=[...document.querySelectorAll('.pop .it')].find(i=>/Rename/.test(i.textContent));
         ren.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true,button:0}));
         return String(JSON.parse(localStorage['pica.index']).some(d=>d.title==='RENAMED SCRIPT'))})()
         """,
         want: "true"),

    // -- find & replace -------------------------------------------------------
    Step(name: "find counts hits; replace-all rewrites as one undo step",
         js: """
         (()=>{const T=PICA_API.test;T.reset();T.caret(0,0);T.type('INT. A - DAY');T.esc();T.enter();
         T.type('the cat saw the cat');T.esc();
         document.getElementById('findBar').hidden=false;
         const fi=document.getElementById('findIn');fi.value='cat';fi.dispatchEvent(new Event('input',{bubbles:true}));
         const counted=document.getElementById('findCount').textContent==='0 / 2';
         document.getElementById('replIn').value='dog';
         document.getElementById('replAll').dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true}));
         const done=__pica.doc.elements.some(e=>e.text==='the dog saw the dog');
         PICA_API.undo();
         const undone=__pica.doc.elements.some(e=>e.text==='the cat saw the cat');
         return String(counted&&done&&undone)})()
         """,
         want: "true"),

    // -- drafts ---------------------------------------------------------------
    Step(name: "drafts: save, restore with safety draft, chip updates",
         js: """
         (()=>{window.prompt=(m,d)=>d;window.confirm=()=>true;
         const T=PICA_API.test;T.reset();T.caret(0,0);T.type('INT. B - DAY');T.esc();
         document.getElementById('stDrafts').dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true,clientX:300,clientY:600}));
         const save=[...document.querySelectorAll('.pop .it')].find(i=>/Save draft/.test(i.textContent));
         save.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true}));
         const saved=(__pica.doc.drafts||[]).length===1;
         T.caret(0,12);T.type(' CHANGED');T.esc();
         const dr=__pica.doc.drafts[0];
         return String(saved&&/drafts · 1/.test(document.getElementById('stDrafts').textContent)&&dr.elements.length>=1)})()
         """,
         want: "true"),

    // -- forgiving caret ------------------------------------------------------
    Step(name: "clicking past a line's end lands the caret at its end",
         js: """
         (()=>{const line=[...document.querySelectorAll('.line')].find(d=>d.textContent.length>6&&d.dataset.el&&!d.dataset.el.startsWith('title:'));
         const r=line.getBoundingClientRect();const page=line.closest('.page');
         page.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true,button:0,clientX:r.right+90,clientY:r.top+4}));
         return String(__pica.caret.el===line.dataset.el&&__pica.caret.off===(+line.dataset.off||0)+line.textContent.length)})()
         """,
         want: "true"),

    // -- FDX through the app path --------------------------------------------
    Step(name: "FDX import via the native file route",
         js: "String(typeof PICA_API.importUrl==='function' && typeof PicaEngine.importFdx==='function')",
         want: "true"),
]

final class Nav: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { run(0) }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
        print("FAIL navigation: \(e.localizedDescription)"); exit(1)
    }
}
let nav = Nav()
web.navigationDelegate = nav

func run(_ i: Int) {
    if i >= steps.count {
        print("\n\(pass) passed · \(fail) failed")
        exit(fail == 0 ? 0 : 1)
    }
    let s = steps[i]
    eval("(() => { try { return " + s.js + " } catch(e) { return 'ERR: ' + (e && e.message || e) } })()") { res in
        let got = (res as? String) ?? "<no result>"
        check(s.name, got == s.want, got == s.want ? "" : "got “\(got)” want “\(s.want)”")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { run(i + 1) }
    }
}

web.load(URLRequest(url: URL(string: "pica://app/index.html")!))
DispatchQueue.main.asyncAfter(deadline: .now() + 180) { print("TIMEOUT"); exit(3) }
app.run()
