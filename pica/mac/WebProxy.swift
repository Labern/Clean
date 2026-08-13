import WebKit
// The page's window on the web, shared by the app and by the smoketest that proves it.
//
// A WKWebView on a custom scheme is subject to CORS like any other origin, so the
// find-a-screenplay feature cannot fetch a search engine or a screenplay PDF directly.
// This proxies one GET per request and hands the bytes back on our own origin. Only
// https, only GET, nothing is written to disk, and the page decides what to do with
// what comes back.
import Foundation

// Returns true when it has taken responsibility for the task.
func serveWebProxy(task: WKURLSchemeTask, url: URL, path: String) -> Bool {
    guard path.hasPrefix("/__web/") else { return false }
    let encoded = String(path.dropFirst("/__web/".count))
    guard let target = encoded.removingPercentEncoding.flatMap(URL.init(string:)),
          target.scheme == "https", let host = target.host, !host.isEmpty else {
        let resp = HTTPURLResponse(url: url, statusCode: 400, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "text/plain"])!
        task.didReceive(resp); task.didReceive(Data("only https GETs".utf8)); task.didFinish()
        return true
    }
    var req = URLRequest(url: target)
    req.timeoutInterval = 25
    // some script archives refuse a request with no user agent
    req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
                 + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
    req.setValue("*/*", forHTTPHeaderField: "Accept")
    var finished = false
    let lock = NSLock()
    let done: (Int, String, Data) -> Void = { code, mime, body in
        lock.lock(); defer { lock.unlock() }
        if finished { return }
        finished = true
        let resp = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": mime, "Content-Length": "\(body.count)",
            "Access-Control-Allow-Origin": "*"])!
        task.didReceive(resp); task.didReceive(body); task.didFinish()
    }
    URLSession.shared.dataTask(with: req) { data, response, err in
        if let err = err { done(502, "text/plain", Data("proxy: \(err.localizedDescription)".utf8)); return }
        let http = response as? HTTPURLResponse
        let mime = http?.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
        done(http?.statusCode ?? 200, mime, data ?? Data())
    }.resume()
    return true
}
