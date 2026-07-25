// makepdf.swift — render an HTML file to a single-page PDF, natively.
//   swiftc -O makepdf.swift -o build/makepdf
//   ./build/makepdf docs/FEATURES.html docs/FEATURES.pdf
//
// Uses WKWebView.createPDF against a fixed A4 rect (595×842pt), so the output is
// exactly one page by construction rather than by hoping the paginator agrees.
// It measures the laid-out content first and says how much room is left — if the
// content is taller than the page it would be clipped, so that is reported as a
// failure rather than silently shipped.
//
// Activation policy is .prohibited: no window, no Dock tile, no stolen focus.
import Cocoa
import WebKit

let A4 = CGSize(width: 595, height: 842)

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: makepdf <input.html> <output.pdf>")
    exit(2)
}
let input = URL(fileURLWithPath: args[1]).standardizedFileURL
let output = URL(fileURLWithPath: args[2]).standardizedFileURL

final class Renderer: NSObject, WKNavigationDelegate {
    var done = false
    var failed: String?
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { done = true }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) {
        failed = e.localizedDescription
    }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
        failed = e.localizedDescription
    }
}

func wait(_ timeout: TimeInterval, _ cond: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if cond() { return true }
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.03))
    }
    return cond()
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let r = Renderer()
let cfg = WKWebViewConfiguration()
cfg.websiteDataStore = .nonPersistent()
let web = WKWebView(frame: NSRect(origin: .zero, size: A4), configuration: cfg)
web.navigationDelegate = r
// The page is styled in points for A4; keep 1 CSS px == 1 pt so the design and
// the PDF agree exactly.
web.pageZoom = 1.0

web.loadFileURL(input, allowingReadAccessTo: input.deletingLastPathComponent())
guard wait(20, { r.done || r.failed != nil }), r.failed == nil else {
    print("✗ could not load \(input.lastPathComponent): \(r.failed ?? "timed out")")
    exit(1)
}

// Let webfonts settle — measuring before they load gives the wrong height.
var fontsReady = false
web.evaluateJavaScript("document.fonts.ready.then(() => true)") { _, _ in fontsReady = true }
_ = wait(5) { fontsReady }
_ = wait(0.4) { false }

// Measure, so clipping is caught rather than shipped. The page fixes html/body to
// exactly one A4 height, which means scrollHeight would just report that height
// back — useless as an overflow check. So release the height, measure what the
// content actually wants, then put it back.
var contentHeight = 0.0
var measured = false
// scrollHeight alone is no good here twice over: html/body are pinned to one A4
// height, and the footer is absolutely positioned at the page bottom, so the
// number just comes back as the page height whatever the content does. What
// actually matters is whether the flowing content has reached the footer — so
// measure the lowest edge of everything in normal flow against the footer's top.
web.evaluateJavaScript("""
(() => {
  const footer = document.querySelector('footer');
  const limit = footer ? footer.getBoundingClientRect().top - 4
                       : document.documentElement.clientHeight;
  let lowest = 0;
  for (const el of document.body.children) {
    if (el === footer) continue;
    const r = el.getBoundingClientRect();
    if (r.height > 0) lowest = Math.max(lowest, r.bottom);
  }
  // Report content height as "where the content ends, plus the room the footer
  // needs", so the caller's spare/OVER arithmetic against the page stays honest.
  return lowest + (document.documentElement.clientHeight - limit);
})()
""") { v, _ in
    contentHeight = (v as? NSNumber)?.doubleValue ?? 0
    measured = true
}
_ = wait(5) { measured }
_ = wait(0.3) { false }        // let layout settle back before capturing

let slack = A4.height - contentHeight
print(String(format: "content %.0fpt of %.0fpt (1 CSS px = 1 pt) — %.0fpt %@",
             contentHeight, A4.height, abs(slack), slack >= 0 ? "spare" : "OVER"))

var pdfData: Data?
var pdfDone = false
let pdfCfg = WKPDFConfiguration()
pdfCfg.rect = CGRect(origin: .zero, size: A4)
web.createPDF(configuration: pdfCfg) { result in
    if case .success(let d) = result { pdfData = d }
    pdfDone = true
}
_ = wait(20) { pdfDone }

guard let data = pdfData else { print("✗ createPDF produced nothing"); exit(1) }
do { try data.write(to: output) } catch {
    print("✗ could not write \(output.path): \(error.localizedDescription)"); exit(1)
}

print("✓ wrote \(output.path) — \(data.count / 1024) KB")
if slack < 0 {
    print("✗ content is taller than one page and would be clipped — tighten the HTML")
    exit(1)
}
exit(0)
