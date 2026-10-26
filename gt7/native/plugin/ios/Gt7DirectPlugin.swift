// Gt7Direct: the iOS app talks to Gran Turismo 7 directly, no bridge.
//  - startTelemetry({ ps5: "192.168.1.23" | "auto" }): heartbeats the PS5 on UDP 33739
//    every 10 s and emits every packet it sends back to UDP 33740 as `packet`
//    { data: base64, from: ip }. "auto" heartbeats every address on this Wi-Fi /24
//    (plain unicast, so no multicast entitlement) and locks on to whoever answers.
//  - gt7SignIn(): presents gran-turismo.com in a web view (Sony's own PSN sign-in),
//    then reads the site's API token. gt7Token(): the same, silently, from the
//    saved session (lasts about a week).
import Foundation
import Capacitor
import WebKit
import Darwin

@objc(Gt7DirectPlugin)
public class Gt7DirectPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "Gt7DirectPlugin"
    public let jsName = "Gt7Direct"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "startTelemetry", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopTelemetry", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "gt7SignIn", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "gt7Token", returnType: CAPPluginReturnPromise),
    ]

    private var recvFd: Int32 = -1
    private var sendFd: Int32 = -1
    private var running = false
    private var ps5: String? = nil
    private var beatTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "gt7.beat")        // heartbeats
    private let recvQueue = DispatchQueue(label: "gt7.recv")    // the blocking receive loop gets its own

    // ── telemetry ──
    @objc func startTelemetry(_ call: CAPPluginCall) {
        stop()
        let target = call.getString("ps5") ?? "auto"
        recvFd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        sendFd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard recvFd >= 0, sendFd >= 0 else { call.reject("Couldn't open a UDP socket"); return }
        var yes: Int32 = 1
        setsockopt(recvFd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in(); addr.sin_family = sa_family_t(AF_INET); addr.sin_port = in_port_t(33740).bigEndian; addr.sin_addr.s_addr = in_addr_t(0)  // INADDR_ANY
        let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(recvFd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard ok == 0 else { call.reject("UDP port 33740 is busy"); return }
        running = true
        ps5 = target == "auto" ? nil : target
        recvQueue.async { [weak self] in self?.receiveLoop() }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 10)
        t.setEventHandler { [weak self] in self?.heartbeat() }
        t.resume(); beatTimer = t
        notifyListeners("status", data: ["status": ps5 == nil ? "searching" : "connecting", "ps5": ps5 ?? ""])
        call.resolve()
    }
    @objc func stopTelemetry(_ call: CAPPluginCall) { stop(); call.resolve() }

    private func stop() {
        running = false
        beatTimer?.cancel(); beatTimer = nil
        if recvFd >= 0 { close(recvFd); recvFd = -1 }
        if sendFd >= 0 { close(sendFd); sendFd = -1 }
    }
    private func send(_ ip: String) {
        var to = sockaddr_in(); to.sin_family = sa_family_t(AF_INET); to.sin_port = in_port_t(33739).bigEndian
        inet_pton(AF_INET, ip, &to.sin_addr)
        let beat: [UInt8] = [0x7E] // "~": the 344-byte packet with steering
        _ = withUnsafePointer(to: &to) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(sendFd, beat, 1, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    }
    private func heartbeat() {
        if let ip = ps5 { send(ip); return }
        guard let me = Gt7DirectPlugin.wifiIPv4() else { return }
        let base = me.split(separator: ".").prefix(3).joined(separator: ".")
        for h in 1...254 { let ip = "\(base).\(h)"; if ip != me { send(ip) } }
    }
    private func receiveLoop() {
        var buf = [UInt8](repeating: 0, count: 2048)
        while running && recvFd >= 0 {
            var from = sockaddr_in(); var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(recvFd, &buf, buf.count, 0, $0, &len) } }
            if n <= 0 { continue }
            var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &from.sin_addr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
            let ip = String(cString: ipBuf)
            if ps5 == nil { ps5 = ip; notifyListeners("status", data: ["status": "live", "ps5": ip]) }
            let data = Data(buf[0..<n]).base64EncodedString()
            notifyListeners("packet", data: ["data": data, "from": ip])
        }
    }
    static func wifiIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var p = ifaddr
        while let a = p {
            let f = a.pointee
            if let sa = f.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET), String(cString: f.ifa_name) == "en0" {
                var h = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(sa, socklen_t(sa.pointee.sa_len), &h, socklen_t(h.count), nil, 0, NI_NUMERICHOST)
                return String(cString: h)
            }
            p = f.ifa_next
        }
        return nil
    }

    // ── GT7 account via gran-turismo.com ──
    private var web: WKWebView?
    private var pending: CAPPluginCall?
    private var shown: UIViewController?
    private static let tokenJS = "fetch('/us/gt7/info/api/token/', {credentials:'include'}).then(r => r.ok ? r.json() : null).catch(() => null)"

    @objc func gt7Token(_ call: CAPPluginCall) { DispatchQueue.main.async { self.openWeb(call, interactive: false) } }
    @objc func gt7SignIn(_ call: CAPPluginCall) { DispatchQueue.main.async { self.openWeb(call, interactive: true) } }

    private func openWeb(_ call: CAPPluginCall, interactive: Bool) {
        pending = call
        let w = WKWebView(frame: .zero, configuration: { let c = WKWebViewConfiguration(); c.websiteDataStore = .default(); return c }())
        w.navigationDelegate = self; web = w
        let start = interactive ? "https://www.gran-turismo.com/us/gt7/user/mymenu/" : "https://www.gran-turismo.com/us/gt7/info/api/token/"
        w.load(URLRequest(url: URL(string: start)!))
        if interactive {
            let vc = UIViewController(); vc.view = w
            let nav = UINavigationController(rootViewController: vc)
            vc.title = "Sign in to Gran Turismo"
            vc.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelSignIn))
            shown = nav
            bridge?.viewController?.present(nav, animated: true)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.finish(nil, error: "timeout") }
        }
    }
    @objc private func cancelSignIn() { finish(nil, error: "cancelled") }
    fileprivate func tryToken() {
        guard let w = web, w.url?.host == "www.gran-turismo.com" else { return }
        guard #available(iOS 14.0, *) else { finish(nil, error: "GT7 sign-in needs iOS 14 or newer"); return }
        w.callAsyncJavaScript("return await \(Gt7DirectPlugin.tokenJS)", arguments: [:], in: nil, in: .page) { [weak self] r in
            if case let .success(v) = r, let d = v as? [String: Any], d["access_token"] != nil { self?.finish(d, error: nil) }
            else if self?.shown == nil { self?.finish(nil, error: "signin") }   // silent and no session
        }
    }
    private func finish(_ data: [String: Any]?, error: String?) {
        guard let call = pending else { return }
        pending = nil
        shown?.dismiss(animated: true); shown = nil
        web?.navigationDelegate = nil; web = nil
        if let d = data { call.resolve(d.mapValues { "\($0)" }) } else { call.reject(error ?? "failed") }
    }
}

extension Gt7DirectPlugin: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { tryToken() }
}
