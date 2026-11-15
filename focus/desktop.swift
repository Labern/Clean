// Focus — the desktop window.
//
// The menu bar app is the real app; this window is optional and hidden until asked for ("Open Desktop App" in the
// menu, or Settings ▸ Show Desktop App). Everything it does goes through the same Focus engine the menu uses: it
// keeps no state of its own and nothing in the menu depends on it.
//
// ORDER OF AUTHORITY (his rule, 2026-11-14): the menu has authority. The window must never conflict with it. It
// holds no record of its own — every list, name, tick and number is read from the Focus engine (the menu's own
// record) each time the view is drawn, and every action is a call into that engine. If the two could ever
// disagree, the menu's record is right and the window re-reads it. Do not add stored state here beyond what is
// purely the window's own (which row is selected; text being typed before Return).
//
// Design: the website's (paradoxica.co.uk/focus) — black ground, white ink, the Graphik face, the same greys.
import AppKit
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers
import Carbon.HIToolbox

/// The two measurements the top of the window hangs on: the session button and the logo share them, so they line up.
enum Layout { static let top: CGFloat = 28, button: CGFloat = 64 }

/// The website's design tokens (its :root block), so the window and the site are one look.
enum Site {
    static func hex(_ h: UInt32) -> Color { Color(red: Double((h >> 16) & 255) / 255, green: Double((h >> 8) & 255) / 255, blue: Double(h & 255) / 255) }
    static let bg = Color.black, surface = hex(0x1A1A1A), surface2 = hex(0x232323), line = hex(0x2A2A2A)
    static let head = Color.white, body = hex(0xEEEEEE), low = hex(0xD0D1D2), muted = hex(0x8E8E8E), hazard = hex(0xED4E3B)
    enum Weight { case regular, medium, semibold }
    /// Graphik, the site's face (it ships with macOS as a downloadable system font); Helvetica Neue if it's absent.
    /// The user's text size for the window (View ▸ Bigger Text / Smaller Text): every size is multiplied by it.
    static var scale: CGFloat = {
        if !UserDefaults.standard.bool(forKey: "desktopTextBase090") {      // the standard size moved: start everyone from it, at Default
            UserDefaults.standard.set(true, forKey: "desktopTextBase090"); UserDefaults.standard.removeObject(forKey: "desktopTextScale")
        }
        let s = UserDefaults.standard.double(forKey: "desktopTextScale"); return s >= 0.8 && s <= 1.6 ? CGFloat(s) : 1
    }() { didSet { UserDefaults.standard.set(Double(scale), forKey: "desktopTextScale") } }
    /// The standard text size, as a multiple of the sizes written in this file. 0.9 since 0.18.36 (two steps down from 1.08).
    static let standard: CGFloat = 0.9                      // "Default" in Settings ▸ Text size; 0.18.43 made the size he had chosen (one step under 1.0) the Default
    static func font(_ base: CGFloat, _ w: Weight = .regular) -> Font {
        let size = (base * Site.standard * scale).rounded()
        let name = ["Graphik-Regular", "Graphik-Medium", "Graphik-Semibold"][w == .regular ? 0 : w == .medium ? 1 : 2]
        if NSFont(name: name, size: size) != nil { return .custom(name, size: size) }
        let fallback = ["HelveticaNeue", "HelveticaNeue-Medium", "HelveticaNeue-Bold"][w == .regular ? 0 : w == .medium ? 1 : 2]
        return .custom(fallback, size: size)
    }
}

/// The logo (final, 2026-11-14): a white ring, closed, round a large white dot, on a near-black tile with rounded
/// corners. Drawn, not scaled from a bitmap, so it is sharp at every size. `t` plays its opening: 0 = the ring
/// still in four pieces round a small dot, 1 = the finished logo. `grid`: leave the margin macOS app icons have.
func siteLogo(_ side: CGFloat, t: CGFloat = 1, grid: Bool = false) -> NSImage {
    NSImage(size: NSSize(width: side, height: side), flipped: false) { r in
        let tile = grid ? r.insetBy(dx: side * 100 / 1024, dy: side * 100 / 1024) : r, u = tile.width
        let shape = NSBezierPath(roundedRect: tile, xRadius: u * 185 / 824, yRadius: u * 185 / 824)
        NSGradient(starting: NSColor(white: 0.17, alpha: 1), ending: NSColor(white: 0.06, alpha: 1))?.draw(in: shape, angle: -90)
        NSColor(white: 1, alpha: 0.10).setStroke(); shape.lineWidth = max(0.5, side / 340); shape.stroke()
        let e = min(max(t, 0), 1), k = e * e * (3 - 2 * e), c = NSPoint(x: tile.midX, y: tile.midY)
        let radius = u * 0.256, gap = 26 * (1 - k)                                    // measured from the artwork
        let ring = NSBezierPath(); ring.lineWidth = u * 0.0615
        if gap < 0.5 { ring.appendOval(in: NSRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)) }
        else { for q in 0..<4 { let a0 = CGFloat(q) * 90 + gap / 2
            ring.move(to: NSPoint(x: c.x + radius * cos(a0 * .pi / 180), y: c.y + radius * sin(a0 * .pi / 180)))
            ring.appendArc(withCenter: c, radius: radius, startAngle: a0, endAngle: a0 + 90 - gap) } }
        NSColor.white.setStroke(); ring.stroke()
        let dot = u * (0.07 + 0.05 * k)
        NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: c.x - dot, y: c.y - dot, width: dot * 2, height: dot * 2)).fill()
        return true
    }
}

/// The logo in the window's corner: it plays its opening once each time the window appears, then rests.
struct LogoView: View {
    let side: CGFloat
    @State private var t: CGFloat = 0
    @State private var timer: Timer?
    var body: some View {
        Image(nsImage: siteLogo(side * 2, t: t)).resizable().interpolation(.high).frame(width: side, height: side)
            .onTapGesture { play() }                                   // click the logo: it plays again
            .onAppear { play() }
            .onDisappear { timer?.invalidate() }
    }
    func play() {
        do {
                guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { t = 1; return }
                t = 0; let began = Date()
                let tm = Timer(timeInterval: 1.0 / 60, repeats: true) { tm in
                    let x = CGFloat(Date().timeIntervalSince(began) - 0.25) / 0.7        // a beat, then 0.7 s
                    t = min(max(x, 0), 1); if x >= 1 { tm.invalidate() }
                }
                timer?.invalidate(); RunLoop.main.add(tm, forMode: .common); timer = tm
        }
    }
}

/// ★★★★★ × PARADOX — the exact lockup the website's header uses.
let brandLockup: NSImage? = {
    let svg = #"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="420 488 1080 112" fill="#ffffff" aria-hidden="true" aria-label="★★★★★ × PARADOX"><defs><path id="font_2_722" d="M.5 .8593445 .3829956 .49899293H.01399231L.31098939 .2757721 .19699097-.078567508 .5 .14064026 .8019867-.078567508 .68899539 .2757721 .9850006 .49899293H.6159973L.5 .8593445Z"/><path id="font_4_1" d="M.07998657 .13085938 .23399353 .28585816 .3880005 .13085938 .43598939 .17884827 .28199769 .33285523 .43598939 .48684693 .3880005 .5348511 .23399353 .3798523 .07998657 .5348511 .032989503 .48684693 .18699646 .33285523 .032989503 .17884827 .07998657 .13085938Z"/><path id="font_6_8" d="M.04899597 0H.24398804V.0019989014C.21099854 .0640564 .20399475 .098098758 .20399475 .18118286V.30030824H.269989C.46499635 .30030824 .56799319 .3973236 .56799319 .530365 .56799319 .63739016 .5029907 .7324219 .2849884 .7324219H.04899597V.7304077C.08099365 .66841128 .08898926 .6343994 .08898926 .55137637V.18118286C.08898926 .099090579 .08099365 .0640564 .04899597 .0019989014V0M.2679901 .7124176C.36999513 .7124176 .45199586 .6734009 .45199586 .5283661 .45199586 .42134095 .39898683 .3203125 .2659912 .3203125H.20399475V.7104187C.23599243 .7124176 .2539978 .7124176 .2679901 .7124176Z"/><path id="font_6_26" d="M.3789978 .29589845H.1599884L.269989 .5851135 .3789978 .29589845M.1329956 .0019989014C.11199951 .034973146 .085998538 .10295105 .1309967 .21990967L.1519928 .27589417H.3869934L.42799378 .16792298C.45599366 .09396362 .45599366 .030975342 .43899537 .0019989014V0H.6380005V.0019989014C.6029968 .037979127 .5799866 .07595825 .5469971 .16293335L.32798768 .7402344H.30799867L.09298706 .17393494C.06399536 .096954349 .04598999 .051971437-.0020141602 .0019989014V0H.1329956V.0019989014Z"/><path id="font_6_9" d="M.28199769 .7124176C.4039917 .7124176 .43998719 .64933779 .43998719 .5582428 .43998719 .46012879 .4079895 .37304688 .28199769 .37304688H.20399475V.7114105C.24299622 .7124176 .2689972 .7124176 .28199769 .7124176M.04899597 0H.24398804V.0019989014C.21099854 .06399536 .20399475 .0980072 .20399475 .18101502V.3530426H.29100038L.47099305 0H.6469879V.0069885256C.59498599 .032989503 .57398989 .054992677 .5309906 .13900757L.4119873 .3720398C.5119934 .404068 .5569916 .4741516 .5569916 .5572357 .5569916 .6623535 .4850006 .7324219 .3039856 .7324219H.04899597V.7304077C.08099365 .6683655 .08898926 .6343231 .08898926 .551239V.18101502C.08898926 .09899902 .08099365 .06399536 .04899597 .0019989014V0Z"/><path id="font_6_3" d="M.04899597 0H.32299806C.57899478 0 .72299197 .13204956 .72299197 .36915589 .72299197 .6062622 .57199099 .7363281 .32299806 .7363281 .19099427 .7363281 .17399597 .73231509 .04899597 .73231509V.73031619C.08099365 .67729189 .08898926 .6482849 .08898926 .5782471V.15405274C.08898926 .08403015 .08099365 .055007936 .04899597 .0019989014V0M.31399537 .71632388C.5029907 .71632388 .59599307 .6022644 .59599307 .35514833 .59599307 .13804627 .519989 .024993897 .31498719 .019989014L.20399475 .016998291V.71632388H.31399537Z"/><path id="font_6_7" d="M.4059906-.0146484379C.59399417-.0146484379 .7839966 .1532898 .7839966 .36520387 .7839966 .5771179 .59399417 .7470703 .4059906 .7470703 .21798706 .7470703 .02999878 .5771179 .02999878 .36520387 .02999878 .1532898 .21798706-.0146484379 .4059906-.0146484379M.4059906 .005340576C.23399353 .005340576 .15699768 .1592865 .15699768 .36520387 .15699768 .5711212 .23399353 .72706606 .4059906 .72706606 .57899478 .72706606 .6569977 .5711212 .6569977 .36520387 .6569977 .15827942 .57899478 .005340576 .4059906 .005340576Z"/><path id="font_6_11" d="M.17799378 .0019989014C.1599884 .053024293 .13999939 .095047 .19898987 .18009949L.30999757 .34118653 .43598939 .13206482C.46699525 .08003235 .47200013 .023010254 .45298768 .0019989014V0H.6859894V.0019989014C.6380005 .03100586 .60598757 .074035648 .5669861 .1390686L.3929901 .426239 .49899293 .57533267C.5469971 .6433716 .59199526 .6893921 .6559906 .730423V.7324219H.48599244V.730423C.5119934 .6793823 .5119934 .6333618 .45498658 .5523071L.3809967 .44625855 .28799439 .6003418C.25698854 .65237429 .2519989 .7094116 .2709961 .730423V.7324219H.037994386V.730423C.085998538 .70140078 .11898804 .65737918 .15699768 .5943451L.29699708 .36120606 .15499878 .15708924C.10598755 .08703613 .067993167 .043014528 .0079956059 .0019989014V0H.17799378V.0019989014Z"/></defs><g class="m-stars"><use href="#font_2_722" transform="matrix(100,0,0,-100,430.85,584.9999)"/><use href="#font_2_722" transform="matrix(100,0,0,-100,530.85,584.9999)"/><use href="#font_2_722" transform="matrix(100,0,0,-100,630.85,584.9999)"/><use href="#font_2_722" transform="matrix(100,0,0,-100,730.85,584.9999)"/><use href="#font_2_722" transform="matrix(100,0,0,-100,830.85,584.9999)"/></g><g class="m-x"><use href="#font_4_1" transform="matrix(100,0,0,-100,957.35,584.9999)"/></g><g class="m-word"><use href="#font_6_8" transform="matrix(100,0,0,-100,1027.95,584.9999)"/><use href="#font_6_26" transform="matrix(100,0,0,-100,1078.75,584.9999)"/><use href="#font_6_9" transform="matrix(100,0,0,-100,1142.35,584.9999)"/><use href="#font_6_26" transform="matrix(100,0,0,-100,1205.95,584.9999)"/><use href="#font_6_3" transform="matrix(100,0,0,-100,1269.5499,584.9999)"/><use href="#font_6_7" transform="matrix(100,0,0,-100,1344.85,584.9999)"/><use href="#font_6_11" transform="matrix(100,0,0,-100,1419.75,584.9999)"/></g></svg>
"""#
    return NSImage(data: Data(svg.utf8))
}()

/// What the window shows: nothing but a view onto the Focus engine. `tick` makes the views re-read it.
final class DesktopModel: ObservableObject {
    unowned let f: Focus
    @Published var tick = 0
    @Published var selection: String? = nil                     // nil = the session; otherwise a mode's id
    var still = false                                           // off-screen drawing: no animation
    private var timer: Timer?
    init(_ f: Focus) { self.f = f }

    // — updates —
    /// A newer build than this one, if the release page has one: its version and where to get it.
    @Published var update: (version: String, url: URL)?
    static let releaseAPI = URL(string: "https://api.github.com/repos/Labern/Clean/releases/tags/focus-latest")!
    static let releasePage = URL(string: "https://github.com/Labern/Clean/releases/tag/focus-latest")!
    static func newer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) { let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0; if p != q { return p > q } }
        return false
    }
    /// Asks the release page which version it holds (it sends nothing about this Mac beyond an ordinary web request).
    func checkForUpdate() {
        let mine = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        URLSession.shared.dataTask(with: Self.releaseAPI) { [weak self] data, _, _ in
            guard let data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let body = j["body"] as? String,
                  let r = body.range(of: #"focus-v[0-9]+(\.[0-9]+)+"#, options: .regularExpression) else { return }
            let latest = String(body[r].dropFirst("focus-v".count))
            DispatchQueue.main.async { self?.update = Self.newer(latest, than: mine) ? (latest, Self.releasePage) : nil }
        }.resume()
    }

    static let site = URL(string: "https://paradoxica.co.uk")!

    // — feedback, written here and sent straight to the developer —
    enum FeedbackState: Equatable { case writing, sending, sent, emailed }
    @Published var feedbackShown = false
    @Published var feedbackText = ""
    @Published var feedbackState = FeedbackState.writing
    /// Where feedback is posted. Until the site answers there, the message goes into an email instead.
    static let feedbackEndpoint = URL(string: "https://paradoxica.co.uk/api/feedback")!
    static let feedbackAddress = "labern@paradoxica.co.uk"      // for now; help@paradoxica.co.uk later
    func openFeedback() { feedbackState = .writing; feedbackShown = true }
    func sendFeedback() {
        let text = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty, feedbackState == .writing else { return }
        feedbackState = .sending
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        var req = URLRequest(url: Self.feedbackEndpoint, timeoutInterval: 12); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["app": "Focus", "version": version, "macOS": os, "message": text])
        URLSession.shared.dataTask(with: req) { [weak self] _, resp, _ in
            let ok = (resp as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            DispatchQueue.main.async {
                guard let self else { return }
                if ok { self.feedbackState = .sent; self.feedbackText = ""; return }
                // No answer from the site: put the same message in an email, so nothing written is lost.
                var c = URLComponents(); c.scheme = "mailto"; c.path = Self.feedbackAddress
                c.queryItems = [URLQueryItem(name: "subject", value: "Focus: feedback"), URLQueryItem(name: "body", value: text + "\n\nFocus \(version) · \(os)")]
                if let u = c.url { NSWorkspace.shared.open(u) }
                self.feedbackState = .emailed
            }
        }.resume()
    }

    // — one app, from a right-click —
    func quit(_ id: String, force: Bool) {
        for a in NSWorkspace.shared.runningApplications where a.bundleIdentifier == id && !a.isTerminated { _ = force ? a.forceTerminate() : a.terminate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.refresh() }
    }

    func start() {
        refresh()
        if !still { checkForUpdate() }
        timer?.invalidate()
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common); timer = t
    }
    func stop() { timer?.invalidate(); timer = nil }
    func refresh() { f.mem = memoryByPid(); tick &+= 1 }
    /// Do something to the engine, then show it.
    func act(_ change: () -> Void) { change(); tick &+= 1 }

    // — the engine, read for the views —
    struct AppLine: Identifiable { let id: String, path: String, name: String, usage: String, on: Bool, note: String; var bytes: UInt64 = 0 }
    private var icons: [String: NSImage] = [:]                   // read once per app: redrawing (e.g. while dragging) stays instant
    func icon(_ path: String) -> NSImage {
        if let i = icons[path] { return i }
        let i = NSWorkspace.shared.icon(forFile: path); i.size = NSSize(width: 128, height: 128); icons[path] = i; return i   // the full-size artwork
    }
    var running: [AppLine] {
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let listed = f.sorted(f.apps().compactMap { a in a.bundleIdentifier.flatMap { id in a.bundleURL.map { (id, $0.path) } } })
        let mine = listed.enumerated().sorted { (rank[$0.element.0] ?? 10_000 + $0.offset) < (rank[$1.element.0] ?? 10_000 + $1.offset) }.map(\.element)
        return mine.map { id, p in
            let size = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }.map(f.memory) ?? 0
            let parked = f.focused && f.isParked(id)
            return AppLine(id: id, path: p, name: f.appName(p), usage: size > 0 ? gb(size) : "", on: f.focused ? !parked : f.excluded.contains(id), note: parked ? "leaving…" : "", bytes: size)
        }
    }
    var outside: [AppLine] {
        guard f.focused else { return [] }
        let open = Set(f.apps().compactMap(\.bundleIdentifier))
        return f.parkedEntries.compactMap { e in
            guard let p = e["path"] as? String, let id = (e["id"] as? String) ?? Bundle(path: p)?.bundleIdentifier, !open.contains(id) else { return nil }
            return AppLine(id: id, path: p, name: f.appName(p), usage: "", on: false, note: "")
        }
    }
    var critical: [AppLine] {
        f.neverClose.compactMap { id in f.path(id).map { AppLine(id: id, path: $0, name: f.appName($0), usage: "", on: true, note: "") } }
    }
    struct ModeLine: Identifiable { let id: String, name: String, key: String, apps: [String], live: Bool }
    var modes: [ModeLine] {
        f.modes.compactMap { md in
            guard let id = md["id"] as? String else { return nil }
            return ModeLine(id: id, name: md["name"] as? String ?? "Mode", key: (md["key"] as? Int).map { f.label(forMode: $0) } ?? "",
                            apps: md["apps"] as? [String] ?? [], live: f.focused && f.sessions.first?["modeID"] as? String == id)
        }
    }
    /// Under the button: what pressing it does, in a line.
    var caption: String {
        if f.focused { return "End the session to restore all of your apps as they were." }      // no memory talk once a session is on
        guard !f.hideMode else { return f.sessionCaption() }
        let out = f.leaving(); guard !out.isEmpty else { return f.sessionCaption() }
        return "Closes \(out.count) app\(out.count == 1 ? "" : "s") and saves \(gb(out.reduce(0) { $0 + f.memory($1) })) of RAM. They reopen when the session ends."
    }
    // — the user's own order for the app list (drag a row; it changes nothing but how the list looks) —
    @Published var dragging: String?
    @Published var draggingMode: String?
    var order: [String] {
        get { UserDefaults.standard.stringArray(forKey: "desktopAppOrder") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "desktopAppOrder") }
    }
    func move(_ id: String, before target: String) {
        var ids = running.map(\.id)
        guard id != target, let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target) else { return }
        ids.remove(at: from); ids.insert(id, at: to); order = ids; tick &+= 1
    }
    @Published var modesShown = UserDefaults.standard.object(forKey: "desktopModesShown") as? Bool ?? true {
        didSet { UserDefaults.standard.set(modesShown, forKey: "desktopModesShown") }
    }
    struct PastLine: Identifiable { let id: Int, title: String, detail: String, canSave: Bool, live: Bool }
    var history: [PastLine] {
        let when = DateFormatter(); when.dateStyle = .medium; when.timeStyle = .short; when.doesRelativeDateFormatting = true
        return f.sessions.enumerated().map { n, s in
            let kept = f.keptShort(s), closed = (s["apps"] as? [Any])?.count ?? 0
            let name = (s["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (kept.isEmpty ? "Session" : "Kept " + kept)
            let date = (s["date"] as? Date).map { when.string(from: $0) } ?? ""
            return PastLine(id: n, title: name, detail: [date, kept.isEmpty ? nil : "kept " + kept, "closed \(closed) app\(closed == 1 ? "" : "s")"].compactMap { $0 }.joined(separator: " · "),
                            canSave: !f.kept(s).isEmpty, live: f.focused && n == 0)
        }
    }
    func toggle(_ app: AppLine) {
        act {
            if !f.focused { _ = f.flip(\.excluded, app.id) }
            else if f.isParked(app.id) { f.showMove(app.id, out: false); f.bringBack(app.id) }
            else { f.showMove(app.id, out: true); f.parkNow(app.id) }
        }
    }
    /// A new mode from the ticked apps (or, with nothing ticked, the app in front) — never an empty one.
    func newMode() {
        var ids = f.excluded.filter { f.path($0) != nil }
        if ids.isEmpty, let front = f.apps().first(where: { $0.isActive })?.bundleIdentifier ?? f.apps().first?.bundleIdentifier { ids = [front] }
        guard !ids.isEmpty else { return }
        act { selection = f.createMode("", apps: ids) }
    }
}

// MARK: pieces

struct AppRowView: View {
    let app: DesktopModel.AppLine, icon: NSImage, mark: String, action: (() -> Void)?
    var quit: ((Bool) -> Void)? = nil                           // right-click: Quit / Force Quit this app (running apps only)
    @State private var hover = false
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: 28, height: 28).opacity(app.on ? 1 : 0.55)
            Text(app.name).font(Site.font(18, .medium)).foregroundColor(app.on ? Site.head : Site.muted)
            Spacer(minLength: 12)
            Text(app.note.isEmpty ? app.usage : app.note).font(Site.font(16)).foregroundColor(Site.muted).monospacedDigit()
            Image(systemName: hover && action != nil ? (app.on ? "xmark.circle.fill" : "plus.circle") : mark)
                .font(.system(size: 19)).foregroundColor(app.on ? Site.head : Site.muted).frame(width: 24)
        }
        .padding(.horizontal, 14).frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover && action != nil ? Site.surface : Color.clear))
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: hover).animation(.easeOut(duration: 0.2), value: app.on)
        .onHover { hover = $0 }
        .onTapGesture { action?() }
        .contextMenu {
            if let quit {
                Button("Quit \(app.name)") { quit(false) }
                Button("Force Quit \(app.name)") { quit(true) }
            }
        }
    }
}

/// Dragging one app row over another puts it there.
struct RowDrop: DropDelegate {
    let id: String, m: DesktopModel
    func dropEntered(info: DropInfo) { if let d = m.dragging { withAnimation(.easeOut(duration: 0.15)) { m.move(d, before: id) } } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { m.dragging = nil; return true }
}

/// Dragging one mode over another in the sidebar puts it there (the menu shows the same order).
struct ModeDrop: DropDelegate {
    let id: String, m: DesktopModel
    func dropEntered(info: DropInfo) {                           // instant: the row jumps to its new place, no easing
        guard let d = m.draggingMode, d != id else { return }
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { m.act { m.f.moveMode(d, before: id) } }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { m.draggingMode = nil; return true }
}

/// What the open apps are holding, as one bar: each app a segment as wide as its memory. White = stays in the
/// session, grey = would close. Hover a segment to see whose it is.
struct MemoryBar: View {
    let apps: [DesktopModel.AppLine]
    @State private var hover: String?
    var body: some View {
        let total = max(apps.reduce(0) { $0 + $1.bytes }, 1), freed = apps.filter { !$0.on }.reduce(0) { $0 + $1.bytes }
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                HStack(spacing: 2) {
                    ForEach(apps.filter { $0.bytes > 0 }) { a in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(a.on ? Color.white : Site.hex(0x4A4A4A)).opacity(hover == nil || hover == a.id ? 1 : 0.45)
                            .frame(width: max(3, (g.size.width - CGFloat(apps.count) * 2) * CGFloat(a.bytes) / CGFloat(total)))
                            .onHover { hover = $0 ? a.id : (hover == a.id ? nil : hover) }
                    }
                }.animation(.easeOut(duration: 0.35), value: apps.map(\.on))
            }.frame(height: 10)
            Text(hover.flatMap { id in apps.first { $0.id == id } }.map { "\($0.name) · \($0.usage)" }
                 ?? "\(gb(total)) in use by open apps" + (freed > 0 ? " · a session frees \(gb(freed))" : ""))
                .font(Site.font(15)).foregroundColor(Site.muted)
        }
    }
}

/// The edge the website's Buy square draws: from the top centre, anticlockwise, round all four sides, and 2 points
/// past the start so the ends meet without a seam.
struct DrawnEdge: Shape {
    let radius: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path(), q = radius
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + q, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX, y: r.minY + q), radius: q)
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - q))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX + q, y: r.maxY), radius: q)
        p.addLine(to: CGPoint(x: r.maxX - q, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX, y: r.maxY - q), radius: q)
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + q))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX - q, y: r.minY), radius: q)
        p.addLine(to: CGPoint(x: r.midX - 2, y: r.minY))
        return p
    }
}

/// The point of the app: one press and you're in a session. As wide as the pane, tall, white, its title centred
/// and its key at the right — worded as in the menu.
/// Under the pointer: a touch dimmer, a touch larger, and pressure builds — see PressureDots.
/// Clicked: it sinks, then a white line draws round it the way the website's Buy square does — from the top centre,
/// 2.4 s, quick then settling — anticlockwise when a session begins, clockwise when one ends.
struct SessionButton: View {
    let title: String, key: String, starting: Bool
    var tint = Color.white, tint2 = Color.white, ink = Color.black   // Settings ▸ Appearance's colour (the icon's), and text that reads on it
    let action: () -> Void
    @State private var hover = false
    @State private var trace: CGFloat = 0
    @State private var clockwise = false
    @State private var lineShown = false
    @State private var drawGen = 0
    @State private var pressStart: Date?
    @State private var pressEnd: Date?
    @State private var pressRelease: Date?
    @State private var titleWidth: CGFloat = 200
    static let gap: CGFloat = 6                                   // the drawn line sits this far outside the button
    static var still: (hover: Bool, trace: CGFloat, clockwise: Bool)?   // off-screen renders only: freeze a moment
    var body: some View {
        Button(action: click) {
            ZStack {
                Text(title).font(Site.font(25, .medium)).tracking(-0.4).lineLimit(1)
                    .background(GeometryReader { g in Color.clear.preference(key: TitleWidth.self, value: g.size.width) })
                    .onPreferenceChange(TitleWidth.self) { titleWidth = $0 }
                HStack { Spacer(); Text(key).font(Site.font(18)).opacity(hover ? 0.6 : 0.45).lineLimit(1) }.padding(.trailing, 24)
            }
            .foregroundColor(ink).frame(maxWidth: .infinity).frame(height: Layout.button)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [tint, tint2], startPoint: .leading, endPoint: .trailing)).opacity(hover ? 0.92 : 1)
                    .overlay(Group {
                        if let s = pressStart { PressureDots(ink: ink, titleWidth: titleWidth, start: s, end: pressEnd, release: pressRelease) }
                    }.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)))
            )
            .overlay(
                DrawnEdge(radius: 16 + Self.gap).trim(from: 0, to: trace)
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .scaleEffect(x: clockwise ? -1 : 1, y: 1)          // mirrored about the centre: same start, other way round
                    .opacity(lineShown ? 1 : 0)
                    .padding(-Self.gap).allowsHitTesting(false)
            )
            .scaleEffect(hover ? 1.005 : 1)
            .animation(.easeOut(duration: 0.18), value: hover)
        }
        .buttonStyle(PressStyle())
        .onAppear {
            guard let s = Self.still else { return }
            hover = s.hover; trace = s.trace; clockwise = s.clockwise; lineShown = s.trace > 0
            if s.hover { pressStart = Date().addingTimeInterval(-6) }
        }
        .onHover { on in
            hover = on
            if on { pressStart = Date(); pressEnd = nil; pressRelease = nil }
            else if pressRelease == nil { pressEnd = Date() }
        }
    }

    private func click() {
        pressRelease = Date()                                     // let the pressure go…
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {    // …and, still under the pointer, let it build again
            if hover { pressStart = Date(); pressEnd = nil; pressRelease = nil }
        }
        drawGen += 1; let g = drawGen
        clockwise = !starting; trace = 0; lineShown = true
        withAnimation(.timingCurve(0.5, 0, 0, 0.75, duration: 2.4)) { trace = 1 }     // the website's curve and time
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            guard drawGen == g else { return }
            withAnimation(.easeOut(duration: 0.5)) { lineShown = false }
        }
        action()
    }
}

/// Pressure, under the pointer: thick dark squares slide in from both outer edges along the button's middle and pile
/// up against the title, each new one queuing behind the last; once the pile is full it presses inward in a slow pulse.
/// On the click everything is let go: the squares fly back out and fade while the line draws. Leaving without a click,
/// they simply fade.
struct TitleWidth: PreferenceKey {
    static let defaultValue: CGFloat = 200
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct PressureDots: View {
    let ink: Color, titleWidth: CGFloat
    let start: Date, end: Date?, release: Date?
    static let side: CGFloat = 9, step: CGFloat = 15, every = 0.26, travel = 0.5, perSide = 8
    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { c, size in
                let now = tl.date
                let built = (release ?? now).timeIntervalSince(start)            // how far the build got (frozen at the click)
                let gone = release.map { now.timeIntervalSince($0) / 0.45 } ?? 0  // 0…1 after the click
                let fade = end.map { 1 - now.timeIntervalSince($0) / 0.25 } ?? 1  // leaving without a click
                guard gone < 1, fade > 0, built > 0 else { return }
                let midX = size.width / 2, y = size.height / 2, s = Self.side
                let innerL = midX - titleWidth / 2 - 20, innerR = midX + titleWidth / 2 + 20
                let edgeL: CGFloat = 16, edgeR = size.width - 92                   // the key sits at the right edge
                let room = Int(min(innerL - edgeL, edgeR - innerR) / Self.step)            // the same count both sides
                let count = max(0, min(Self.perSide, room))
                let full = built > Double(count) * Self.every + Self.travel
                let squeeze = full ? CGFloat(sin(now.timeIntervalSinceReferenceDate * 3)) * 1.6 : 0
                for k in 0..<count {
                    let born = Double(k) * Self.every
                    guard built > born else { break }
                    var p = min(1, (built - born) / Self.travel); p = 1 - pow(1 - p, 3)        // ease out: arrives and settles
                    for left in [true, false] {
                        let slot = left ? innerL - CGFloat(k) * Self.step : innerR + CGFloat(k) * Self.step
                        let from = left ? edgeL : edgeR
                        var x = from + (slot - from) * CGFloat(p)
                        x += (left ? 1 : -1) * squeeze * CGFloat(count - k) / CGFloat(max(count, 1))   // the pile presses in
                        x += (left ? -1 : 1) * CGFloat(gone * gone) * 260                                   // let go
                        let a = (1 - gone) * fade * (0.55 + 0.45 * Double(p))
                        let r = CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)
                        c.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(ink.opacity(a)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Pressing: the button sinks a little and dims, the way a physical key gives.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.975 : 1).brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// A slow white pulse: a session is running.
struct PulseDot: View {
    @State private var on = false
    var body: some View {
        Circle().fill(Color.white).frame(width: 8, height: 8).opacity(on ? 1 : 0.35)
            .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { on = true } }
    }
}

/// A plain text box in the window's own face. (SwiftUI's TextEditor fell back to the system font for typed text.)
struct SiteEditor: NSViewRepresentable {
    @Binding var text: String
    let size: CGFloat
    static func nsFont(_ base: CGFloat) -> NSFont {
        let s = (base * Site.standard * Site.scale).rounded()
        return NSFont(name: "Graphik-Regular", size: s) ?? NSFont(name: "HelveticaNeue", size: s) ?? .systemFont(ofSize: s)
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView(), tv = scroll.documentView as! NSTextView
        scroll.drawsBackground = false; scroll.hasVerticalScroller = false; scroll.scrollerStyle = .overlay
        tv.drawsBackground = false; tv.isRichText = false; tv.allowsUndo = true
        tv.font = Self.nsFont(size); tv.textColor = .white; tv.insertionPointColor = .white
        tv.typingAttributes = [.font: Self.nsFont(size), .foregroundColor: NSColor.white]
        tv.textContainerInset = NSSize(width: 0, height: 0); tv.delegate = context.coordinator; tv.string = text
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
        tv.font = Self.nsFont(size)
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: SiteEditor
        init(_ p: SiteEditor) { parent = p }
        func textDidChange(_ n: Notification) { if let tv = n.object as? NSTextView { parent.text = tv.string } }
    }
}

/// Send feedback: written in the app and sent from it. A card over the dimmed window.
struct FeedbackCard: View {
    @ObservedObject var m: DesktopModel
    var body: some View {
        ZStack {
            Color.black.opacity(0.6).onTapGesture { m.feedbackShown = false }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Send feedback").font(Site.font(28, .medium)).tracking(-0.4).foregroundColor(Site.head)
                    Spacer()
                    Button { m.feedbackShown = false } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .medium)).foregroundColor(Site.low).frame(width: 28, height: 28).contentShape(Rectangle()) }.buttonStyle(.plain)
                }
                switch m.feedbackState {
                case .sent:
                    Text("Sent. Thank you.").font(Site.font(19)).foregroundColor(Site.low).padding(.vertical, 18)
                    HStack { Spacer(); SiteButton("Close") { m.feedbackShown = false } }
                case .emailed:
                    Text("Focus couldn't send it directly, so your message is in a new email to \(DesktopModel.feedbackAddress). Send that and it will reach us.")
                        .font(Site.font(19)).foregroundColor(Site.low).fixedSize(horizontal: false, vertical: true).padding(.vertical, 12)
                    HStack { Spacer(); SiteButton("Close") { m.feedbackShown = false } }
                default:
                    Text("Report a bug, suggest an idea, or share what's working well.").font(Site.font(19)).foregroundColor(Site.low)
                    ZStack(alignment: .topLeading) {
                        SiteEditor(text: $m.feedbackText, size: 19).padding(8)
                        if m.feedbackText.isEmpty {
                            Text("“The Dock icon stayed after I closed the window.”").font(Site.font(19)).foregroundColor(Site.muted).padding(.horizontal, 13).padding(.vertical, 8).allowsHitTesting(false)
                        }
                    }
                    .frame(height: 130)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Site.bg))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Site.line, lineWidth: 1))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Site.hex(0x4A4A4A), lineWidth: 1))
                    Text("This sends your message, the Focus version and your macOS version. Nothing else.")
                        .font(Site.font(16)).foregroundColor(Site.muted).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Spacer()
                        SiteButton("Cancel") { m.feedbackShown = false }
                        Button { m.sendFeedback() } label: {
                            Text(m.feedbackState == .sending ? "Sending…" : "Send").font(Site.font(18, .medium)).foregroundColor(.black)
                                .padding(.horizontal, 22).frame(height: 32)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white))
                        }.buttonStyle(.plain)
                        .opacity(m.feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || m.feedbackState == .sending ? 0.35 : 1)
                    }
                }
            }
            .padding(24).frame(width: 520)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Site.bg))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
        }
    }
}

/// A small labelled button for the foot of the sidebar (Help, Manual).
struct FootButton: View {
    let symbol: String, title: String, enabled: Bool, action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) { Image(systemName: symbol).font(.system(size: 13)); Text(title).font(Site.font(15, .medium)).lineLimit(1).minimumScaleFactor(0.8) }
                .foregroundColor(enabled ? Site.head : Site.muted)
                .frame(maxWidth: .infinity).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hover && enabled ? Site.surface2 : Site.surface))
        }
        .buttonStyle(.plain).onHover { hover = $0 }
    }
}

/// The line under a panel's name: white, full width — the panel's one strong rule.
struct PanelRule: View {
    var body: some View { Rectangle().fill(Color.white).frame(height: 1).frame(maxWidth: .infinity).padding(.top, 10).padding(.bottom, 12) }
}

/// Right-click on a mode, wherever it's listed: start or end it, edit it, give it a key, delete it.
struct ModeMenu: View {
    @ObservedObject var m: DesktopModel
    let mode: DesktopModel.ModeLine
    var body: some View {
        Button(mode.live ? "End \(mode.name)" : "Start \(mode.name)") { m.act { m.f.startOrSwitch(mode.id) } }
        Button("Edit…") { m.selection = mode.id }
        Menu("Shortcut") {
            Button("None") { m.act { m.f.setModeKey(mode.id, nil) } }
            ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9, 0], id: \.self) { d in Button(m.f.label(forMode: d)) { m.act { m.f.setModeKey(mode.id, d) } } }
        }
        Divider()
        Button("Delete \(mode.name)", role: .destructive) { m.act { m.f.removeMode(mode.id); if m.selection == mode.id { m.selection = nil } } }
    }
}

/// The line of explanation under a section's name, as the menu has.
struct Note: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View { Text(text).font(Site.font(16)).foregroundColor(Site.low).fixedSize(horizontal: false, vertical: true).padding(.bottom, 4) }
}

struct SectionLabel: View {
    let left: String, right: String, divider: Bool
    init(_ left: String, _ right: String = "", divider: Bool = true) { self.left = left; self.right = right; self.divider = divider }
    var body: some View {
        VStack(spacing: 0) {
            if divider { Rectangle().fill(Site.line).frame(height: 1).padding(.horizontal, 14).padding(.top, 14) }   // a quiet line between sub-sections
            sectionRow
        }
    }
    var sectionRow: some View {
        HStack { Text(left); Spacer(); Text(right).padding(.trailing, 38) }
            .font(Site.font(16, .medium)).foregroundColor(Site.muted).padding(.horizontal, 14).padding(.top, 18).padding(.bottom, 6)
    }
}

/// A quiet outlined button for the lesser actions.
struct SiteButton: View {
    let title: String, tint: Color, action: () -> Void
    init(_ title: String, tint: Color = Site.head, action: @escaping () -> Void) { self.title = title; self.tint = tint; self.action = action }
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Text(title).font(Site.font(16, .medium)).foregroundColor(tint).lineLimit(1).fixedSize()
                .padding(.horizontal, 14).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hover ? Site.surface : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Site.line, lineWidth: 1))
        }
        .buttonStyle(.plain).onHover { hover = $0 }
    }
}

struct SideRow: View {
    let title: String, trailing: String, live: Bool, selected: Bool, icons: [NSImage], symbol: String?, action: () -> Void
    var hint: String? = nil                                      // under the pointer, said at the right instead of `trailing`
    var state: Bool? = nil                                       // a switch at the right: white "On", or outlined "Off"
    @State private var hover = false
    var body: some View {
        HStack(spacing: 10) {
            if let symbol { Image(systemName: symbol).font(.system(size: 14)).frame(width: 22) }
            else {
                ZStack(alignment: .leading) {
                    ForEach(Array(icons.prefix(3).enumerated().reversed()), id: \.offset) { i, im in
                        Image(nsImage: im).resizable().interpolation(.high).frame(width: 20, height: 20).offset(x: CGFloat(i) * 9)
                    }
                }.frame(width: 40, alignment: .leading)
            }
            Text(title).font(Site.font(18, selected ? .medium : .regular)).lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: 6)
            if live && state == nil { Text("On").font(Site.font(14, .medium)).foregroundColor(.black).padding(.horizontal, 7).frame(height: 18).background(Capsule().fill(Color.white)) }
            if hover, let hint, state != nil { Text(hint).font(Site.font(15)).foregroundColor(Site.head) }
            if let on = state {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .circular).fill(on ? Color.white : Color.black)
                    RoundedRectangle(cornerRadius: 10, style: .circular).strokeBorder(Color.white, lineWidth: 1.2)
                    Text(on ? "On" : "Off").font(Site.font(14, .medium)).foregroundColor(on ? .black : .white)
                }.frame(width: 38, height: 20).compositingGroup()
            } else { Text(hover && hint != nil ? hint! : trailing).font(Site.font(15)).foregroundColor(live || (hover && hint != nil) ? Site.head : Site.muted) }
        }
        .foregroundColor(selected || live ? Site.head : Site.low)
        .padding(.horizontal, 12).frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? Site.surface2 : hover || live ? Site.surface : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(live ? 0.85 : 0), lineWidth: 1))   // in use: outlined in white
        .contentShape(Rectangle()).onHover { hover = $0 }.onTapGesture(perform: action)
    }
}

// MARK: the window's content

struct DesktopView: View {
    @ObservedObject var m: DesktopModel
    /// Settings ▸ Appearance ▸ Width: Default (the page fills the window), Narrow (equal space either side), or Space
    /// (an empty column on the right, kept for later). Off-screen renders can pick one with `trial=none|narrow|right`.
    enum Trial: Int { case none = 0, narrow = 1, right = 2 }
    static var renderTrial: Trial?
    static var trial: Trial { renderTrial ?? Trial(rawValue: UserDefaults.standard.integer(forKey: "desktopWidth")) ?? .none }
    /// Room kept beside the page column: an empty right sidebar (as wide as the left one), or equal margins either side.
    var pageInsets: (lead: CGFloat, trail: CGFloat) {
        switch Self.trial { case .none: return (0, 0); case .right: return (0, 292); case .narrow: return (36, 36) }
    }
    var body: some View {
        let _ = m.tick
        VStack(spacing: 0) {
            // The top row, across the whole window: the logo, and the one action. Shown on every page.
            HStack(alignment: .top, spacing: 0) {
                HStack(spacing: 12) {
                    if m.still { Image(nsImage: siteLogo(160)).resizable().interpolation(.high).frame(width: Layout.button, height: Layout.button) } else { LogoView(side: Layout.button) }
                    Text("Focus").font(Site.font(38, .medium)).tracking(-0.8).foregroundColor(Site.head)
                }.padding(.leading, 16).frame(width: 292, alignment: .leading)
                VStack(spacing: 9) {
                    let look = buttonColours
                    SessionButton(title: m.f.focused ? "End Session" : "Start New Session", key: sessionKey, starting: !m.f.focused,
                                  tint: look.0, tint2: look.1, ink: look.2) { m.act { m.f.toggle() } }
                    Text(m.caption).font(Site.font(17)).foregroundColor(Site.low).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }.padding(.horizontal, 28).padding(.leading, pageInsets.lead).padding(.trailing, pageInsets.trail)
            }
            .padding(.top, Layout.top).padding(.bottom, 26)                 // the top row stands apart from everything below
            // Below it, the sidebar and the page start on the same line.
            HStack(alignment: .top, spacing: 0) {
                sidebar.frame(width: 292)
                Group {
                    if m.selection == Page.shortcuts { ShortcutsPage(m: m) }
                    else if m.selection == Page.tools { ToolsPage(m: m) }
                    else if m.selection == Page.settings { SettingsPage(m: m) }
                    else if let id = m.selection, let mode = m.modes.first(where: { $0.id == id }) { ModeDetail(m: m, mode: mode).id(mode.id + "\u{1F}" + mode.name) }
                    else if m.selection == Page.history { HistoryPage(m: m) }
                    else if m.selection == Page.manual { ManualPage() }
                    else { SessionDetail(m: m) }
                }
                .id(m.selection ?? "session").transition(.opacity)
                .animation(.easeOut(duration: 0.16), value: m.selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.leading, pageInsets.lead).padding(.trailing, pageInsets.trail)
            }
        }
        .background(Site.bg).preferredColorScheme(.dark)
        .overlay(alignment: .trailing) {                           // trial only: where the right sidebar would start
            if Self.trial == .right { Rectangle().fill(Site.line).frame(width: 1).padding(.trailing, 292).padding(.vertical, 20) }
        }
        .overlay { if m.feedbackShown { FeedbackCard(m: m).transition(.opacity) } }
        .animation(.easeOut(duration: 0.15), value: m.feedbackShown)
    }
    /// The big button wears the colour chosen in Settings ▸ Appearance (the icon's ring, then its dot), white when none is.
    /// Its text is black on light colours and white on dark ones.
    var buttonColours: (Color, Color, Color) {
        let a = hexColor(m.f.iconColor) ?? .white, b = hexColor(m.f.iconColor2) ?? a
        func light(_ c: NSColor) -> Bool { let s = c.usingColorSpace(.sRGB) ?? c; return 0.2126 * s.redComponent + 0.7152 * s.greenComponent + 0.0722 * s.blueComponent > 0.55 }
        return (Color(nsColor: a), Color(nsColor: b), light(a) || light(b) ? .black : .white)
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 2) {
                SideRow(title: "Session Editor", trailing: "", live: m.f.focused && !m.modes.contains { $0.live }, selected: m.selection == nil, icons: [], symbol: "circle.grid.2x2",
                        action: { if m.selection == nil { m.act { m.f.toggle() } } else { m.selection = nil } },
                        hint: m.selection != nil ? "Open" : m.f.focused ? "Click to end" : "Click to start", state: m.f.focused)
                SideRow(title: "Shortcuts", trailing: "", live: false, selected: m.selection == Page.shortcuts, icons: [], symbol: "keyboard") { m.selection = Page.shortcuts }
                SideRow(title: "Tools", trailing: "", live: false, selected: m.selection == Page.tools, icons: [], symbol: "wrench.and.screwdriver") { m.selection = Page.tools }
                SideRow(title: "History", trailing: m.f.sessions.isEmpty ? "" : "\(m.f.sessions.count)", live: false, selected: m.selection == Page.history, icons: [], symbol: "clock.arrow.circlepath") { m.selection = Page.history }
                SideRow(title: "Settings", trailing: "", live: false, selected: m.selection == Page.settings, icons: [], symbol: "gearshape") { m.selection = Page.settings }
            }.padding(.horizontal, 10)
            Button { withAnimation(.easeOut(duration: 0.15)) { m.modesShown.toggle() } } label: {
                HStack(spacing: 5) {
                    Text("Modes").font(Site.font(16, .medium))
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).rotationEffect(.degrees(m.modesShown ? 90 : 0)).offset(y: 1.5)   // on the text's middle line
                    Spacer()
                }.foregroundColor(Site.muted).padding(.leading, 22).padding(.trailing, 14).padding(.top, 14).padding(.bottom, 5).contentShape(Rectangle())
            }.buttonStyle(.plain).help(m.modesShown ? "Hide your modes" : "Show your modes")
            if m.modesShown {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(m.modes) { mode in
                            SideRow(title: mode.name, trailing: mode.key, live: mode.live, selected: m.selection == mode.id,
                                    icons: mode.apps.compactMap { m.f.path($0) }.map(m.icon), symbol: nil) { m.selection = mode.id }
                                .onDrag { m.draggingMode = mode.id; return NSItemProvider(object: mode.id as NSString) }
                                .onDrop(of: [UTType.text], delegate: ModeDrop(id: mode.id, m: m))
                                .contextMenu { ModeMenu(m: m, mode: mode) }
                        }
                        SideRow(title: "Create New Mode", trailing: "", live: false, selected: false, icons: [], symbol: "plus.circle") { m.newMode() }
                    }.padding(.horizontal, 10)
                }
            }
            Spacer(minLength: 8)
            // The foot: an update when there is one; Help and the Manual; then the maker's mark, which opens the site.
            VStack(spacing: 8) {
                if let u = m.update {
                    Button { NSWorkspace.shared.open(u.url) } label: {
                        HStack(spacing: 7) { Image(systemName: "arrow.down.circle.fill").font(.system(size: 15)); Text("Update available").font(Site.font(15, .medium)) }
                            .foregroundColor(.black).frame(maxWidth: .infinity).frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white))
                    }.buttonStyle(.plain).help("Focus \(u.version) is available. Click to get it.")
                }
                HStack(spacing: 6) {                                  // one row, the sidebar's width, equal parts
                    FootButton(symbol: "bubble.left", title: "Feedback", enabled: true) { m.openFeedback() }
                        .help("Report a bug, suggest an idea, or say what's working well")
                    FootButton(symbol: "book", title: "Manual", enabled: true) { m.selection = Page.manual }
                        .help("How Focus works")
                }
                Button { NSWorkspace.shared.open(DesktopModel.site) } label: {
                    HStack(alignment: .top, spacing: 3) {
                        if let b = brandLockup { Image(nsImage: b).resizable().interpolation(.high).frame(width: 196, height: 196 * 112.0 / 1080.0) }
                        else { Text("★★★★★ × PARADOX").font(Site.font(15)).foregroundColor(Site.head) }
                        Text("™").font(Site.font(8, .medium)).foregroundColor(Site.head).offset(x: -3, y: 2)
                    }.fixedSize().frame(maxWidth: .infinity).padding(.top, 12).padding(.bottom, 2).contentShape(Rectangle())
                }.buttonStyle(.plain).help("paradoxica.co.uk")
            }.padding(.horizontal, 12).padding(.bottom, 24)
        }
    }
}

/// The session: every open app with its memory and whether it's in the session, the apps outside it, the apps
/// that are never quit, and the one button — exactly what the menu shows.
struct SessionDetail: View {
    @ObservedObject var m: DesktopModel
    var body: some View {
        let f = m.f
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Apps in Session").font(Site.font(26, .medium)).tracking(-0.5).foregroundColor(Site.head)   // the menu's own headings
                    PanelRule()
                    Text(f.focused ? "These apps are in your session. Click one to take it out."
                                   : "Tick the apps you want in the session. Everything else closes when the session starts and comes back when it ends.")
                        .font(Site.font(17)).foregroundColor(Site.low).fixedSize(horizontal: false, vertical: true)
                    if !f.focused { MemoryBar(apps: m.running).padding(.top, 12) }      // the memory to be saved is shown before a session, never during one
                    SectionLabel("", "Usage", divider: false).padding(.horizontal, -14)
                    ForEach(m.running) { app in
                        AppRowView(app: app, icon: m.icon(app.path), mark: app.on ? "checkmark.circle.fill" : "circle", action: { m.toggle(app) },
                                   quit: { m.quit(app.id, force: $0) }).padding(.horizontal, -14)
                            .opacity(m.dragging == app.id ? 0.4 : 1)
                            .onDrag { m.dragging = app.id; m.draggingMode = nil; return NSItemProvider(object: app.id as NSString) }
                            .onDrop(of: [UTType.text], delegate: RowDrop(id: app.id, m: m))
                    }
                    if !m.outside.isEmpty {
                        SectionLabel("Apps Outside Session").padding(.horizontal, -14)
                        Note("These apps are not in the session right now. Click one to add it to the session.")
                        ForEach(m.outside) { app in
                            AppRowView(app: app, icon: m.icon(app.path), mark: "circle") { m.toggle(app) }.padding(.horizontal, -14)
                        }
                    }
                    SectionLabel("Critical System Processes — never quit").padding(.horizontal, -14)
                    Note("These apps are never quit or hidden, in any session. Change the list with Add or remove.")
                    ForEach(m.critical) { app in
                        AppRowView(app: app, icon: m.icon(app.path), mark: "lock.circle.fill", action: nil).padding(.horizontal, -14)
                    }
                    SiteButton("Add or remove…") { f.showNever() }.padding(.top, 8)
                    // Modes follow on, as in the menu. Click one to start it; the sidebar's Modes open each in detail.
                    SectionLabel("Modes — frequently used sessions").padding(.horizontal, -14).padding(.top, 8)
                    Note("A mode is a set of apps you keep open. Click one to start it, or press its number. Right-click to edit it.")
                    VStack(spacing: 2) {
                        ForEach(m.modes) { mode in
                            SideRow(title: mode.name, trailing: mode.key, live: mode.live, selected: false,
                                    icons: mode.apps.compactMap { f.path($0) }.map(m.icon), symbol: nil,
                                    action: { if !mode.apps.isEmpty { m.act { f.startOrSwitch(mode.id) } } },
                                    hint: mode.apps.isEmpty ? "Add apps first" : mode.live ? "Click to end" : "Click to start")
                                .contextMenu { ModeMenu(m: m, mode: mode) }
                        }
                        SideRow(title: "Create New Mode", trailing: "", live: false, selected: false, icons: [], symbol: "plus.circle") { m.newMode() }
                    }.padding(.horizontal, -12)
                }
                .padding(.horizontal, 28).padding(.top, 0).padding(.bottom, 30)
            }
        }
    }
}

/// One mode: its name, its number, the apps it keeps open, and starting it.
struct ModeDetail: View {
    @ObservedObject var m: DesktopModel
    let mode: DesktopModel.ModeLine
    @State private var name = ""
    var body: some View {
        let f = m.f
        let inMode = mode.apps.compactMap { id in f.path(id).map { DesktopModel.AppLine(id: id, path: $0, name: f.appName($0), usage: "", on: true, note: "") } }
        let others = m.running.filter { !mode.apps.contains($0.id) }.map { DesktopModel.AppLine(id: $0.id, path: $0.path, name: $0.name, usage: $0.usage, on: false, note: "") }
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        TextField("Mode name", text: $name, onCommit: { m.act { f.renameMode(mode.id, to: name.trimmingCharacters(in: .whitespacesAndNewlines)) } })
                            .textFieldStyle(.plain).font(Site.font(26, .medium)).foregroundColor(Site.head)
                        Menu {
                            Button("None") { m.act { f.setModeKey(mode.id, nil) } }
                            ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9, 0], id: \.self) { d in Button(f.label(forMode: d)) { m.act { f.setModeKey(mode.id, d) } } }
                        } label: { Text(mode.key.isEmpty ? "No shortcut" : mode.key).font(Site.font(15, .medium)) }
                        .menuStyle(.borderlessButton).fixedSize()
                        if !mode.live {
                            SiteButton(mode.apps.isEmpty ? "Add an app to start" : "Start this session") { if !mode.apps.isEmpty { m.act { f.startOrSwitch(mode.id) } } }
                        }
                    }
                    PanelRule()
                    Text("A mode is a set of apps you keep open. Starting it closes everything else until the session ends.")
                        .font(Site.font(17)).foregroundColor(Site.low).padding(.top, 3).fixedSize(horizontal: false, vertical: true)
                    SectionLabel("Keeps open", divider: false).padding(.horizontal, -14)
                    ForEach(inMode) { app in
                        AppRowView(app: app, icon: m.icon(app.path), mark: "checkmark.circle.fill") { m.act { f.removeApp(app.id, fromMode: mode.id) } }.padding(.horizontal, -14)
                    }
                    if inMode.isEmpty { Text("No apps yet. Add one below.").font(Site.font(16)).foregroundColor(Site.muted).padding(.vertical, 8) }
                    if !others.isEmpty {
                        SectionLabel("Open now — click to add").padding(.horizontal, -14)
                        ForEach(others) { app in
                            AppRowView(app: app, icon: m.icon(app.path), mark: "circle") { m.act { _ = f.addApp(app.id, toMode: mode.id) } }.padding(.horizontal, -14)
                        }
                    }
                    HStack(spacing: 10) {
                        SiteButton("Add App…") { let s = NSMenuItem(); s.representedObject = mode.id; f.addAppToMode(s); m.refresh() }
                        SiteButton("Delete Mode", tint: Site.hazard) { m.act { f.removeMode(mode.id); m.selection = nil } }
                    }.padding(.top, 10)
                }
                .padding(.horizontal, 28).padding(.top, 0).padding(.bottom, 30)
            }
        }
        .onAppear { name = mode.name }
    }
}

// MARK: the other pages — the same settings the menu has, read from and written to the same place

/// Sidebar pages that aren't a mode (a mode's id is a UUID, so these can't collide).
enum Page { static let shortcuts = "§shortcuts", tools = "§tools", settings = "§settings", history = "§history", manual = "§manual" }

struct PageFrame<Content: View>: View {
    let title: String, text: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Site.font(26, .medium)).tracking(-0.5).foregroundColor(Site.head)
                PanelRule()
                if !text.isEmpty { Text(text).font(Site.font(17)).foregroundColor(Site.low).fixedSize(horizontal: false, vertical: true) }
                content
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 28).padding(.top, 0).padding(.bottom, 30)
        }
    }
}

/// One choice out of a few, as a row of pills.
struct Choice: View {
    let options: [String], selected: Int
    var unavailable: Set<Int> = []                              // shown, dimmed, not yet choosable
    let pick: (Int) -> Void
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                Button { if !unavailable.contains(i) { pick(i) } } label: {
                    Text(o).font(Site.font(16, .medium)).foregroundColor(i == selected ? .black : Site.head).lineLimit(1).fixedSize()
                        .padding(.horizontal, 16).frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(i == selected ? Color.white : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(i == selected ? 0 : 0.75), lineWidth: 1))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).opacity(unavailable.contains(i) ? 0.35 : 1)
            }
        }
    }
}

/// Text size: − and + either side of where it is now — "Default", or how many steps (one ⌘+ each) above or below.
/// Clicking the middle goes back to Default. The same steps as ⌘+ and ⌘−.
struct TextSizeStepper: View {
    var body: some View {
        let step = Int(((Site.scale - 1) * 10).rounded())
        HStack(spacing: 8) {
            key("minus", enabled: Site.scale > 0.801) { desktop.smallerText() }.help("Smaller (⌘−)")
            Button { desktop.setScale(1) } label: {
                Text(step == 0 ? "Default" : "Default \(step > 0 ? "+" : "−")\(abs(step))").font(Site.font(16, .medium))
                    .foregroundColor(.black).lineLimit(1).fixedSize().frame(minWidth: 110).frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white)).contentShape(Rectangle())
            }.buttonStyle(.plain).help(step == 0 ? "The standard size" : "Back to Default")
            key("plus", enabled: Site.scale < 1.599) { desktop.biggerText() }.help("Bigger (⌘+)")
        }
    }
    private func key(_ symbol: String, enabled: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundColor(Site.head).frame(width: 44, height: 36)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.75), lineWidth: 1)).contentShape(Rectangle())
        }.buttonStyle(PressStyle()).disabled(!enabled).opacity(enabled ? 1 : 0.35)
    }
}

/// The name of a group of settings: larger than a section label, with room above it.
struct GroupTitle: View {
    let title: String
    init(_ t: String) { title = t }
    var body: some View { Text(title).font(Site.font(22, .medium)).tracking(-0.3).foregroundColor(Site.head).padding(.top, 30).padding(.bottom, 2) }
}

struct SettingLine<Control: View>: View {
    let title: String, note: String
    @ViewBuilder var control: Control
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Site.font(18, .medium)).foregroundColor(Site.head)
                if !note.isEmpty { Text(note).font(Site.font(15)).foregroundColor(Site.muted).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 12)
            control.layoutPriority(1)                               // the choices are never cut short: the note wraps instead
        }
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) { Rectangle().fill(Site.line).frame(height: 1) }
    }
}

struct ShortcutsPage: View {
    @ObservedObject var m: DesktopModel
    var body: some View {
        let f = m.f
        PageFrame(title: "Shortcuts", text: "The keys that start and end a session, open the menu, and start your modes.") {
            SettingLine(title: "Start / End Session", note: f.sessionKeyTaken ? "That combination is taken by another app. Pick another." : "Then F.") {
                Choice(options: modifierChoices.map { $0.label + "F" }, selected: modifierChoices.firstIndex { $0.mods == f.sessionMods } ?? 0) { i in m.act { f.sessionMods = modifierChoices[i].mods } }
            }
            SettingLine(title: "Open the Menu", note: f.menuKeyTaken ? "That combination is taken by another app. Pick another." : "Then E.") {
                Choice(options: modifierChoices.map { $0.label + "E" }, selected: modifierChoices.firstIndex { $0.mods == f.menuMods } ?? 0) { i in m.act { f.menuMods = modifierChoices[i].mods } }
            }
            SettingLine(title: "Modes", note: "This, plus the number you give each mode.") {
                Choice(options: modeModifierChoices.map { $0.label + "1" }, selected: modeModifierChoices.firstIndex { $0.mods == f.modeMods } ?? 0) { i in m.act { f.modeMods = modeModifierChoices[i].mods } }
            }
            SectionLabel("Your modes").padding(.horizontal, -14)
            ForEach(m.modes) { mode in
                HStack {
                    Text(mode.name).font(Site.font(18, .medium)).foregroundColor(Site.head)
                    Spacer()
                    Menu {
                        Button("None") { m.act { f.setModeKey(mode.id, nil) } }
                        ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9, 0], id: \.self) { d in Button(f.label(forMode: d)) { m.act { f.setModeKey(mode.id, d) } } }
                    } label: { Text(mode.key.isEmpty ? "No shortcut" : mode.key).font(Site.font(16, .medium)) }
                    .menuStyle(.borderlessButton).fixedSize()
                }.frame(height: 36)
            }
            if m.modes.isEmpty { Text("No modes yet.").font(Site.font(16)).foregroundColor(Site.muted).padding(.vertical, 6) }
        }
    }
}

/// Past sessions: when, what was kept, how many apps were closed. Any of them can become a mode.
/// The Manual: the maker's own words (written by him, 2026-11-15; typos corrected), set as a page — contents at the
/// top, and figures drawn from the app's own parts so it always matches what's on screen.
struct ManualPage: View {
    enum Figure { case choose, before, after, modes, history, tools, colours, keys }
    enum Block { case heading(String), text(String), bullets([String]), figure(Figure, String), link(String, URL) }
    static let blocks: [Block] = [
        .heading("Start a session"),
        .text("Start a session by choosing which apps you want in it: just click the apps you currently have open. Anything not chosen will be closed — safely, one at a time, making sure all of your data is saved — and you will be left with the apps you chose."),
        .figure(.choose, "Tick the apps that stay, then press Start New Session."),
        .text("You can now get your work done with:"),
        .bullets(["Total focus (the name really is Focus for a reason).", "The most possible RAM.", "The least possible CPU usage."]),
        .text("The moment you're done, or if you temporarily want to do something else, just end the session."),
        .heading("End a session"),
        .text("The beauty of Focus is that whether you use the button (in the menu, and at the top of this window) or the keyboard shortcut (⌘⇧F by default, and yours to change), you can press it and instantly get everything back."),
        .text("All apps will be reopened as they were. Wherever possible, they will be returned to where they were. If an app's defaults do not allow this, it will reopen as if you had opened it yourself."),
        .text("The main advantage is that you don't have to make a mental note of which apps you had open, which files you had open in which app, and so on."),
        .text("For example, if you have 10+ apps open (it happens — you know it), each with several things open in it (writing, projects), all of them will be ready to go. What once looked like this:"),
        .figure(.before, "Before a session: everything open."),
        .text("will temporarily look like this:"),
        .figure(.after, "In a session: only what you chose."),
        .text("And, when you're ready, it will return to its former, gloriously chaotic state."),
        .heading("Modes"),
        .text("Though the core of the app is simplicity — turn these apps off while I work in a few of them, then bring them back again — it is simply too useful not to be able to create and edit common modes."),
        .text("Common examples are:"),
        .bullets(["Research (web browser, writing tool).", "Programming (IDE, Chrome, AI).", "Writing (Word).", "Game development (game engine, web browser)."]),
        .text("And so on. Modes are entirely optional and defined by you. Each is given a simple shortcut (⌘0 and so on), which you can change or ignore as you choose."),
        .figure(.modes, "Modes, each with its own key. Click one, or press its key, to start it."),
        .heading("Snapshots and previous sessions"),
        .text("Each time you start a session, Focus notes the time and the apps involved. If you accidentally lose work or forget what you were doing, you can use this to find out what you were working on."),
        .figure(.history, "History lists your past sessions. Save one as a mode to start it again with a key."),
        .text("If you like, you can allow the app to take a screenshot of the apps you are using when you start a session — it is stored only on this Mac — so that you can see, at a glance, what you were working on."),
        .text("This is particularly useful if you are swapping between different kinds of work and want a visual reminder of what you were doing."),
        .heading("Tools"),
        .text("There is a range of other tools built into Focus."),
        .text("Since the app is about helping both you and your computer focus, there are tools to help you watch the apps you are using and the resources they are taking up: simple links to tools that show RAM and CPU usage, and a way to force quit all apps."),
        .figure(.tools, "Two of the tools, as they appear under Tools."),
        .text("As with sessions, the idea is to save you from having to search for apps and close them one by one, and to let you do it all at once."),
        .heading("Appearance"),
        .text("There is a range of options to change the look and style of the app: play around and see which one you like."),
        .figure(.colours, "The colour you choose in Settings ▸ Appearance colours the menu bar icon and this button."),
        .heading("Menu and app"),
        .text("Focus is primarily a menu tool — it's intended for power users who like to keep their hands on the keyboard and stay in flow. But there is also a fully working app: this window, which you can hide with ⌘H or close with ⌘Q (which does not stop the menu from running). Use one or both, as you like. The menu always runs: that's where the work is done."),
        .figure(.keys, "The keys that matter."),
        .heading("Feedback"),
        .text("If you have any ideas or feedback, please use the Feedback button in this window."),
        .heading("About"),
        .link("paradoxica.co.uk/focus", URL(string: "https://paradoxica.co.uk/focus")!),
        .text("Focus is made by ★★★★★ × PARADOX™."),
        .text("★★★★★ × PARADOX™ is a trademark of PARADOXICA Ltd. Registered in England and Wales, company no. 17145296."),
    ]
    static var sections: [String] { blocks.compactMap { if case .heading(let t) = $0 { return t } else { return nil } } }
    static let up: CGFloat = 1.1                                 // the Manual reads one stop (one ⌘+) larger than the other pages
    static func f(_ base: CGFloat, _ w: Site.Weight = .regular) -> Font { Site.font(base * up, w) }
    static let top = "§manual-top"
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Manual").font(Site.font(26, .medium)).tracking(-0.5).foregroundColor(Site.head).id(Self.top)
                    PanelRule()
                    Text("Focus is a simple app. It solves a genuine problem: what to do when you often have many apps open, but temporarily want only a few. It solves this problem exceptionally well.")
                        .font(Self.f(17)).foregroundColor(Site.low).lineSpacing(4).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 680, alignment: .leading)
                    Contents(titles: Self.sections) { t in withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(t, anchor: .top) } }
                    ForEach(Array(Self.blocks.enumerated()), id: \.offset) { _, b in block(b, proxy) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 28).padding(.bottom, 30)
            }
        }
    }
    @ViewBuilder func block(_ b: Block, _ proxy: ScrollViewProxy) -> some View {
        switch b {
        case .heading(let t):
            HStack(alignment: .firstTextBaseline) {
                Text(t).font(Self.f(22, .medium)).tracking(-0.3).foregroundColor(Site.head)
                Spacer()
                Button { withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(Self.top, anchor: .top) } } label: {
                    Text("Contents ↑").font(Self.f(13)).foregroundColor(Site.muted)
                }.buttonStyle(.plain).help("Back to the contents")
            }.frame(maxWidth: 680).padding(.top, 34).padding(.bottom, 2).id(t)
        case .text(let t):
            Text(t).font(Self.f(17)).foregroundColor(Site.low).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 680, alignment: .leading).padding(.top, 10)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("—").font(Self.f(17)).foregroundColor(Site.muted)
                        Text(i).font(Self.f(17)).foregroundColor(Site.head).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.padding(.top, 10).padding(.leading, 4)
        case .figure(let fig, let caption):
            VStack(alignment: .leading, spacing: 8) {
                ManualFigure(figure: fig).frame(maxWidth: 680)
                Text(caption).font(Self.f(14)).foregroundColor(Site.muted).fixedSize(horizontal: false, vertical: true)
            }.padding(.top, 16).padding(.bottom, 4)
        case .link(let t, let url):
            Button { NSWorkspace.shared.open(url) } label: {
                HStack(spacing: 6) { Text(t).font(Self.f(17, .medium)); Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)) }
                    .foregroundColor(Site.head).underline()
            }.buttonStyle(.plain).padding(.top, 10).help(url.absoluteString)
        }
    }
}

/// The Manual's contents: every section, numbered in reading order; click one to go to it.
struct Contents: View {
    let titles: [String], go: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Contents").font(ManualPage.f(14, .medium)).foregroundColor(Site.muted).padding(.bottom, 8)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 4) {
                ForEach(Array(titles.enumerated()), id: \.offset) { i, t in ContentsLine(number: i + 1, title: t) { go(t) } }
            }
        }
        .padding(16).frame(maxWidth: 680, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Site.line, lineWidth: 1))
        .padding(.top, 18)
    }
}
struct ContentsLine: View {
    let number: Int, title: String, action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("\(number)").font(ManualPage.f(15)).foregroundColor(Site.muted).frame(width: 18, alignment: .trailing).monospacedDigit()
                Text(title).font(ManualPage.f(16, .medium)).foregroundColor(hover ? Site.head : Site.low).underline(hover)
            }.padding(.vertical, 4).contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hover = $0 }
    }
}

/// The Manual's figures: close-ups built from the window's own parts with sample apps that come with every Mac, so a
/// figure always shows what the window shows. Framed and inert — they illustrate, they don't act.
struct ManualFigure: View {
    let figure: ManualPage.Figure
    static func app(_ path: String, _ name: String, _ usage: String, _ on: Bool) -> DesktopModel.AppLine {
        DesktopModel.AppLine(id: path, path: path, name: name, usage: usage, on: on, note: "")
    }
    static func icon(_ path: String) -> NSImage { let i = NSWorkspace.shared.icon(forFile: path); i.size = NSSize(width: 128, height: 128); return i }
    static let safari = "/Applications/Safari.app", notes = "/System/Applications/Notes.app", calendar = "/System/Applications/Calendar.app",
               music = "/System/Applications/Music.app", textEdit = "/System/Applications/TextEdit.app", terminal = "/System/Applications/Utilities/Terminal.app"
    var body: some View {
        Group {
            switch figure {
            case .choose:
                VStack(alignment: .leading, spacing: 10) {
                    SessionButton(title: "Start New Session", key: "⌘⇧F", starting: true) {}
                    VStack(spacing: 0) {
                        ForEach([Self.app(Self.safari, "Safari", "1.2 GB", true), Self.app(Self.notes, "Notes", "310 MB", true),
                                 Self.app(Self.music, "Music", "640 MB", false), Self.app(Self.calendar, "Calendar", "180 MB", false)]) { a in
                            AppRowView(app: a, icon: Self.icon(a.path), mark: a.on ? "checkmark.circle.fill" : "circle", action: nil).padding(.horizontal, -14)
                        }
                    }.padding(.horizontal, 14)
                }
            case .before: DesktopSketch(busy: true)
            case .after: DesktopSketch(busy: false)
            case .modes:
                VStack(spacing: 2) {
                    SideRow(title: "Research", trailing: "⌘1", live: true, selected: false, icons: [Self.safari, Self.notes].map(Self.icon), symbol: nil) {}
                    SideRow(title: "Programming", trailing: "⌘2", live: false, selected: false, icons: [Self.terminal, Self.safari].map(Self.icon), symbol: nil) {}
                    SideRow(title: "Writing", trailing: "⌘3", live: false, selected: false, icons: [Self.textEdit].map(Self.icon), symbol: nil) {}
                }
            case .history:
                HStack(spacing: 12) {
                    DesktopSketch(busy: false).frame(width: 120)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Research").font(Site.font(18, .medium)).foregroundColor(Site.head)
                        Text("Today, 10:42 · Safari, Notes").font(Site.font(15)).foregroundColor(Site.muted)
                    }
                    Spacer(minLength: 10)
                    SiteButton("Save as Mode") {}
                }
            case .tools:
                VStack(spacing: 0) {
                    ToolLine(title: "Open Activity Monitor", why: "See which apps are using the most memory and processor right now.", tint: Site.head, enabled: true) {}
                    ToolLine(title: "Force Quit All Apps…", why: "For apps that have frozen and won't quit. Unsaved work in them is lost, so it asks first.", tint: Site.hazard, enabled: true) {}
                }
            case .colours:
                VStack(spacing: 12) {
                    SessionButton(title: "Start New Session", key: "⌘⇧F", starting: true) {}
                    SessionButton(title: "Start New Session", key: "⌘⇧F", starting: true, tint: Color(red: 0.55, green: 0.36, blue: 0.96),
                                  tint2: Color(red: 0.55, green: 0.36, blue: 0.96), ink: .white) {}
                    SessionButton(title: "Start New Session", key: "⌘⇧F", starting: true, tint: Color(red: 1, green: 0.84, blue: 0.37),
                                  tint2: Color(red: 1, green: 0.53, blue: 1), ink: .black) {}
                }
            case .keys:
                VStack(alignment: .leading, spacing: 10) {
                    KeyLine(keys: ["⌘", "⇧", "F"], says: "Start or end a session, from anywhere")
                    KeyLine(keys: ["⌘", "H"], says: "Hide this window; press again straight away to bring it back")
                    KeyLine(keys: ["⌘", "Q"], says: "Close this window. The menu keeps running")
                    KeyLine(keys: ["⌘", "+"], says: "Bigger text (⌘− for smaller)")
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .allowsHitTesting(false)
        .modifier(FigureFrame(on: figure != .before && figure != .after))    // the desktop drawings carry their own frame
    }
}
struct FigureFrame: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on {
            content.padding(18)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Site.bg))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Site.line, lineWidth: 1))
        } else { content }
    }
}
struct KeyLine: View {
    let keys: [String], says: String
    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                ForEach(keys, id: \.self) { k in
                    Text(k).font(Site.font(16, .medium)).foregroundColor(Site.head).frame(minWidth: 30, minHeight: 30)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Site.surface))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.white.opacity(0.35), lineWidth: 1))
                }
            }.frame(width: 112, alignment: .leading)
            Text(says).font(Site.font(16)).foregroundColor(Site.low)
        }
    }
}

/// A drawing of a Mac's desktop for the Manual: crowded with windows before a session, down to the chosen few in one.
/// (An abstraction of his two screenshots — nothing from anyone's real screen goes into the app.)
struct DesktopSketch: View {
    let busy: Bool
    /// Windows as fractions of the desktop: x, y, width, height. The first three are the ones a session keeps.
    static let windows: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (0.05, 0.07, 0.42, 0.5), (0.53, 0.07, 0.42, 0.5), (0.28, 0.63, 0.44, 0.31),     // the three a session keeps
        (0.17, 0.2, 0.3, 0.42), (0.6, 0.3, 0.3, 0.38), (0.03, 0.56, 0.27, 0.38),
        (0.7, 0.58, 0.27, 0.36), (0.4, 0.03, 0.24, 0.32),
    ]
    var body: some View {
        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            ZStack(alignment: .topLeading) {
                ForEach(Array(Self.windows.enumerated()), id: \.offset) { i, r in
                    if busy || i < 3 {
                        let kept = !busy && i < 3                         // the chosen few only stand out once the rest have gone
                        VStack(alignment: .leading, spacing: H * 0.018) {
                            HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.white.opacity(kept ? 0.55 : 0.25)).frame(width: 4, height: 4) } }
                            ForEach(0..<4, id: \.self) { l in
                                Capsule().fill(Color.white.opacity(kept ? 0.4 : 0.14)).frame(width: r.2 * W * [0.7, 0.85, 0.5, 0.75][l] - 12, height: 3)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(6)
                        .frame(width: r.2 * W, height: r.3 * H, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(kept ? Site.surface2 : Site.surface))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.white.opacity(kept ? 0.85 : 0.18), lineWidth: 1))
                        .offset(x: r.0 * W, y: r.1 * H)
                    }
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Site.bg))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Site.line, lineWidth: 1))
    }
}

struct HistoryPage: View {
    @ObservedObject var m: DesktopModel
    var body: some View {
        let f = m.f
        PageFrame(title: "History", text: "Your past sessions. Save one as a mode to start it again with a key.") {
            if m.history.isEmpty { Text("No sessions yet.").font(Site.font(16)).foregroundColor(Site.muted).padding(.vertical, 10) }
            ForEach(m.history) { s in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) { if s.live { PulseDot() }; Text(s.title).font(Site.font(18, .medium)).foregroundColor(Site.head).lineLimit(1) }
                        Text(s.detail).font(Site.font(15)).foregroundColor(Site.muted).lineLimit(1)
                    }
                    Spacer(minLength: 10)
                    if s.canSave {
                        SiteButton("Save as Mode") { m.act { if f.modeFromSession(s.id, name: s.title) { m.selection = f.modes.last?["id"] as? String } } }
                    }
                }.padding(.vertical, 7)
            }
        }
    }
}

/// The menu bar's own drawing of an icon, rasterised the right way up at 4× (some designs are drawn on a flipped
/// canvas; handed to SwiftUI as they are, those came out upside-down — not the icon the menu bar shows).
func upright(_ g: NSImage) -> NSImage {
    let side: CGFloat = 72
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    g.draw(in: NSRect(x: 0, y: 0, width: side, height: side)); NSGraphicsContext.restoreGraphicsState()
    let out = NSImage(size: NSSize(width: 18, height: 18)); out.addRepresentation(rep); return out
}

/// One menu bar icon design in the picker: at rest, and playing into its in-session state under the pointer.
struct IconCell: View {
    let style: IconStyle, selected: Bool, ring: NSColor, dot: NSColor, pick: () -> Void
    @State private var hover = false
    var body: some View {
        VStack(spacing: 4) {
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !hover)) { tl in
                let p = hover ? tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2) / 2.2 : 0
                let t = p < 0.2 ? 0 : p < 0.45 ? (p - 0.2) / 0.25 : p < 0.75 ? 1 : 1 - (p - 0.75) / 0.25
                Image(nsImage: upright(glyph(CGFloat(t), ring: ring, dot: dot, style: style))).resizable().interpolation(.high).frame(width: 30, height: 30)
            }
            Text(style.name).font(Site.font(13)).foregroundColor(selected ? Site.head : Site.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity).frame(height: 76)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hover || selected ? Site.surface2 : Site.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(selected ? 0.9 : 0), lineWidth: 1.5))
        .contentShape(Rectangle()).onHover { hover = $0 }.onTapGesture(perform: pick)
    }
}

/// One tool: a large button, and beside it why you'd reach for it.
struct ToolLine: View {
    let title: String, why: String, tint: Color, enabled: Bool, action: () -> Void
    @State private var hover = false
    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Button { if enabled { action() } } label: {
                Text(title).font(Site.font(18, .medium)).foregroundColor(tint).lineLimit(1).minimumScaleFactor(0.85)
                    .padding(.horizontal, 16).frame(width: 290, height: 48)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hover && enabled ? Site.surface2 : Site.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Site.line, lineWidth: 1))
            }.buttonStyle(.plain).onHover { hover = $0 }
            Text(why).font(Site.font(16)).foregroundColor(Site.low).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6).opacity(enabled ? 1 : 0.4)
    }
}

struct ToolsPage: View {
    @ObservedObject var m: DesktopModel
    var body: some View {
        let f = m.f, busy = f.focused || f.clearing
        PageFrame(title: "Tools", text: busy ? "End the session first to use the quit tools." : "Look at what your Mac is doing, or clear everything at once.") {
            SectionLabel("Analyse performance", divider: false).padding(.horizontal, -14)
            ToolLine(title: "Open Activity Monitor", why: "See which apps are using the most memory and processor right now.", tint: Site.head, enabled: true) { f.openActivityMonitor() }
            ToolLine(title: "Open System Settings", why: "Change what opens at login, and the battery and display settings that affect how the Mac runs.", tint: Site.head, enabled: true) { f.openSystemSettings() }
            SectionLabel("Quit Unresponsive Apps").padding(.horizontal, -14)
            ToolLine(title: "Quit All Apps…", why: "Close every app at once for a clean start. Each app saves first. Critical System Processes stay open.", tint: Site.head, enabled: !busy) { f.quitAllApps() }
            ToolLine(title: "Quit All Apps & Restart Mac…", why: "Close everything, then restart. Clears memory completely when the Mac feels slow.", tint: Site.head, enabled: !busy) { f.quitAllRestart() }
            ToolLine(title: "Force Quit All Apps…", why: "For apps that have frozen and won't quit. Unsaved work in them is lost, so it asks first.", tint: Site.hazard, enabled: !busy) { f.forceQuitAllApps() }
        }
    }
}

struct SettingsPage: View {
    @ObservedObject var m: DesktopModel
    var body: some View {
        let f = m.f
        PageFrame(title: "Settings", text: "The same settings as the menu. Changing one here changes it there.") {
            GroupTitle("Behaviour")
            SettingLine(title: "App Open/Close Speed", note: "Safety first closes apps one at a time. Speed first does them all at once.") {
                Choice(options: ["Safety first", "Speed first"], selected: f.fastSwitching ? 1 : 0) { i in m.act { f.fastSwitching = i == 1 } }
            }
            SettingLine(title: "Reopen windows as they were", note: "Asks macOS to bring each app's windows back when it reopens.") {
                Choice(options: ["Off", "On"], selected: f.keepWindows ? 1 : 0) { i in m.act { f.keepWindows = i == 1 } }
            }
            SettingLine(title: "Open at login", note: "") {
                Choice(options: ["Off", "On"], selected: SMAppService.mainApp.status == .enabled ? 1 : 0) { i in
                    if (SMAppService.mainApp.status == .enabled) != (i == 1) { m.act { f.login() } }
                }
            }
            GroupTitle("Appearance")
            SettingLine(title: "This window", note: "Dark is the standard look. Light and System are coming.") {
                Choice(options: ["Light", "Dark", "System"], selected: 1, unavailable: [0, 2]) { _ in }
            }
            SettingLine(title: "Menu", note: "The look of the menu bar menu.") {
                Choice(options: ["Dark", "Light"], selected: f.lightMenuSetting ? 1 : 0) { i in m.act { f.lightMenuSetting = i == 1 } }
            }
            SettingLine(title: "Menu headings", note: "How much the menu's headings explain.") {
                Choice(options: ["Minimalist", "Normal", "Verbose"], selected: f.headingStyle) { i in m.act { f.headingStyle = i } }
            }
            SettingLine(title: "Width", note: "Default fills the window. Narrow leaves space either side. Space keeps an empty column on the right.") {
                Choice(options: ["Default", "Narrow", "Space"], selected: DesktopView.trial.rawValue) { i in
                    m.act { UserDefaults.standard.set(i, forKey: "desktopWidth") }
                }
            }
            SettingLine(title: "Text size", note: "For this window. Also ⌘+ and ⌘−.") {
                TextSizeStepper()
            }
            SectionLabel("Menu bar icon — hover to see it enter a session").padding(.horizontal, -14).padding(.top, 10)
            let ring = hexColor(f.iconColor) ?? .white, dot = hexColor(f.iconColor2) ?? ring
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), alignment: .leading, spacing: 8) {
                ForEach(IconStyle.allCases, id: \.rawValue) { st in
                    IconCell(style: st, selected: f.iconStyleSetting == st, ring: ring, dot: dot) { m.act { f.iconStyleSetting = st } }
                }
            }
            SectionLabel("Icon colour").padding(.horizontal, -14).padding(.top, 10)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), alignment: .leading, spacing: 8) {
                let all = [("White", "", "")] + theme.iconPresets + theme.evaPresets
                ForEach(all, id: \.0) { name, a, b in
                    let on = f.iconColor == a && (f.iconColor2 == b || (a == b && f.iconColor2.isEmpty) || (a.isEmpty && f.iconColor2.isEmpty))
                    Button { m.act { f.iconColor = a; f.iconColor2 = a == b ? "" : b } } label: {
                        HStack(spacing: 8) {
                            ZStack { Circle().fill(Color(nsColor: hexColor(a) ?? .white)).frame(width: 16, height: 16)
                                     Circle().fill(Color(nsColor: hexColor(b) ?? hexColor(a) ?? .white)).frame(width: 7, height: 7) }
                            Text(name).font(Site.font(15, on ? .medium : .regular)).foregroundColor(on ? Site.head : Site.low).lineLimit(1).minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                        }.padding(.horizontal, 12).frame(height: 38)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Site.surface2 : Site.surface))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(on ? 0.9 : 0), lineWidth: 1.5))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: the window

/// Owns the desktop window. While it is open Focus is an ordinary app (in the Dock and ⌘⇥, with the site's logo);
/// when it closes Focus goes back to being only its menu bar icon.
/// ⌘H (and ⌘W) put the window away and return Focus to its menu bar icon, as Wispr Flow does. Only while the
/// window is open: Focus takes no such key otherwise.
final class DesktopWindow: NSWindow {
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        if e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, let ch = e.charactersIgnoringModifiers?.lowercased(), ch == "h" || ch == "w" || ch == "q" {
            if ch == "h" { desktop.hideByH() } else { close() }
            return true
        }
        return super.performKeyEquivalent(with: e)
    }
}
final class DesktopController: NSObject, NSWindowDelegate, NSApplicationDelegate {
    /// ⌘Q quits the desktop app, never the menu bar app. Ever. Only the menu's own Quit (or the Mac shutting down or
    /// logging out) ends Focus: any other quit that arrives while the window is open, or from the Q key, closes the
    /// window and is refused.
    var poweringOff = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Focus.quitAsked || poweringOff { return .terminateNow }
        let fromQ = NSApp.currentEvent.map { $0.type == .keyDown && $0.charactersIgnoringModifiers?.lowercased() == "q" } ?? false
        guard shown || fromQ else { return .terminateNow }
        flog("⌘Q / quit while the desktop app was open: closed the window, Focus stays in the menu bar")
        window?.close(); return .terminateCancel
    }
    var window: NSWindow?, model: DesktopModel?
    var shown: Bool { window?.isVisible == true }
    func show(_ f: Focus) {
        if window == nil {
            let m = DesktopModel(f); model = m
            let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 800)
            // A squat rectangle, well inside the screen: no wider or taller than it needs to be.
            let size = NSSize(width: min(1000, screen.width - 120), height: min(730, screen.height - 110))
            let w = DesktopWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden; w.title = "Focus"
            w.backgroundColor = .black; w.appearance = NSAppearance(named: .darkAqua)
            w.isMovableByWindowBackground = false; w.isReleasedWhenClosed = false   // drag the top strip to move it: rows are for dragging apps
            w.minSize = NSSize(width: 720, height: 420)
            let host = NSHostingView(rootView: DesktopView(m: m))
            host.sizingOptions = []                                  // the window sets the size, never the content
            w.contentView = host
            w.setContentSize(size)
            w.setFrame(NSRect(x: screen.midX - w.frame.width / 2, y: screen.midY - w.frame.height / 2, width: w.frame.width, height: w.frame.height), display: false)
            w.delegate = self; window = w
        }
        model?.start()
        NSApp.setActivationPolicy(.regular)                      // now in the Dock and ⌘⇥…
        NSApp.applicationIconImage = siteLogo(512, grid: true)   // …with the site's logo
        NSApp.mainMenu = mainMenu()                              // …and a menu bar of its own
        if NSApp.delegate == nil {
            NSApp.delegate = self
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { [weak self] _ in self?.poweringOff = true }
        }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    func hide() { window?.close() }

    // MARK: the menu bar while the window is open — Focus, File, Edit, View, Window, Help
    func mainMenu() -> NSMenu {
        let bar = NSMenu()
        func menu(_ title: String, _ build: (NSMenu) -> Void) { let i = NSMenuItem(), m = NSMenu(title: title); build(m); i.submenu = m; bar.addItem(i) }
        func item(_ m: NSMenu, _ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command, mine: Bool = true) {
            let i = m.addItem(withTitle: title, action: action, keyEquivalent: key); i.keyEquivalentModifierMask = mods; if mine { i.target = self }
        }
        menu("Focus") { m in
            item(m, "About Focus", #selector(about))
            m.addItem(.separator())
            item(m, "Hide Desktop App", #selector(hideByH), "h")
            item(m, "Quit Desktop App", #selector(closeWindow), "q")             // back to the menu bar: Focus itself keeps running
        }
        menu("File") { m in
            item(m, "New Mode", #selector(newMode), "n")
            item(m, "Close Window", #selector(closeWindow), "w")
        }
        menu("Edit") { m in
            item(m, "Undo", Selector(("undo:")), "z", mine: false); item(m, "Redo", Selector(("redo:")), "z", [.command, .shift], mine: false)
            m.addItem(.separator())
            item(m, "Cut", #selector(NSText.cut(_:)), "x", mine: false); item(m, "Copy", #selector(NSText.copy(_:)), "c", mine: false)
            item(m, "Paste", #selector(NSText.paste(_:)), "v", mine: false); item(m, "Select All", #selector(NSText.selectAll(_:)), "a", mine: false)
        }
        menu("View") { m in
            item(m, "Increase Font Size", #selector(biggerText), "+")
            item(m, "Decrease Font Size", #selector(smallerText), "-")
            item(m, "Actual Size", #selector(actualText))
            let eq = m.addItem(withTitle: "Increase Font Size", action: #selector(biggerText), keyEquivalent: "="); eq.target = self   // ⌘= without Shift
            eq.isHidden = true; eq.allowsKeyEquivalentWhenHidden = true
        }
        menu("Window") { m in
            item(m, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m", mine: false)
            item(m, "Zoom", #selector(NSWindow.performZoom(_:)), mine: false)
        }
        menu("Help") { m in
            item(m, "Send Feedback…", #selector(feedback))
            item(m, "Email Support", #selector(help))
            item(m, "Focus Website", #selector(website))
        }
        return bar
    }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationIcon: siteLogo(256, grid: true), .applicationName: "Focus"]) }
    @objc func closeWindow() { window?.close() }
    /// ⌘H puts the window away. Pressed again straight away, it brings it back: for a few seconds after hiding,
    /// Focus holds ⌘H itself (the window is gone, so the key would otherwise go to whatever app is in front), then
    /// lets it go so ⌘H works normally everywhere else.
    static let reopenWindow: TimeInterval = 4
    var reopenKey: EventHotKeyRef?, reopenTimer: Timer?
    @objc func hideByH() {
        window?.close()
        disarmReopen()
        reopenKey = hotkey(200, kVK_ANSI_H, cmdKey)
        let t = Timer(timeInterval: Self.reopenWindow, repeats: false) { [weak self] _ in self?.disarmReopen() }
        RunLoop.main.add(t, forMode: .common); reopenTimer = t
    }
    func disarmReopen() {
        reopenTimer?.invalidate(); reopenTimer = nil
        if let k = reopenKey { UnregisterEventHotKey(k); reopenKey = nil }
    }
    /// ⌘H arrived while Focus was holding it: the window comes back.
    func reopenFromH() { disarmReopen(); focus.openDesktop() }
    @objc func newMode() { model?.newMode() }
    func setScale(_ s: CGFloat) { Site.scale = min(max((s * 20).rounded() / 20, 0.8), 1.6); model?.tick &+= 1 }
    @objc func biggerText() { setScale(Site.scale + 0.1) }
    @objc func smallerText() { setScale(Site.scale - 0.1) }
    @objc func actualText() { setScale(1) }
    @objc func feedback() { model?.openFeedback() }
    @objc func help() { NSWorkspace.shared.open(Maker.helpURL) }
    @objc func website() { NSWorkspace.shared.open(DesktopModel.site) }
    func windowWillClose(_ n: Notification) {
        model?.stop()
        NSApp.mainMenu = nil
        NSApp.setActivationPolicy(.accessory)                    // back to the menu bar only
    }
}
let desktop = DesktopController()

extension Focus {
    @objc func openDesktop() { guard store == .standard else { return }; desktop.show(self) }
    @objc func toggleDesktop() { if desktop.shown { desktop.hide() } else { openDesktop() } }
}

/// `Focus --render-desktop FILE [mode]`: the window's content drawn off-screen (sample modes, its own settings), to
/// check the design without opening anything.
func renderDesktop(to file: String, mode: Bool) {
    let suite = "com.labern.focus.selftest"
    let f = Focus(store: UserDefaults(suiteName: suite)!)
    f.modes = []
    let have = { (ids: [String]) in ids.filter { f.path($0) != nil } }
    f.createMode("AI", apps: have(["com.apple.Terminal", "com.apple.Safari"]))
    let second = f.createMode("Research", apps: have(["com.apple.Safari", "com.apple.Notes", "com.apple.Preview"]))
    f.createMode("", apps: have(["com.apple.TextEdit"]))
    f.neverClose = have(["com.apple.Terminal"]); f.excluded = have(["com.apple.Safari", "com.apple.Terminal"])
    let m = DesktopModel(f); m.still = true; m.refresh(); if mode { m.selection = second }
    if CommandLine.arguments.contains("feedback") { m.openFeedback() }
    if CommandLine.arguments.contains("live") {
        f.sessions = [["date": Date(), "name": "Research", "mode": "Research", "modeID": second, "kept": have(["com.apple.Safari"]), "apps": [["path": "/System/Applications/Notes.app", "id": "com.apple.Notes"]]]]
        f.store.set(true, forKey: "focused")
    }
    for p in [Page.settings, Page.shortcuts, Page.tools, Page.history, Page.manual] where CommandLine.arguments.contains(String(p.dropFirst())) { m.selection = p }
    if !CommandLine.arguments.contains("live") { f.sessions = [["date": Date().addingTimeInterval(-3600), "kept": have(["com.apple.Safari"]), "apps": [["path": "/System/Applications/Notes.app"]]]] }
    if CommandLine.arguments.contains("hover") { SessionButton.still = (true, 0, false) }
    if let a = CommandLine.arguments.first(where: { $0.hasPrefix("line=") }), let t = Double(a.dropFirst(5)) {
        SessionButton.still = (false, CGFloat(abs(t)), t < 0) }                          // line=-0.3: drawn clockwise
    if let c = CommandLine.arguments.first(where: { $0.hasPrefix("colour=") }) {          // e.g. colour=8B5CF6 or colour=8B5CF6,F472B6
        let p = c.dropFirst(7).split(separator: ","); f.store.set(String(p[0]), forKey: "iconColor"); f.store.set(p.count > 1 ? String(p[1]) : "", forKey: "iconColor2")
    }
    if CommandLine.arguments.contains("trial=none") { DesktopView.renderTrial = DesktopView.Trial.none }
    if CommandLine.arguments.contains("trial=right") { DesktopView.renderTrial = .right }
    if CommandLine.arguments.contains("trial=narrow") { DesktopView.renderTrial = .narrow }
    m.update = ("9.9.9", DesktopModel.releasePage)               // so the Update button's place can be checked
    let size = CommandLine.arguments.contains("wide") ? NSSize(width: 1320, height: 880)
        : NSSize(width: 1000, height: CommandLine.arguments.first { $0.hasPrefix("h=") }.flatMap { Double($0.dropFirst(2)) }.map { CGFloat($0) }
                                       ?? (CommandLine.arguments.contains("tall") ? 1500 : 730))
    let host = NSHostingView(rootView: DesktopView(m: m).frame(width: size.width, height: size.height))
    let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    w.appearance = NSAppearance(named: .darkAqua); w.contentView = host
    host.frame = NSRect(origin: .zero, size: size); host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: file))
    }
    f.modes = []; UserDefaults.standard.removePersistentDomain(forName: suite)
}
