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
/// The options off-screen renders read (`--render-desktop FILE mode live …`): the command line, or what a test sets.
var renderArgs: [String] = CommandLine.arguments
import ServiceManagement
import UniformTypeIdentifiers
import Carbon.HIToolbox

/// The two measurements the top of the window hangs on: the session button and the logo share them, so they line up.
enum Layout { static let top: CGFloat = 28, button: CGFloat = 64 }

/// The website's design tokens (its :root block), so the window and the site are one look.
enum Site {
    static func hex(_ h: UInt32) -> Color { Color(red: Double((h >> 16) & 255) / 255, green: Double((h >> 8) & 255) / 255, blue: Double(h & 255) / 255) }
    /// The window's look: Light, Dark (the standard) or System (follows macOS, live). Settings ▸ Appearance ▸ This
    /// window; renders: `look=light|dark`. Every colour below follows it: the site's white on black, or its exact
    /// inverse, black on white.
    static var look: Int { renderArgs.contains("look=light") ? 0 : renderArgs.contains("look=dark") ? 1 : (UserDefaults.standard.object(forKey: "desktopLook") as? Int ?? 1) }
    static var light: Bool {
        switch look {
        case 0: return true
        case 2: return NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        default: return false
        }
    }
    static func pick(_ dark: UInt32, _ lite: UInt32) -> Color { hex(light ? lite : dark) }
    static var ink: Color { light ? .black : .white }               // what was white: text, rules, solid buttons
    static var paper: Color { light ? .white : .black }             // what was black: the ground, text on solid buttons
    static var bg: Color { paper }
    static var surface: Color { pick(0x1A1A1A, 0xF2F2F2) }
    static var surface2: Color { pick(0x232323, 0xE6E6E6) }
    static var line: Color { pick(0x2A2A2A, 0xDDDDDD) }
    static var head: Color { ink }
    static var body: Color { pick(0xEEEEEE, 0x111111) }
    static var low: Color { pick(0xD0D1D2, 0x3A3A3A) }
    static var muted: Color { pick(0x8E8E8E, 0x6E6E6E) }
    static var idle: Color { pick(0x4A4A4A, 0xC4C4C4) }              // the memory bar's grey (apps that would close)
    static let hazard = hex(0xED4E3B)
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
    /// Where Buy Now goes: the Focus page's buy section, as the site's own Buy link does (#buy).
    static let buy = URL(string: "https://paradoxica.co.uk/focus#buy")!
    /// Whether this copy is on a trial. Licences aren't built yet, so it's shown for now to see the button in place.
    static let trial = true
    /// Free's weekly sessions (PRICING.md: 10 a week; Pro and Max unlimited).
    static var freeWeekly: Int { Pricing.current?.free_sessions_per_week ?? 10 }   // from pricing.json
    /// Sessions started since 00:00 on Monday (Quit All clean-ups don't count), how many of Free's are left, and the
    /// day it resets (next Monday, 00:00 local time).
    static func week(_ sessions: [[String: Any]], now: Date, calendar: Calendar = .current) -> (used: Int, left: Int, reset: Date, resetDay: String) {
        var cal = calendar; cal.firstWeekday = 2                       // weeks start on Monday
        let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
        let reset = cal.date(byAdding: .day, value: 7, to: start) ?? now
        let used = sessions.filter { ($0["kind"] as? String) != "quit all" && (($0["date"] as? Date).map { $0 >= start && $0 <= now } ?? false) }.count
        let f = DateFormatter(); f.calendar = cal; f.locale = Locale(identifier: "en_GB"); f.dateFormat = "EEEE"
        return (used, max(0, freeWeekly - used), reset, f.string(from: reset))
    }
    /// Temporary, for looking at the design: show the Focus Pro badge and the Buy button together. Remove with licences.
    static let showBoth = false
    /// Free copies show their tier by the name too: the paid box's shape, outlined instead of solid. On (his ask,
    /// 2026-11-15); the word is "Basic" for him to see, then "Free" when he switches it.
    static var freeBadge: Bool { true }
    static var freeBadgeWord: String { renderArgs.first { $0.hasPrefix("freeword=") }.map { String($0.dropFirst(9)) } ?? "Basic" }                                 // replaced by View ▸ View As (0.18.68)
    /// Whether this copy has been bought — read live (the window refreshes every 1.5 s), so the moment a purchase is
    /// recorded the Buy button becomes "Focus Pro". Licences aren't built yet: the purchase flow will set
    /// `focusPro` in Focus's defaults. A render can show it with `licensed`.
    static var licensed: Bool { tier != .free }
    /// Which Focus this copy is: Free, Pro or Max — read live from `focusTier` ("pro" / "max"; the older `focusPro`
    /// flag counts as Pro). Max has everything and shows "Max" where Pro shows "Pro"; it's priced so Pro is the one
    /// people buy. Renders: `licensed` (Pro) or `tier=max`.
    enum Tier { case free, pro, max }
    /// Whether Pro parts lock right now: only while viewing as Free (View As). A real copy never locks anything
    /// until licences exist, so his own use is untouched.
    static var gated: Bool { renderArgs.contains("viewas=free") || (UserDefaults.standard.string(forKey: "desktopViewAs") != nil && tier == .free) }
    static var tierKey: String { switch tier { case .free: return "free"; case .pro: return "pro"; case .max: return "max" } }
    static var tier: Tier {
        if renderArgs.contains("tier=max") { return .max }
        if renderArgs.contains("licensed") { return .pro }
        if renderArgs.contains("tier=free") { return .free }
        switch UserDefaults.standard.string(forKey: "desktopViewAs") {   // View ▸ View As: see the app as each user would
        case "free": return .free
        case "pro": return .pro
        case "max": return .max
        default: break
        }
        switch UserDefaults.standard.string(forKey: "focusTier") {
        case "max": return .max
        case "pro": return .pro
        default: return UserDefaults.standard.bool(forKey: "focusPro") ? .pro : .free
        }
    }
    /// Days left in the Pro Preview (what the free trial of Focus Pro is called). Not counted yet (licences come later): the planned 14, to see the button as it will read.
    static var trialDaysLeft: Int { Pricing.current?.trial_days ?? 14 }    // the Preview's length, from pricing.json

    // — feedback, written here and sent straight to the developer —
    enum FeedbackState: Equatable { case writing, sending, sent, emailed }
    @Published var feedbackShown = false
    @Published var upgradeShown = false
    func openUpgrade() { upgradeShown = true }
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
    func refresh() { f.mem = memoryByPid(); if Site.look == 2, let w = desktop.window { DesktopController.applyLook(to: w) }; tick &+= 1 }
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
                            .fill(a.on ? Site.ink : Site.idle).opacity(hover == nil || hover == a.id ? 1 : 0.45)
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
/// The line: when a session starts, a line draws round it the way the website's Buy square does — from the top centre,
/// anticlockwise, 2.4 s, quick then settling — and stays for the whole session. When the session ends, it undraws,
/// back the way it came. It follows the session itself, so starting or ending one from the menu or the key does it too.
struct SessionButton: View {
    let title: String, key: String, starting: Bool
    var tint = Color.white, tint2 = Color.white, ink = Color.black   // Settings ▸ Appearance's colour (the icon's), and text that reads on it
    let action: () -> Void
    @State private var hover = false
    @State private var trace: CGFloat = 0
    @State private var drawn = false                              // the first look: the line is simply there (or not)
    @State private var lineAlpha: Double = 1
    /// Whether the line stays round the button for the whole session (0.18.54), or only draws and goes (trying, 0.18.56).
    static let keepBorder = false
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
                HStack(spacing: 14) {
                    Spacer()
                    if !starting {                                        // in a session: the Focus mark, beside the key
                        FocusMark(ink: ink).frame(width: 24, height: 24).transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                    Text(key).font(Site.font(18)).opacity(hover ? 0.6 : 0.45).lineLimit(1)
                }.padding(.trailing, 24).animation(.spring(response: 0.45, dampingFraction: 0.7), value: starting)
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
                    .opacity(trace > 0.001 ? lineAlpha : 0)
                    .padding(-Self.gap).allowsHitTesting(false)
            )
            .scaleEffect(hover ? 1.005 : 1)
            .animation(.easeOut(duration: 0.18), value: hover)
        }
        .buttonStyle(PressStyle())
        .onAppear {
            guard let s = Self.still else { return }
            hover = s.hover; if s.trace > 0 { trace = s.trace }
            if s.hover { pressStart = Date().addingTimeInterval(-6) }
        }
        .task(id: starting) {                                       // the session started or ended: draw or undraw
            let on = !starting
            if !drawn || Self.still != nil { drawn = true; if Self.still?.trace ?? 0 == 0 { trace = on && Self.keepBorder ? 1 : 0 }; return }
            if on {
                lineAlpha = 1; trace = 0
                withAnimation(.timingCurve(0.5, 0, 0, 0.75, duration: 2.4)) { trace = 1 }        // the website's curve and time
                if !Self.keepBorder {                                                            // drawn, then let go
                    try? await Task.sleep(nanoseconds: 2_700_000_000)
                    withAnimation(.easeOut(duration: 0.6)) { lineAlpha = 0 }
                    try? await Task.sleep(nanoseconds: 650_000_000); trace = 0; lineAlpha = 1
                }
            } else {
                if !Self.keepBorder { lineAlpha = 1; trace = 1 }                                 // the whole line, then undrawn
                withAnimation(.timingCurve(0.5, 0, 0, 0.75, duration: 2.4)) { trace = 0 }
            }
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
        action()                                                    // the line follows the session (see .task above)
    }
}

/// Pressure, under the pointer: thick dark squares slide in from both outer edges along the button's middle and pile
/// up against the title, each new one queuing behind the last; once the pile is full it presses inward in a slow pulse.
/// On the click everything is let go: the squares fly back out and fade while the line draws. Leaving without a click,
/// they simply fade.
/// The Buy button's words: "14 Days of Pro Left — Buy Now" on one line, at full size (his choice, 5). Renders can show
/// the others with `buy=1…5`.
struct BuyLabel: View {
    static var style: Int { renderArgs.first { $0.hasPrefix("buy=") }.flatMap { Int($0.dropFirst(4)) } ?? 7 }   // he chose 5 (4, two lines, was ugly)
    /// The words for `days` left, in each wording (4's are its top line; "Buy Now" sits under them).
    static func words(days n: Int, style: Int) -> String {
        let days = "\(n) \(n == 1 ? "Day" : "Days")"
        switch style {
        case 2: return "\(days) of Pro Remaining — Buy Now"
        case 3, 4: return "\(days) of Pro Remaining"
        case 5: return "\(days) of Pro Left — Buy Now"
        case 6: return "\(days) of Pro Left — Upgrade"
        case 7: return "\(days) of Pro Left — Upgrade Now"
        default: return "\(days) of Pro — Buy Now"
        }
    }
    var body: some View {
        let t = Self.words(days: DesktopModel.trialDaysLeft, style: Self.style)
        if Self.style == 4 {
            VStack(spacing: 1) { Text(t).font(Site.font(14)).opacity(0.7); Text("Buy Now").font(Site.font(18, .semibold)) }
        } else { line(t) }
    }
    func line(_ t: String) -> some View { Text(t).font(Site.font(17, .medium)).lineLimit(1).minimumScaleFactor(0.8) }
}

/// Links show the pointing hand, always.
struct LinkCursor: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }
}
extension View { func linkCursor() -> some View { modifier(LinkCursor()) } }

// MARK: prices and tiers — one source, the site's pricing.json

/// Focus's prices and tiers, from paradoxica.uk/focus/pricing.json: the one source the site is built from, so the app
/// and the site can never disagree. A copy ships inside the app (works offline); the live file replaces it when the
/// window opens and the site answers. Nothing here is typed by hand.
struct Pricing: Decodable {
    struct Tier: Decodable { let name: String; let tagline: String; let monthly: Int; let once: Int?; let best: Bool?; let summary: String; let once_summary: String? }
    struct Lead: Decodable { let tier: String; let plan: String }
    let currency: String
    let trial_days: Int
    let trial_tier: String
    let free_sessions_per_week: Int
    let lead: Lead
    let badge: String?                                         // the best tier's label ("Best value"), when the file has it
    let tiers: [String: Tier]
    let features: [Group]
    struct Group: Decodable { let group: String; let rows: [[Cell]] }
    enum Cell: Decodable {
        case text(String), yes(Bool)
        init(from d: Decoder) throws { let c = try d.singleValueContainer(); if let b = try? c.decode(Bool.self) { self = .yes(b) } else { self = .text(try c.decode(String.self)) } }
    }
    static let url = URL(string: "https://paradoxica.uk/focus/pricing.json")!
    static let page = URL(string: "https://paradoxica.uk/focus#pricing")!
    /// Where a plan is bought: the site's checkout, in the browser (Apple Pay, the padlock, Stripe).
    static func checkout(tier: String, plan: String) -> URL { URL(string: "https://paradoxica.uk/focus/checkout/?tier=\(tier)&plan=\(plan)")! }
    static var cacheFile: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Focus")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("pricing.json")
    }
    /// The copy inside the app, as shipped.
    static var bundled: Pricing? {
        let paths = [Bundle.main.url(forResource: "pricing", withExtension: "json"), URL(fileURLWithPath: "pricing.json")].compactMap { $0 }
        return paths.lazy.compactMap { try? JSONDecoder().decode(Pricing.self, from: Data(contentsOf: $0)) }.first
    }
    /// What the app uses: the last live copy if there is one, else the shipped one.
    static var current: Pricing? = (try? JSONDecoder().decode(Pricing.self, from: Data(contentsOf: cacheFile))) ?? bundled
    /// Fetches the live file; keeps it only if it parses.
    static func refresh(_ done: (() -> Void)? = nil) {
        URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)) { data, _, _ in
            guard let data, let p = try? JSONDecoder().decode(Pricing.self, from: data) else { return }
            try? data.write(to: cacheFile)
            DispatchQueue.main.async { current = p; done?() }
        }.resume()
    }
    /// "{free_sessions_per_week}" in the file's words, filled in.
    func fill(_ t: String) -> String { t.replacingOccurrences(of: "{free_sessions_per_week}", with: "\(free_sessions_per_week)") }
}

/// Upgrade: the plans, side by side, the way Mac apps sell from inside themselves — Monthly or Once, Pro marked as
/// the best value, and the plan's button opening the site's checkout in the browser. Everything comes from pricing.json.
struct UpgradeCard: View {
    @ObservedObject var m: DesktopModel
    @State private var once = false
    var body: some View {
        ZStack {
            Color.black.opacity(0.6).onTapGesture { m.upgradeShown = false }
            if let p = Pricing.current {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Upgrade Focus").font(Site.font(30, .medium)).tracking(-0.5).foregroundColor(Site.head)
                        Spacer()
                        Button { m.upgradeShown = false } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .medium)).foregroundColor(Site.low).frame(width: 28, height: 28).contentShape(Rectangle()) }.buttonStyle(.plain)
                    }
                    PanelRule()
                    HStack {
                        Text(p.lead.tier == "pro" ? "Pay monthly, or once and keep it forever." : "").font(Site.font(17)).foregroundColor(Site.low)
                        Spacer()
                        Choice(options: ["Monthly", "Once"], selected: once ? 1 : 0) { i in once = i == 1 }
                    }
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(["free", "pro", "max"], id: \.self) { key in
                            if let t = p.tiers[key] { plan(key, t, p) }
                        }
                    }.fixedSize(horizontal: false, vertical: true).padding(.top, 18)
                    HStack {
                        Text("\(p.trial_days) days of Pro come free with every new copy.").font(Site.font(15)).foregroundColor(Site.muted)
                        Spacer()
                        Button { NSWorkspace.shared.open(Pricing.page) } label: {
                            HStack(spacing: 5) { Text("Compare every feature").font(Site.font(15, .medium)); Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)) }
                                .foregroundColor(Site.head).underline()
                        }.buttonStyle(.plain).linkCursor()
                    }.padding(.top, 18)
                }
                .padding(28).frame(width: 780).fixedSize(horizontal: false, vertical: true)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Site.bg))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Site.ink.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
            }
        }
        .onAppear { once = (Pricing.current?.lead.plan ?? "monthly") == "once"; Pricing.refresh { m.tick &+= 1 } }
    }
    @ViewBuilder func plan(_ key: String, _ t: Pricing.Tier, _ p: Pricing) -> some View {
        let best = t.best == true, current = DesktopModel.tierKey == key
        let price = key == "free" ? "\(p.currency)0" : once ? "\(p.currency)\(t.once ?? t.monthly * 10)" : "\(p.currency)\(t.monthly)"
        let per = key == "free" ? "Free for everyone" : once ? "once" : "a month"
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(t.name).font(Site.font(24, .medium)).foregroundColor(Site.head)
                Spacer()
                if best { Text(p.badge ?? "Best value").font(Site.font(12, .semibold)).foregroundColor(Site.paper).padding(.horizontal, 7).frame(height: 20).background(RoundedRectangle(cornerRadius: 5).fill(Site.ink)) }
            }
            Text(t.tagline).font(Site.font(15)).foregroundColor(Site.low)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(price).font(Site.font(32, .medium)).foregroundColor(Site.head)
                Text(per).font(Site.font(15)).foregroundColor(Site.muted)
            }.padding(.top, 8)
            Text(p.fill(once && key != "free" ? (t.once_summary ?? t.summary) : t.summary)).font(Site.font(14)).foregroundColor(Site.low)
                .fixedSize(horizontal: false, vertical: true).frame(minHeight: 40, alignment: .top)
            Button {
                if key != "free" && !current { NSWorkspace.shared.open(Pricing.checkout(tier: key, plan: once ? "once" : "monthly")) }
            } label: {
                Text(current ? "Your plan" : key == "free" ? "Included" : "Choose \(t.name)").font(Site.font(16, .medium))
                    .foregroundColor(best && !current ? Site.paper : Site.head).frame(maxWidth: .infinity).frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(best && !current ? Site.ink : Color.clear))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Site.ink.opacity(best && !current ? 0 : 0.6), lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))   // the whole button takes the click
            }.buttonStyle(PressStyle()).disabled(key == "free" || current).linkCursor().padding(.top, 10)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(best ? Site.surface : Site.bg))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(best ? Site.ink.opacity(0.9) : Site.line, lineWidth: best ? 1.5 : 1))
    }
}

/// The Focus mark — a ring and its dot, as the app icon draws them — in the button's ink.
struct FocusMark: View {
    let ink: Color
    var body: some View {
        GeometryReader { g in
            let d = min(g.size.width, g.size.height)
            ZStack {
                Circle().stroke(ink, lineWidth: d * 0.12).padding(d * 0.06)
                Circle().fill(ink).frame(width: d * 0.42, height: d * 0.42)
            }
        }
    }
}

struct TitleWidth: PreferenceKey {
    static let defaultValue: CGFloat = 200
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct PressureDots: View {
    let ink: Color, titleWidth: CGFloat
    let start: Date, end: Date?, release: Date?
    static let side: CGFloat = 9, step: CGFloat = 15, every = 0.26, travel = 0.5, perSide = 8
    static let edgeL: CGFloat = 16, keyRoom: CGFloat = 92, titleGap: CGFloat = 20     // the key sits at the right edge
    /// Where the squares come to rest: as many as fit between each edge and the title, the same number both sides,
    /// nearest the title first.
    static func slots(width: CGFloat, titleWidth: CGFloat) -> (left: [CGFloat], right: [CGFloat]) {
        let midX = width / 2, innerL = midX - titleWidth / 2 - titleGap, innerR = midX + titleWidth / 2 + titleGap
        let room = Int(max(0, min(innerL - edgeL, width - keyRoom - innerR)) / step)
        let count = max(0, min(perSide, room))
        return ((0..<count).map { innerL - CGFloat($0) * step }, (0..<count).map { innerR + CGFloat($0) * step })
    }
    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { c, size in
                let now = tl.date
                let built = (release ?? now).timeIntervalSince(start)            // how far the build got (frozen at the click)
                let gone = release.map { now.timeIntervalSince($0) / 0.45 } ?? 0  // 0…1 after the click
                let fade = end.map { 1 - now.timeIntervalSince($0) / 0.25 } ?? 1  // leaving without a click
                guard gone < 1, fade > 0, built > 0 else { return }
                let y = size.height / 2, s = Self.side
                let slots = Self.slots(width: size.width, titleWidth: titleWidth)
                let edgeL = Self.edgeL, edgeR = size.width - Self.keyRoom
                let count = slots.left.count
                let full = built > Double(count) * Self.every + Self.travel
                let squeeze = full ? CGFloat(sin(now.timeIntervalSinceReferenceDate * 3)) * 1.6 : 0
                for k in 0..<count {
                    let born = Double(k) * Self.every
                    guard built > born else { break }
                    var p = min(1, (built - born) / Self.travel); p = 1 - pow(1 - p, 3)        // ease out: arrives and settles
                    for left in [true, false] {
                        let slot = left ? slots.left[k] : slots.right[k]
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
        Circle().fill(Site.ink).frame(width: 8, height: 8).opacity(on ? 1 : 0.35)
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
        let ink: NSColor = Site.light ? .black : .white
        tv.font = Self.nsFont(size); tv.textColor = ink; tv.insertionPointColor = ink
        tv.typingAttributes = [.font: Self.nsFont(size), .foregroundColor: ink]
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
                            Text(m.feedbackState == .sending ? "Sending…" : "Send").font(Site.font(18, .medium)).foregroundColor(Site.paper)
                                .padding(.horizontal, 22).frame(height: 32)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Site.ink))
                        }.buttonStyle(.plain)
                        .opacity(m.feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || m.feedbackState == .sending ? 0.35 : 1)
                    }
                }
            }
            .padding(24).frame(width: 520)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Site.bg))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Site.ink.opacity(0.35), lineWidth: 1))
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

/// The line under a heading inside a panel (Behaviour, Appearance, the Manual's sections): white, full width, finer
/// than the panel's own.
struct HeadingRule: View {
    var body: some View { Rectangle().fill(Site.ink.opacity(0.85)).frame(height: 0.75).frame(maxWidth: .infinity) }
}

/// The line under a panel's name: white, full width — the panel's one strong rule.
struct PanelRule: View {
    var body: some View { Rectangle().fill(Site.ink).frame(height: 1).frame(maxWidth: .infinity).padding(.top, 10).padding(.bottom, 12) }
}

/// A mode in the Session Editor's list. Its name opens it to edit (as does the rest of the row). At the right: its key,
/// and under the pointer a white "Start session" button; a mode that's running says "On" (hover: "End session").
struct ModeListRow: View {
    @ObservedObject var m: DesktopModel
    let mode: DesktopModel.ModeLine
    @State private var hover = false
    @State private var nameHover = false
    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                ForEach(Array(mode.apps.compactMap { m.f.path($0) }.prefix(3).enumerated().reversed()), id: \.offset) { i, p in
                    Image(nsImage: m.icon(p)).resizable().interpolation(.high).frame(width: 20, height: 20).offset(x: CGFloat(i) * 9)
                }
            }.frame(width: 40, alignment: .leading)
            Text(mode.name).font(Site.font(18, mode.live ? .medium : .regular)).foregroundColor(Site.head).lineLimit(1)
                .underline(nameHover).onHover { nameHover = $0 }.help("Edit \(mode.name)")
            Spacer(minLength: 8)
            if mode.live {
                Button { if DesktopModel.gated { m.openUpgrade() } else { m.act { m.f.startOrSwitch(mode.id) } } } label: {
                    Text(hover ? "End session" : "On").font(Site.font(14, .medium)).foregroundColor(Site.paper)
                        .padding(.horizontal, 12).frame(height: 26).background(Capsule().fill(Site.ink))
                }.buttonStyle(PressStyle())
            } else if hover {
                Button { if DesktopModel.gated { m.openUpgrade() } else if !mode.apps.isEmpty { m.act { m.f.startOrSwitch(mode.id) } } } label: {
                    Text(mode.apps.isEmpty ? "Add apps first" : "Start session").font(Site.font(14, .medium)).foregroundColor(Site.paper)
                        .padding(.horizontal, 12).frame(height: 26).background(Capsule().fill(Site.ink))
                }.buttonStyle(PressStyle()).opacity(mode.apps.isEmpty ? 0.5 : 1)
            }
            Text(mode.key).font(Site.font(15)).foregroundColor(Site.muted).frame(minWidth: 30, alignment: .trailing)
        }
        .padding(.horizontal, 12).frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hover ? Site.surface : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Site.ink.opacity(mode.live ? 0.85 : 0), lineWidth: 1))
        .contentShape(Rectangle()).onHover { hover = $0 }
        .onTapGesture { m.selection = mode.id }
    }
}

/// Where a Pro feature is locked (viewing as Free): what Pro adds, and Upgrade Now.
struct LockedPanel: View {
    @ObservedObject var m: DesktopModel
    let text: String
    var body: some View {
        HStack(spacing: 14) {
            ProTag()
            Text(text).font(Site.font(16)).foregroundColor(Site.low).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 10)
            Button { m.openUpgrade() } label: {
                Text("Upgrade Now").font(Site.font(15, .medium)).foregroundColor(Site.paper).padding(.horizontal, 14).frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Site.ink))
            }.buttonStyle(PressStyle()).linkCursor()
        }
        .padding(14).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Site.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Site.line, lineWidth: 1))
        .padding(.vertical, 10)
    }
}

/// For development: see the window as a Free, Pro or Max user, with the Pro parts locking and unlocking for real.
/// Sits under the modes; collapses with its chevron; View ▸ Developer Panel shows or hides it altogether.
struct ViewAsPanel: View {
    @ObservedObject var m: DesktopModel
    @State private var open = UserDefaults.standard.object(forKey: "desktopViewAsOpen") as? Bool ?? true
    var body: some View {
        let now = renderArgs.contains("viewas=free") ? "free" : UserDefaults.standard.string(forKey: "desktopViewAs") ?? ""
        VStack(alignment: .leading, spacing: 8) {
            Button { open.toggle(); UserDefaults.standard.set(open, forKey: "desktopViewAsOpen") } label: {
                HStack(spacing: 5) {
                    Text("View As").font(Site.font(15, .medium))
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).rotationEffect(.degrees(open ? 90 : 0)).offset(y: 1.5)
                    Spacer()
                    Text("Developer").font(Site.font(12)).foregroundColor(Site.muted)
                }.foregroundColor(Site.muted).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if open {
                HStack(spacing: 6) {
                    ForEach([("Actual", ""), ("Free", "free"), ("Pro", "pro"), ("Max", "max")], id: \.1) { title, key in
                        let on = now == key
                        Button {
                            m.act { if key.isEmpty { UserDefaults.standard.removeObject(forKey: "desktopViewAs") } else { UserDefaults.standard.set(key, forKey: "desktopViewAs") } }
                        } label: {
                            Text(title).font(Site.font(14, .medium)).foregroundColor(on ? Site.paper : Site.head).lineLimit(1).frame(maxWidth: .infinity).frame(height: 30)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? Site.ink : Color.clear))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Site.ink.opacity(on ? 0 : 0.5), lineWidth: 1))
                                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))   // the whole button takes the click
                        }.buttonStyle(PressStyle())
                    }
                }
            }
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Site.muted, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .padding(.leading, 12).padding(.trailing, 12).padding(.top, 10)
    }
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

/// A heading inside a panel (Apps Outside Session, Critical System Processes, Modes…): large and white, with a fine
/// white line under it — the same as Behaviour and Appearance. A column name (Usage) can sit at its right.
/// With no name, it is just the column name, small, over the list.
struct SectionLabel: View {
    let left: String, right: String, divider: Bool
    var pro = false
    init(_ left: String, _ right: String = "", divider: Bool = true, pro: Bool = false) { self.left = left; self.right = right; self.divider = divider; self.pro = pro }
    var body: some View {
        if left.isEmpty {
            HStack { Spacer(); Text(right).font(Site.font(15)).foregroundColor(Site.muted).padding(.trailing, 38) }
                .padding(.horizontal, 14).padding(.top, 2).padding(.bottom, 0)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(left).font(Site.font(22, .medium)).tracking(-0.3).foregroundColor(Site.head)
                    if pro { ProTag().alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 } }
                    Spacer()
                    if !right.isEmpty { Text(right).font(Site.font(15)).foregroundColor(Site.muted).padding(.trailing, 24) }
                }
                HeadingRule()
            }.padding(.horizontal, 14).padding(.top, divider ? 30 : 20).padding(.bottom, 8)
        }
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
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))   // the whole button takes the click
        }
        .buttonStyle(.plain).onHover { hover = $0 }
    }
}

/// A small white "Pro" beside something only Pro (and Max) include — shown on Free and during the Pro Preview, so
/// it's clear what Pro brings; gone once Pro or Max is bought.
struct ProTag: View {
    var body: some View {
        if !DesktopModel.licensed || renderArgs.contains("tags") {
            Text("Pro").font(Site.font(11, .semibold)).foregroundColor(Site.paper)
                .padding(.horizontal, 5).frame(height: 16)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Site.ink))
                .help("Part of Focus Pro")
        }
    }
}

struct SideRow: View {
    let title: String, trailing: String, live: Bool, selected: Bool, icons: [NSImage], symbol: String?, action: () -> Void
    var hint: String? = nil                                      // under the pointer, said at the right instead of `trailing`
    var state: Bool? = nil                                       // the Session Editor: white "On" in a session, nothing otherwise
    var start: (() -> Void)? = nil                               // a mode: under the pointer, "Start" (or "End") takes the key's place
    var pro = false                                              // a Pro feature: a small "Pro" tag after the title
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
            Text(title).font(Site.font(18, selected ? .medium : .regular)).lineLimit(1).truncationMode(.tail)   // never shrinks (e.g. when Start appears)
            if pro { ProTag() }
            Spacer(minLength: 6)
            if hover, let start {
                Button(action: start) {
                    Text(live ? "End" : "Start").font(Site.font(14, .medium)).foregroundColor(Site.paper)
                        .padding(.horizontal, 10).frame(height: 22).background(Capsule().fill(Site.ink))
                }.buttonStyle(PressStyle()).help(live ? "End this session" : "Start this session")
            } else {
            if live && state == nil { Text("On").font(Site.font(14, .medium)).foregroundColor(Site.paper).padding(.horizontal, 7).frame(height: 18).background(Capsule().fill(Site.ink)) }
            if hover, let hint, state != nil { Text(hint).font(Site.font(15)).foregroundColor(Site.head) }
            if let on = state {                                 // "On" in a session; nothing otherwise
                if on {
                    Text("On").font(Site.font(14, .medium)).foregroundColor(Site.paper)
                        .frame(width: 38, height: 20).background(RoundedRectangle(cornerRadius: 10, style: .circular).fill(Site.ink))
                }
            } else { Text(hover && hint != nil ? hint! : trailing).font(Site.font(15)).foregroundColor(live || (hover && hint != nil) ? Site.head : Site.muted) }
            }
        }
        .foregroundColor(selected || live ? Site.head : Site.low)
        .padding(.horizontal, 12).frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? Site.surface2 : hover || live ? Site.surface : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Site.ink.opacity(live ? 0.85 : 0), lineWidth: 1))   // in use: outlined in white
        .contentShape(Rectangle()).onHover { hover = $0 }.onTapGesture(perform: action)
    }
}

// MARK: the window's content

struct DesktopView: View {
    @ObservedObject var m: DesktopModel
    /// Settings ▸ Appearance ▸ Width: Default (equal space either side of the page), Wide (the page fills the window), or
    /// Minimal (the page fills a window made narrower by a sidebar's width). Renders: `trial=narrow|wide|minimal`.
    enum Trial: Int { case narrow = 0, wide = 1, minimal = 2 }   // Default, Wide, Minimal (stored under "desktopWidthV2")
    static var renderTrial: Trial?
    static var trial: Trial { renderTrial ?? Trial(rawValue: UserDefaults.standard.integer(forKey: "desktopWidthV2")) ?? .narrow }
    /// Minimal takes the right sidebar's width off the window itself.
    static let minimalCut: CGFloat = 292
    /// How much the window's width changes going from one Width to another: only Minimal moves it.
    static func minimalDelta(was: Trial, now: Trial) -> CGFloat { (now == .minimal ? -minimalCut : 0) - (was == .minimal ? -minimalCut : 0) }
    /// Room kept beside the page column: an empty right sidebar (as wide as the left one), or equal margins either side.
    var pageInsets: (lead: CGFloat, trail: CGFloat) {
        switch Self.trial { case .narrow: return (36, 36); case .wide, .minimal: return (0, 0) }
    }
    var body: some View {
        let _ = m.tick
        VStack(spacing: 0) {
            // The top row, across the whole window: the logo, and the one action. Shown on every page.
            HStack(alignment: .top, spacing: 0) {
                HStack(spacing: 12) {
                    if m.still { Image(nsImage: siteLogo(160)).resizable().interpolation(.high).frame(width: Layout.button, height: Layout.button) } else { LogoView(side: Layout.button) }
                    Text("Focus").font(Site.font(38, .medium)).tracking(-0.8).foregroundColor(Site.head)
                    if DesktopModel.licensed {                            // Focus Pro / Max: a solid box by the name
                        Text(DesktopModel.tier == .max ? "Max" : "Pro").font(Site.font(15, .semibold)).foregroundColor(Site.paper)
                            .padding(.horizontal, 7).frame(height: 24)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Site.ink))
                            .offset(y: 2)
                    }
                    if !DesktopModel.licensed && DesktopModel.freeBadge {  // Free copies: the same box, outlined (trying "Basic")
                        Text(DesktopModel.freeBadgeWord).font(Site.font(15, .semibold)).foregroundColor(Site.ink)
                            .padding(.horizontal, 7).frame(height: 24)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Site.paper))
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Site.ink, lineWidth: 1.2))
                            .offset(y: 2)
                    }
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
        .background(Site.bg).preferredColorScheme(Site.light ? .light : .dark)
        .overlay { if m.feedbackShown { FeedbackCard(m: m).transition(.opacity) } }
        .overlay { if m.upgradeShown { UpgradeCard(m: m).transition(.opacity) } }
        .animation(.easeOut(duration: 0.15), value: m.upgradeShown)
        .animation(.easeOut(duration: 0.15), value: m.feedbackShown)
    }
    /// The big button wears the colour chosen in Settings ▸ Appearance (the icon's ring, then its dot), white when none is.
    /// Its text is the user's Text colour: black (the standard) or white.
    var buttonColours: (Color, Color, Color) {
        guard let a = hexColor(m.f.iconColor) else { return (Site.ink, Site.ink, Site.paper) }   // no colour: the look's own
        let b = hexColor(m.f.iconColor2) ?? a
        return (Color(nsColor: a), Color(nsColor: b), Self.buttonInkWhite ? .white : .black)
    }
    /// Settings ▸ Appearance ▸ Text colour (the big button only). Renders: `ink=white`.
    static var buttonInkWhite: Bool { renderArgs.contains("ink=white") || UserDefaults.standard.bool(forKey: "desktopButtonInkWhite") }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 2) {
                SideRow(title: "Session Editor", trailing: "", live: m.f.focused && !m.modes.contains { $0.live }, selected: m.selection == nil, icons: [], symbol: "circle.grid.2x2",
                        action: { m.selection = nil }, state: m.f.focused)
                SideRow(title: "Shortcuts", trailing: "", live: false, selected: m.selection == Page.shortcuts, icons: [], symbol: "keyboard", action: { m.selection = Page.shortcuts }, pro: true)
                SideRow(title: "Tools", trailing: "", live: false, selected: m.selection == Page.tools, icons: [], symbol: "wrench.and.screwdriver", action: { m.selection = Page.tools }, pro: true)
                SideRow(title: "History", trailing: m.f.sessions.isEmpty ? "" : "\(m.f.sessions.count)", live: false, selected: m.selection == Page.history, icons: [], symbol: "clock.arrow.circlepath", action: { m.selection = Page.history }, pro: true)
                SideRow(title: "Settings", trailing: "", live: false, selected: m.selection == Page.settings, icons: [], symbol: "gearshape") { m.selection = Page.settings }
            }.padding(.horizontal, 10)
            Button { withAnimation(.easeOut(duration: 0.15)) { m.modesShown.toggle() } } label: {
                HStack(spacing: 5) {
                    Text("Modes").font(Site.font(16, .medium))
                    ProTag()
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).rotationEffect(.degrees(m.modesShown ? 90 : 0)).offset(y: 1.5)   // on the text's middle line
                    Spacer()
                }.foregroundColor(Site.muted).padding(.leading, 22).padding(.trailing, 14).padding(.top, 14).padding(.bottom, 5).contentShape(Rectangle())
            }.buttonStyle(.plain).help(m.modesShown ? "Hide your modes" : "Show your modes")
            if m.modesShown {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(m.modes) { mode in
                            SideRow(title: mode.name, trailing: mode.key, live: mode.live, selected: m.selection == mode.id,
                                    icons: mode.apps.compactMap { m.f.path($0) }.map(m.icon), symbol: nil,
                                    action: { m.selection = mode.id },                       // the name (the row): edit it
                                    start: mode.apps.isEmpty ? nil : { if DesktopModel.gated { m.openUpgrade() } else { m.act { m.f.startOrSwitch(mode.id) } } })
                                .onDrag { m.draggingMode = mode.id; return NSItemProvider(object: mode.id as NSString) }
                                .onDrop(of: [UTType.text], delegate: ModeDrop(id: mode.id, m: m))
                                .contextMenu { ModeMenu(m: m, mode: mode) }
                        }
                        SideRow(title: "Create New Mode", trailing: "", live: false, selected: false, icons: [], symbol: "plus.circle") { if DesktopModel.gated { m.openUpgrade() } else { m.newMode() } }
                    }.padding(.horizontal, 10)
                }
                .frame(maxHeight: CGFloat(m.modes.count + 1) * 36 + 4)    // only as tall as the modes: what follows sits right under them
            }
            if UserDefaults.standard.object(forKey: "desktopDevPanel") as? Bool ?? true { ViewAsPanel(m: m) }
            Spacer(minLength: 8)
            // The foot: an update when there is one; Help and the Manual; then the maker's mark, which opens the site.
            VStack(spacing: 8) {
                if DesktopModel.trial && (!DesktopModel.licensed || DesktopModel.showBoth) {   // a trial: one clear way to buy
                    Button { m.openUpgrade() } label: {
                        BuyLabel()                                       // the Pro Preview
                            .foregroundColor(Site.paper)
                            .padding(.horizontal, 10).frame(maxWidth: .infinity).frame(minHeight: 40).padding(.vertical, BuyLabel.style == 4 ? 6 : 0)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Site.ink))
                    }.buttonStyle(PressStyle()).help("See the plans").linkCursor()
                }
                if let u = m.update {
                    Button { NSWorkspace.shared.open(u.url) } label: {
                        HStack(spacing: 7) { Image(systemName: "arrow.down.circle.fill").font(.system(size: 15)); Text("Update available").font(Site.font(15, .medium)) }
                            .foregroundColor(Site.paper).frame(maxWidth: .infinity).frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Site.ink))
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
                        if let b = brandLockup { Image(nsImage: Site.light ? tinted(b, .black) : b).resizable().interpolation(.high).frame(width: 196, height: 196 * 112.0 / 1080.0) }
                        else { Text("★★★★★ × PARADOX").font(Site.font(15)).foregroundColor(Site.head) }
                        Text("™").font(Site.font(8, .medium)).foregroundColor(Site.head).offset(x: -3, y: 2)
                    }.fixedSize().frame(maxWidth: .infinity).padding(.top, 12).padding(.bottom, 2).contentShape(Rectangle())
                }.buttonStyle(.plain).help("paradoxica.co.uk").linkCursor()
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
                    HStack(alignment: .firstTextBaseline) {
                        Text("Apps in Session").font(Site.font(26, .medium)).tracking(-0.5).foregroundColor(Site.head)   // the menu's own headings
                        Spacer(minLength: 12)
                        if !DesktopModel.licensed {                       // Free: sessions left this week, and when it resets
                            let w = DesktopModel.week(f.sessions, now: Date())
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(w.left) \(w.left == 1 ? "Session" : "Sessions") remaining this week").font(Site.font(16, .medium)).foregroundColor(Site.head)
                                Text("Resets 00:00 on \(w.resetDay)").font(Site.font(14)).foregroundColor(Site.muted)
                            }
                        }
                    }
                    PanelRule()
                    Text(f.focused ? "These apps are in your session. Click one to take it out."
                                   : "Tick the apps you want in the session. Everything else closes when the session starts and comes back when it ends.")
                        .font(Site.font(17)).foregroundColor(Site.low).fixedSize(horizontal: false, vertical: true)
                    if !f.focused { MemoryBar(apps: m.running).padding(.top, 12) }      // the memory to be saved is shown before a session, never during one
                    SectionLabel("", "Usage", divider: false).padding(.horizontal, -14).padding(.top, f.focused ? 0 : 8)
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
                    SectionLabel("Modes — frequently used sessions", pro: true).padding(.horizontal, -14).padding(.top, 8)
                    Note("A mode is a set of apps you keep open. Start one with its button or its key; click its name to edit it.")
                    if DesktopModel.gated { LockedPanel(m: m, text: "Modes are part of Pro: a set of apps you start with one key.") }
                    VStack(spacing: 2) {
                        ForEach(m.modes) { mode in
                            ModeListRow(m: m, mode: mode).contextMenu { ModeMenu(m: m, mode: mode) }
                        }
                        SideRow(title: "Create New Mode", trailing: "", live: false, selected: false, icons: [], symbol: "plus.circle") { if DesktopModel.gated { m.openUpgrade() } else { m.newMode() } }
                    }.padding(.horizontal, -12).opacity(DesktopModel.gated ? 0.45 : 1)
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
                ChoiceOption(title: o, on: i == selected, available: !unavailable.contains(i)) { pick(i) }
            }
        }
    }
}
/// One option of a Choice. Chosen: solid white. Not chosen: outlined, and under the pointer it fills a little and its
/// outline brightens, so it's clear it can be picked.
struct ChoiceOption: View {
    let title: String, on: Bool, available: Bool, pick: () -> Void
    @State private var hover = false
    var body: some View {
        let lit = hover && available && !on
        Button { if available { pick() } } label: {
            Text(title).font(Site.font(16, .medium)).foregroundColor(on ? Site.paper : Site.head).lineLimit(1).fixedSize()
                .padding(.horizontal, 16).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Site.ink : lit ? Site.surface2 : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Site.ink.opacity(on ? 0 : lit ? 1 : 0.75), lineWidth: 1))
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).opacity(available ? 1 : 0.35).onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: lit)
    }
}

/// Text size: − and + either side of where it is now — "Default", or how many steps (one ⌘+ each) above or below.
/// Clicking the middle goes back to Default. The same steps as ⌘+ and ⌘−.
struct TextSizeStepper: View {
    /// "Default", or how many steps (one ⌘+ each) above or below it: "Default +2", "Default −1".
    static func label(_ scale: CGFloat) -> String {
        let step = Int(((scale - 1) * 10).rounded())
        return step == 0 ? "Default" : "Default \(step > 0 ? "+" : "−")\(abs(step))"
    }
    var body: some View {
        HStack(spacing: 8) {
            key("minus", enabled: Site.scale > 0.801) { desktop.smallerText() }.help("Smaller (⌘−)")
            Button { desktop.setScale(1) } label: {
                Text(Self.label(Site.scale)).font(Site.font(16, .medium))
                    .foregroundColor(Site.paper).lineLimit(1).fixedSize().frame(minWidth: 110).frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Site.ink)).contentShape(Rectangle())
            }.buttonStyle(.plain).help(Self.label(Site.scale) == "Default" ? "The standard size" : "Back to Default")
            key("plus", enabled: Site.scale < 1.599) { desktop.biggerText() }.help("Bigger (⌘+)")
        }
    }
    private func key(_ symbol: String, enabled: Bool, _ act: @escaping () -> Void) -> some View {
        StepKey(symbol: symbol, enabled: enabled, act: act)
    }
}

struct StepKey: View {
    let symbol: String, enabled: Bool, act: () -> Void
    @State private var hover = false
    var body: some View {
        let lit = hover && enabled
        Button(action: act) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundColor(Site.head).frame(width: 44, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(lit ? Site.surface2 : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Site.ink.opacity(lit ? 1 : 0.75), lineWidth: 1)).contentShape(Rectangle())
        }.buttonStyle(PressStyle()).disabled(!enabled).opacity(enabled ? 1 : 0.35).onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: lit)
    }
}

/// One colour in Settings ▸ Appearance ▸ Icon colour. Chosen: outlined in white. Under the pointer: lifts a shade.
struct ColourTile: View {
    let name: String, a: String, b: String, on: Bool, pick: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: pick) {
            HStack(spacing: 8) {
                ZStack { Circle().fill(Color(nsColor: hexColor(a) ?? .white)).frame(width: 16, height: 16)
                         Circle().fill(Color(nsColor: hexColor(b) ?? hexColor(a) ?? .white)).frame(width: 7, height: 7) }
                Text(name).font(Site.font(15, on ? .medium : .regular)).foregroundColor(on || hover ? Site.head : Site.low).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }.padding(.horizontal, 12).frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on || hover ? Site.surface2 : Site.surface))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Site.ink.opacity(on ? 0.9 : hover ? 0.4 : 0), lineWidth: on ? 1.5 : 1))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hover = $0 }.animation(.easeOut(duration: 0.12), value: hover)
    }
}

/// The name of a group of settings: larger than a section label, with room above it.
struct GroupTitle: View {
    let title: String
    init(_ t: String) { title = t }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Site.font(22, .medium)).tracking(-0.3).foregroundColor(Site.head)
            HeadingRule()
        }.padding(.top, 30).padding(.bottom, 2)
    }
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
        PageFrame(title: "Shortcuts", text: "The keys that start and end a session, open the menu, open this app, and start your modes.") {
            if DesktopModel.gated { LockedPanel(m: m, text: "Choosing your own keys is part of Pro. Free keeps ⌘⇧F, ⌘⇧E and ⌥⇧E.") }
            SettingLine(title: "Start / End Session", note: f.sessionKeyTaken ? "That combination is taken by another app. Pick another." : "") {
                Choice(options: modifierChoices.map { $0.label + "F" }, selected: modifierChoices.firstIndex { $0.mods == f.sessionMods } ?? 0) { i in if !DesktopModel.gated { m.act { f.sessionMods = modifierChoices[i].mods } } }
            }
            SettingLine(title: "Open the Menu", note: f.menuKeyTaken ? "That combination is taken by another app. Pick another." : "") {
                Choice(options: menuModifierChoices.map { $0.label + "E" }, selected: menuModifierChoices.firstIndex { $0.mods == f.menuMods } ?? 0) { i in if !DesktopModel.gated { m.act { f.menuMods = menuModifierChoices[i].mods } } }
            }
            SettingLine(title: "Open the Desktop App", note: f.appKeyTaken ? "That combination is taken by another app. Pick another." : "From anywhere. Press again to put it away.") {
                Choice(options: modifierChoices.map { $0.label + "E" }, selected: modifierChoices.firstIndex { $0.mods == f.appMods } ?? 0) { i in if !DesktopModel.gated { m.act { f.appMods = modifierChoices[i].mods } } }
            }
            SettingLine(title: "Modes", note: "This, plus the number you give each mode.") {
                Choice(options: modeModifierChoices.map { $0.label + "1" }, selected: modeModifierChoices.firstIndex { $0.mods == f.modeMods } ?? 0) { i in if !DesktopModel.gated { m.act { f.modeMods = modeModifierChoices[i].mods } } }
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
        .text("The beauty of Focus is that whether you use the button (in the menu, and at the top of the app) or the keyboard shortcut (⌘⇧F by default, and yours to change), you can press it and instantly get everything back."),
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
        .figure(.colours, "The colour you choose in Settings ▸ Appearance colours the menu bar icon and the big button."),
        .heading("Menu and app"),
        .text("Focus is primarily a menu tool — it's intended for power users who like to keep their hands on the keyboard and stay in flow. But there is also a fully working app, which you can hide with ⌘H or close with ⌘Q (which does not stop the menu from running). Use one or both, as you like. The menu always runs: that's where the work is done."),
        .figure(.keys, "The keys that matter."),
        .heading("Feedback"),
        .text("If you have any ideas or feedback, please use the Feedback button."),
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
                .textSelection(.enabled)                                   // any of it can be selected and copied
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
                }.buttonStyle(.plain).help("Back to the contents").linkCursor()
            }.frame(maxWidth: 680).padding(.top, 34).padding(.bottom, 2).id(t)
            HeadingRule().frame(maxWidth: 680).padding(.top, 6).padding(.bottom, 4)
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
            }.buttonStyle(.plain).padding(.top, 10).help(url.absoluteString).linkCursor()
        }
    }
}

/// The Manual's contents: every section, numbered down each column (1–5, then 6 on); click one to go to it.
struct Contents: View {
    let titles: [String], go: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Contents").font(ManualPage.f(14, .medium)).foregroundColor(Site.muted).padding(.bottom, 8)
            let half = (titles.count + 1) / 2
            HStack(alignment: .top, spacing: 16) {
                ForEach([0, 1], id: \.self) { col in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(titles.enumerated()).filter { col == 0 ? $0.offset < half : $0.offset >= half }, id: \.offset) { i, t in
                            ContentsLine(number: i + 1, title: t) { go(t) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
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
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(number)").font(ManualPage.f(15)).foregroundColor(Site.muted).frame(width: 18, alignment: .trailing).monospacedDigit()
                Text(title).font(ManualPage.f(16, .medium)).foregroundColor(hover ? Site.head : Site.low).underline(hover)
            }.padding(.vertical, 4).contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hover = $0 }.linkCursor()
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
                    KeyLine(keys: ["⌘", "⇧", "E"], says: "Open the app from anywhere (and put it away)")
                    KeyLine(keys: ["⌘", "H"], says: "Hide the app; press again straight away to bring it back")
                    KeyLine(keys: ["⌘", "Q"], says: "Close the app. The menu keeps running")
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
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Site.ink.opacity(0.35), lineWidth: 1))
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
                            HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Site.ink.opacity(kept ? 0.55 : 0.25)).frame(width: 4, height: 4) } }
                            ForEach(0..<4, id: \.self) { l in
                                Capsule().fill(Site.ink.opacity(kept ? 0.4 : 0.14)).frame(width: r.2 * W * [0.7, 0.85, 0.5, 0.75][l] - 12, height: 3)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(6)
                        .frame(width: r.2 * W, height: r.3 * H, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(kept ? Site.surface2 : Site.surface))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Site.ink.opacity(kept ? 0.85 : 0.18), lineWidth: 1))
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
            ForEach(DesktopModel.gated ? Array(m.history.prefix(3)) : m.history) { s in
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
            if DesktopModel.gated && m.history.count > 3 { LockedPanel(m: m, text: "Free keeps your last 3 sessions. Pro keeps all \(m.history.count).") }
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
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Site.ink.opacity(selected ? 0.9 : 0), lineWidth: 1.5))
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
            if DesktopModel.gated { LockedPanel(m: m, text: "Tools are part of Pro: quit everything at once, restart clean, force quit what's frozen.") }
            SectionLabel("Analyse performance", divider: false).padding(.horizontal, -14)
            ToolLine(title: "Open Activity Monitor", why: "See which apps are using the most memory and processor right now.", tint: Site.head, enabled: !DesktopModel.gated) { f.openActivityMonitor() }
            ToolLine(title: "Open System Settings", why: "Change what opens at login, and the battery and display settings that affect how the Mac runs.", tint: Site.head, enabled: !DesktopModel.gated) { f.openSystemSettings() }
            SectionLabel("Quit Unresponsive Apps").padding(.horizontal, -14)
            ToolLine(title: "Quit All Apps…", why: "Close every app at once for a clean start. Each app saves first. Critical System Processes stay open.", tint: Site.head, enabled: !busy && !DesktopModel.gated) { f.quitAllApps() }
            ToolLine(title: "Quit All Apps & Restart Mac…", why: "Close everything, then restart. Clears memory completely when the Mac feels slow.", tint: Site.head, enabled: !busy && !DesktopModel.gated) { f.quitAllRestart() }
            ToolLine(title: "Force Quit All Apps…", why: "For apps that have frozen and won't quit. Unsaved work in them is lost, so it asks first.", tint: Site.hazard, enabled: !busy && !DesktopModel.gated) { f.forceQuitAllApps() }
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
            SettingLine(title: "This window", note: "Dark is the standard look. System follows your Mac.") {
                Choice(options: ["Light", "Dark", "System"], selected: Site.look) { i in desktop.setLook(i) }
            }
            SettingLine(title: "Menu", note: "The look of the menu bar menu.") {
                Choice(options: ["Dark", "Light"], selected: f.lightMenuSetting ? 1 : 0) { i in m.act { f.lightMenuSetting = i == 1 } }
            }
            SettingLine(title: "Menu headings", note: "How much the menu's headings explain.") {
                Choice(options: ["Minimalist", "Normal", "Verbose"], selected: f.headingStyle) { i in m.act { f.headingStyle = i } }
            }
            SettingLine(title: "Width", note: "Default leaves space either side of the page. Wide fills the window. Minimal makes the window itself smaller.") {
                Choice(options: ["Default", "Wide", "Minimal"], selected: DesktopView.trial.rawValue) { i in desktop.setWidth(i) }
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
                    let locked = DesktopModel.gated && (all.firstIndex { $0.0 == name } ?? 0) >= 3      // Free: 3 colour schemes
                    ColourTile(name: name, a: a, b: b, on: on) { if locked { m.openUpgrade() } else { m.act { f.iconColor = a; f.iconColor2 = a == b ? "" : b } } }
                        .opacity(locked ? 0.4 : 1)
                }
            }
            SettingLine(title: "Text colour", note: "The big button's text, to go with its colour.") {
                Choice(options: ["White", "Black"], selected: DesktopView.buttonInkWhite ? 0 : 1) { i in
                    m.act { UserDefaults.standard.set(i == 0, forKey: "desktopButtonInkWhite") }
                }
            }.padding(.top, 14)
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
            // Big enough that the sidebar never squashes: its rows, every mode (36 pt each), and the foot (with room for
            // Update available), measured off-screen; at least 1100 × 780, never more than the screen.
            let size = Self.defaultSize(modes: f.modes.count, screen: screen, minimal: DesktopView.trial == .minimal)
            let w = DesktopWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden; w.title = "Focus"
            Self.applyLook(to: w)
            w.isMovableByWindowBackground = false; w.isReleasedWhenClosed = false   // drag the top strip to move it: rows are for dragging apps
            w.minSize = NSSize(width: 600, height: 420)
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
            item(m, "Upgrade to Pro…", #selector(upgrade))
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
            m.addItem(.separator())
            // View As: the window as a Free, Pro or Max user sees it (badge, Buy button, weekly count, Pro tags).
            // Only the look changes: nothing is bought or unlocked. "Actual" goes back to this copy's own licence.
            let viewAs = NSMenuItem(title: "View As", action: nil, keyEquivalent: ""), sub = NSMenu(title: "View As")
            let now = UserDefaults.standard.string(forKey: "desktopViewAs") ?? ""
            for (title, key) in [("Actual", ""), ("Free", "free"), ("Pro", "pro"), ("Max", "max")] {
                let i = sub.addItem(withTitle: title, action: #selector(viewAs(_:)), keyEquivalent: "")
                i.target = self; i.representedObject = key; i.state = now == key ? .on : .off
            }
            viewAs.submenu = sub; m.addItem(viewAs)
            let dev = m.addItem(withTitle: "Developer Panel", action: #selector(toggleDevPanel(_:)), keyEquivalent: ""); dev.target = self
            dev.state = (UserDefaults.standard.object(forKey: "desktopDevPanel") as? Bool ?? true) ? .on : .off
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
    /// Settings ▸ Appearance ▸ Width. Into or out of Minimal, the window narrows or widens by a sidebar's width,
    /// keeping its left edge where it is.
    static func defaultSize(modes: Int, screen: NSRect, minimal: Bool) -> NSSize {
        let devPanel: CGFloat = (UserDefaults.standard.object(forKey: "desktopDevPanel") as? Bool ?? true) ? 90 : 0   // View As, when shown
        let sidebar = 600 + 36 * CGFloat(modes + 1) + 44 + devPanel
        return NSSize(width: max(600, min(1100, screen.width - 120) - (minimal ? DesktopView.minimalCut : 0)),
                      height: max(420, min(max(780, sidebar), screen.height - 60)))
    }
    /// Settings ▸ Appearance ▸ This window. The window's own frame and controls follow at once.
    func setLook(_ i: Int) { UserDefaults.standard.set(i, forKey: "desktopLook"); if let w = window { Self.applyLook(to: w) }; model?.tick &+= 1 }
    static func applyLook(to w: NSWindow) {
        w.backgroundColor = Site.light ? .white : .black
        w.appearance = Site.look == 2 ? nil : NSAppearance(named: Site.light ? .aqua : .darkAqua)   // System: follow macOS
    }
    @objc func upgrade() { model?.openUpgrade() }
    /// Pro and Max say "Pro"/"Max" only beside the name: the Upgrade item hides for them.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(upgrade) { item.isHidden = DesktopModel.licensed }
        return true
    }
    @objc func toggleDevPanel(_ sender: NSMenuItem) {
        let on = !(UserDefaults.standard.object(forKey: "desktopDevPanel") as? Bool ?? true)
        UserDefaults.standard.set(on, forKey: "desktopDevPanel"); sender.state = on ? .on : .off; model?.tick &+= 1
    }
    @objc func viewAs(_ sender: NSMenuItem) {
        let key = sender.representedObject as? String ?? ""
        if key.isEmpty { UserDefaults.standard.removeObject(forKey: "desktopViewAs") } else { UserDefaults.standard.set(key, forKey: "desktopViewAs") }
        sender.menu?.items.forEach { $0.state = ($0.representedObject as? String ?? "") == key ? .on : .off }
        model?.tick &+= 1
    }
    func setWidth(_ i: Int) {
        let was = DesktopView.trial
        UserDefaults.standard.set(i, forKey: "desktopWidthV2"); model?.tick &+= 1
        let d = DesktopView.minimalDelta(was: was, now: DesktopView.trial)
        if d != 0, let w = window {
            var f = w.frame; f.size.width = max(w.minSize.width, f.size.width + d)
            w.setFrame(f, display: true, animate: true)
        }
    }
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
    if let n = renderArgs.first(where: { $0.hasPrefix("modes=") }).flatMap({ Int($0.dropFirst(6)) }) {
        f.modes = []                                              // a given number of modes (sizing checks)
        for i in 0..<n { f.createMode("Mode \(i + 1)", apps: have(["com.apple.TextEdit", "com.apple.Safari"])) }
    }
    f.neverClose = have(["com.apple.Terminal"]); f.excluded = have(["com.apple.Safari", "com.apple.Terminal"])
    let m = DesktopModel(f); m.still = true; m.refresh(); if mode { m.selection = second }
    if renderArgs.contains("feedback") { m.openFeedback() }
    if renderArgs.contains("upgrade") { m.upgradeShown = true }
    if renderArgs.contains("live") {
        f.sessions = [["date": Date(), "name": "Research", "mode": "Research", "modeID": second, "kept": have(["com.apple.Safari"]), "apps": [["path": "/System/Applications/Notes.app", "id": "com.apple.Notes"]]]]
        f.store.set(true, forKey: "focused")
    }
    for p in [Page.settings, Page.shortcuts, Page.tools, Page.history, Page.manual] where renderArgs.contains(String(p.dropFirst())) { m.selection = p }
    if !renderArgs.contains("live") { f.sessions = [["date": Date().addingTimeInterval(-3600), "kept": have(["com.apple.Safari"]), "apps": [["path": "/System/Applications/Notes.app"]]]] }
    if renderArgs.contains("hover") { SessionButton.still = (true, 0, false) }
    if let a = renderArgs.first(where: { $0.hasPrefix("line=") }), let t = Double(a.dropFirst(5)) {
        SessionButton.still = (false, CGFloat(abs(t)), false) }
    if let c = renderArgs.first(where: { $0.hasPrefix("colour=") }) {          // e.g. colour=8B5CF6 or colour=8B5CF6,F472B6
        let p = c.dropFirst(7).split(separator: ","); f.store.set(String(p[0]), forKey: "iconColor"); f.store.set(p.count > 1 ? String(p[1]) : "", forKey: "iconColor2")
    }
    DesktopView.renderTrial = nil                                 // each render starts from the saved Width
    if renderArgs.contains("trial=narrow") { DesktopView.renderTrial = .narrow }
    if renderArgs.contains("trial=wide") { DesktopView.renderTrial = .wide }
    if renderArgs.contains("trial=minimal") { DesktopView.renderTrial = .minimal }
    m.update = ("9.9.9", DesktopModel.releasePage)               // so the Update button's place can be checked
    var size = renderArgs.contains("wide") ? NSSize(width: 1320, height: 880)
        : NSSize(width: 1000, height: renderArgs.first { $0.hasPrefix("h=") }.flatMap { Double($0.dropFirst(2)) }.map { CGFloat($0) }
                                       ?? (renderArgs.contains("tall") ? 1500 : 730))
    if DesktopView.trial == .minimal { size.width -= DesktopView.minimalCut }
    if let w = renderArgs.first(where: { $0.hasPrefix("w=") }).flatMap({ Double($0.dropFirst(2)) }) { size.width = CGFloat(w) }
    let host = NSHostingView(rootView: DesktopView(m: m).frame(width: size.width, height: size.height))
    let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    w.appearance = NSAppearance(named: Site.light ? .aqua : .darkAqua); w.contentView = host
    host.frame = NSRect(origin: .zero, size: size); host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: file))
    }
    f.modes = []; UserDefaults.standard.removePersistentDomain(forName: suite)
}

// MARK: the desktop app's own tests — `Focus --selftest-gui`
// Off-screen only: nothing is shown, no session is started, no app is closed. Safe to run while he's at the Mac.
// Each check prints "gui: PASS|FAIL  n. what — detail"; the exit code is the number of failures.

/// Renders the window off-screen with the given render options and returns the picture (2× pixels).
private func guiRender(_ opts: [String]) -> NSBitmapImageRep? {
    let file = NSTemporaryDirectory() + "focus-gui-\(UUID().uuidString).png"
    let saved = renderArgs
    renderArgs = ["Focus", "--render-desktop", file] + opts
    defer { renderArgs = saved; try? FileManager.default.removeItem(atPath: file) }
    renderDesktop(to: file, mode: opts.contains("mode"))
    return NSBitmapImageRep(data: (try? Data(contentsOf: URL(fileURLWithPath: file))) ?? Data())
}
private func lum(_ r: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat {
    guard let c = r.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return 0 }
    return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
}
/// In the sidebar (points 20…280 across): the top of the first full-width white button below `from`, and the bottom
/// of the last drawn thing above it. Their distance is the slack the sidebar has: below a few points, it's squashed.
private func sidebarSlack(_ r: NSBitmapImageRep, from: CGFloat = 300, light: Bool = false) -> (gap: CGFloat, buyTop: CGFloat)? {
    let s = CGFloat(r.pixelsWide) / 1000.0 * (1000.0 / max(1, CGFloat(r.size.width)))   // pixels per point
    let px = { (p: CGFloat) in Int(p * s) }
    let xs = Array(stride(from: px(20), to: px(280), by: 4))
    func white(_ y: Int) -> Bool { xs.filter { light ? lum(r, $0, y) < 0.07 : lum(r, $0, y) > 0.93 }.count > Int(Double(xs.count) * 0.8) }   // the solid (ink) button
    guard let buy = (px(from)..<r.pixelsHigh).first(where: white) else { return nil }
    // the largest empty stretch between the rows and the foot (the View As panel sits just above the foot, so the
    // room shows up between the modes and it rather than right above the button)
    var best = 0, run = 0
    for y in px(from)..<max(px(from), buy - 2) {
        if xs.contains(where: { light ? lum(r, $0, y) < 0.76 : lum(r, $0, y) > 0.24 }) { best = max(best, run); run = 0 } else { run += 1 }
    }
    best = max(best, run)
    return (CGFloat(best) / s, CGFloat(buy) / s)
}

func guiSelfTest(only: Set<Int>?) -> Int32 {
    _ = NSApplication.shared
    var failures = 0
    func check(_ n: Int, _ name: String, _ ok: Bool, _ detail: String) {
        guard only == nil || only!.contains(n) else { return }
        if !ok { failures += 1 }
        print("gui: \(ok ? "PASS" : "FAIL")  \(n). \(name) — \(detail)")
    }
    let std = UserDefaults.standard
    // Settings that some checks change, put back afterwards.
    let keep = ["desktopWidthV2", "desktopTextScale", "focusPro", "focusTier", "desktopButtonInkWhite", "desktopViewAs", "desktopLook"].map { ($0, std.object(forKey: $0)) }
    defer { for (k, v) in keep { if let v { std.set(v, forKey: k) } else { std.removeObject(forKey: k) } }; Site.scale = CGFloat(std.double(forKey: "desktopTextScale") == 0 ? 1 : std.double(forKey: "desktopTextScale")) }
    std.removeObject(forKey: "desktopWidthV2"); std.removeObject(forKey: "focusPro"); std.removeObject(forKey: "desktopButtonInkWhite")
    std.removeObject(forKey: "desktopViewAs"); std.removeObject(forKey: "focusTier"); std.removeObject(forKey: "desktopLook")

    // 1. The window opens big enough for the sidebar: for 0…6 modes, drawn at the size it opens at on a 14" MacBook
    //    screen, the sidebar keeps slack between its last row and the foot.
    let screen = NSRect(x: 0, y: 0, width: 1512, height: 945)
    var worst: (Int, CGFloat) = (-1, .infinity), missing = [Int]()
    for look in ["dark", "light"] { for n in [0, 2, 4, 6] {
        let size = DesktopController.defaultSize(modes: n, screen: screen, minimal: false)
        guard let r = guiRender(["modes=\(n)", "w=\(Int(size.width))", "h=\(Int(size.height))", "trial=narrow", "look=\(look)"]),
              let sl = sidebarSlack(r, light: look == "light") else { missing.append(n); continue }
        if sl.gap < worst.1 { worst = (n, sl.gap) }
    } }
    check(1, "sidebar never squashed at the opening size", missing.isEmpty && worst.1 >= 12,
          missing.isEmpty ? "Light and Dark: least slack \(Int(worst.1)) pt (with \(worst.0) modes)" : "no foot found with \(missing) modes")

    // 2. The opening size stays on screen and is never smaller than the window allows, on small and large screens.
    let screens = [NSRect(x: 0, y: 0, width: 1280, height: 775), screen, NSRect(x: 0, y: 0, width: 2560, height: 1415)]
    let sizes = screens.flatMap { sc in [false, true].flatMap { mini in [0, 4, 10].map { (sc, DesktopController.defaultSize(modes: $0, screen: sc, minimal: mini)) } } }
    let bad = sizes.filter { sc, sz in sz.width > sc.width || sz.height > sc.height || sz.width < 600 || sz.height < 420 }
    let big = DesktopController.defaultSize(modes: 4, screen: screens[2], minimal: false)
    check(2, "opening size fits the screen", bad.isEmpty && big.width >= 1100 && big.height >= 780,
          bad.isEmpty ? "all \(sizes.count) cases fit; large screen opens at \(Int(big.width)) × \(Int(big.height))" : "\(bad.count) off-screen or too small")

    // 3. Width: Default leaves equal margins, Wide and Minimal fill; only Minimal changes the window, by a sidebar.
    var insets = [String]()
    DesktopView.renderTrial = nil
    for (i, t) in [(0, DesktopView.Trial.narrow), (1, .wide), (2, .minimal)] {
        std.set(i, forKey: "desktopWidthV2")
        let e = DesktopView(m: DesktopModel(Focus(store: UserDefaults(suiteName: "com.labern.focus.selftest")!))).pageInsets
        insets.append("\(t)=\(Int(e.lead))/\(Int(e.trail))")
    }
    std.removeObject(forKey: "desktopWidthV2")
    let deltas = [DesktopView.minimalDelta(was: .narrow, now: .minimal), DesktopView.minimalDelta(was: .minimal, now: .wide), DesktopView.minimalDelta(was: .wide, now: .narrow)]
    check(3, "Width options", insets == ["narrow=36/36", "wide=0/0", "minimal=0/0"] && deltas == [-292, 292, 0] && DesktopView.trial == .narrow,
          "\(insets.joined(separator: " ")); window change \(deltas.map { Int($0) }); unset = \(DesktopView.trial)")

    // 4. Text size: one stop is one ⌘+; the label says how far from Default; it stops at 0.8 and 1.6.
    let labels = [1.0, 1.2, 0.9, 1.6].map { TextSizeStepper.label(CGFloat($0)) }
    desktop.setScale(1); for _ in 0..<12 { desktop.biggerText() }; let top = Site.scale
    for _ in 0..<20 { desktop.smallerText() }; let bottom = Site.scale; desktop.setScale(1)
    check(4, "text size steps", labels == ["Default", "Default +2", "Default −1", "Default +6"] && abs(top - 1.6) < 0.001 && abs(bottom - 0.8) < 0.001,
          "labels \(labels); clamps at \(top) and \(bottom)")

    // 5. The session line starts at the top centre, sets off anticlockwise (left along the top), and ends 2 pt past
    //    its start so the ends meet.
    var pts = [CGPoint]()
    DrawnEdge(radius: 22).path(in: CGRect(x: 0, y: 0, width: 400, height: 76)).forEach { el in
        switch el { case .move(let p), .line(let p): pts.append(p); case .quadCurve(let p, _), .curve(let p, _, _): pts.append(p); default: break }
    }
    check(5, "session line path", pts.count > 3 && pts[0] == CGPoint(x: 200, y: 0) && pts[1].x < 200 && pts[1].y == 0 && abs(pts.last!.x - 198) < 0.01 && pts.last!.y == 0,
          "starts \(pts.first.map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "-"), heads to x=\(pts.count > 1 ? Int(pts[1].x) : -1), ends x=\(pts.last.map { String(format: "%.0f", $0.x) } ?? "-")")

    // 6. The Buy button's words, in the wording he chose (5), singular and plural.
    let buy14 = BuyLabel.words(days: 14, style: BuyLabel.style), buy1 = BuyLabel.words(days: 1, style: BuyLabel.style)
    check(6, "Buy button words", buy14 == "14 Days of Pro Left — Upgrade Now" && buy1 == "1 Day of Pro Left — Upgrade Now", "\"\(buy14)\" / \"\(buy1)\"")

    // 7. Pressure squares: the same number each side, all between the edge and the title, clear of the key; still
    //    at least one each side on the narrowest button (Minimal at the smallest window).
    var sq = [String](), sqOK = true
    for (w, title) in [(CGFloat(1060), CGFloat(210)), (CGFloat(640), CGFloat(210)), (CGFloat(400), CGFloat(140))] {
        let s = PressureDots.slots(width: w, titleWidth: title)
        let l = s.left, r = s.right, inner = w / 2 - title / 2
        let ok = l.count == r.count && l.count >= 1 && l.allSatisfy { $0 >= PressureDots.edgeL && $0 < inner } &&
                 r.allSatisfy { $0 > w / 2 + title / 2 && $0 <= w - PressureDots.keyRoom }
        sqOK = sqOK && ok; sq.append("\(Int(w))pt: \(l.count)+\(r.count)")
    }
    check(7, "pressure squares symmetric and clear", sqOK, sq.joined(separator: ", "))

    // 8. Focus Pro: the purchase flag is read live; set, the top left gains the white "Pro" box beside the name.
    std.set("max", forKey: "focusTier"); let maxTier = DesktopModel.tier == .max; std.removeObject(forKey: "focusTier")
    std.set(true, forKey: "focusPro"); let on = DesktopModel.licensed && DesktopModel.tier == .pro
    var proBox = true
    for look in ["dark", "light"] {                                  // the box is ink: white in Dark, black in Light
        guard let r = guiRender(["trial=narrow", "look=\(look)"]) else { proBox = false; continue }
        let s = CGFloat(r.pixelsWide) / 1000
        proBox = proBox && (Int(190 * s)..<Int(260 * s)).contains { x in look == "dark" ? lum(r, x, Int(63 * s)) > 0.93 : lum(r, x, Int(63 * s)) < 0.07 }
    }
    std.removeObject(forKey: "focusPro"); let off = DesktopModel.licensed || renderArgs.contains("licensed")
    check(8, "Focus Pro / Max from the purchase", on && !off && maxTier && proBox, "Pro flag on → \(on), off → \(off); Max read → \(maxTier); box by the name in Light and Dark: \(proBox)")

    // 9. Button colour and text colour: the Appearance colour reaches the big button, and Text colour is obeyed.
    let violet = hexColor("8B5CF6")?.usingColorSpace(.sRGB)
    std.set(true, forKey: "desktopButtonInkWhite"); let inkWhite = DesktopView.buttonInkWhite
    std.removeObject(forKey: "desktopButtonInkWhite"); let inkBlack = !DesktopView.buttonInkWhite
    var tinted = true
    for look in ["dark", "light"] {                                  // his colour wins in either look
        guard let r = guiRender(["colour=8B5CF6", "trial=narrow", "look=\(look)"]) else { tinted = false; continue }
        let s = CGFloat(r.pixelsWide) / 1000, c = r.colorAt(x: Int(400 * s), y: Int(45 * s))?.usingColorSpace(.sRGB)
        tinted = tinted && (c.map { abs($0.redComponent - 0.545) < 0.06 && abs($0.blueComponent - 0.965) < 0.06 } ?? false)
    }
    check(9, "button colour and text colour", violet != nil && inkWhite && inkBlack && tinted, "violet parsed \(violet != nil); text white/black \(inkWhite)/\(inkBlack); button drawn violet in Light and Dark \(tinted)")

    // 10. The Manual: nine sections, Contents numbered down (1–5, then 6–9); none of the wording he's removed.
    let secs = ManualPage.sections
    var text = [String]()
    for b in ManualPage.blocks {
        switch b { case .heading(let t), .text(let t): text.append(t); case .bullets(let a): text += a; case .figure(_, let c): text.append(c); case .link(let t, _): text.append(t) }
    }
    let banned = ["this window", "Then F.", "Then E.", "Click to", "trial"].filter { w in text.contains { $0.localizedCaseInsensitiveContains(w) } }
    check(10, "Manual sections and wording", secs.count == 9 && (secs.count + 1) / 2 == 5 && banned.isEmpty,
          "\(secs.count) sections, first column \((secs.count + 1) / 2); banned wording found: \(banned.isEmpty ? "none" : banned.joined(separator: ", "))")

    // 11. Modes reorder without starting anything: dragging changes the order the window (and menu) lists.
    let f = Focus(store: UserDefaults(suiteName: "com.labern.focus.selftest")!); f.modes = []
    let a = f.createMode("A", apps: []), b = f.createMode("B", apps: []), c = f.createMode("C", apps: [])
    f.moveMode(c, before: a)
    let order = DesktopModel(f).modes.map(\.name)
    check(11, "modes reorder, nothing starts", order == ["C", "A", "B"] && !f.focused, "order \(order); in a session: \(f.focused)")
    _ = b; f.modes = []; UserDefaults.standard.removePersistentDomain(forName: "com.labern.focus.selftest")

    // 12. Every page draws, at the smallest window and in each width, without coming out blank.
    var blank = [String]()
    for page in ["", "live", "mode", "settings", "shortcuts", "tools", "history", "manual", "feedback"] {
        for opts in [["w=600", "h=420", "trial=minimal"], ["trial=narrow"], ["trial=wide"]] { for look in ["dark", "light"] {
            guard let r = guiRender((page.isEmpty ? [] : [page]) + opts + ["look=\(look)"]) else { blank.append("\(page.isEmpty ? "session" : page)/\(opts.last!)/\(look)"); continue }
            let s = CGFloat(r.pixelsWide) / CGFloat(max(1, r.size.width))
            let lit = stride(from: 0, to: r.pixelsWide, by: Int(20 * s)).filter { x in stride(from: 0, to: r.pixelsHigh, by: Int(20 * s)).contains { look == "dark" ? lum(r, x, $0) > 0.5 : lum(r, x, $0) < 0.5 } }.count
            if lit < 3 { blank.append("\(page.isEmpty ? "session" : page)/\(opts.last!)/\(look)") }
        } }
    }
    check(12, "every page draws in every width", blank.isEmpty, blank.isEmpty ? "9 pages × 3 widths × Light and Dark" : "blank: \(blank.joined(separator: ", "))")

    // 13. The session button's mark and title: in a session the Focus mark sits right of the title, out of it.
    var mark = true
    for look in ["dark", "light"] {                                  // paper-coloured mark on the ink button
        guard let r = guiRender(["live", "trial=narrow", "look=\(look)"]) else { mark = false; continue }
        let s = CGFloat(r.pixelsWide) / 1000
        mark = mark && (Int(780 * s)..<Int(840 * s)).contains { x in look == "dark" ? lum(r, x, Int(61 * s)) < 0.2 : lum(r, x, Int(61 * s)) > 0.8 }
    }
    check(13, "Focus mark on the button in a session", mark, "mark found right of the title in Light and Dark: \(mark)")

    // 14. Light and Dark: every page draws on its own ground — white in Light, black in Dark — with readable ink on it.
    var wrong = [String]()
    for look in ["light", "dark"] {
        for page in ["", "live", "settings", "tools", "manual"] {          // (Feedback shades the page on purpose)
            guard let r = guiRender((page.isEmpty ? [] : [page]) + ["look=\(look)", "trial=narrow"]) else { wrong.append("\(look)/\(page)"); continue }
            let s = CGFloat(r.pixelsWide) / 1000
            let ground = lum(r, Int(990 * s), Int(720 * s))                      // the bottom-right corner is bare ground
            let inked = stride(from: Int(320 * s), to: r.pixelsWide, by: 6).contains { x in abs(lum(r, x, Int(164 * s)) - ground) > 0.6 }   // the panel title
            if (look == "light" ? ground < 0.95 : ground > 0.05) || !inked { wrong.append("\(look)/\(page.isEmpty ? "session" : page)") }
        }
    }
    check(14, "Light and Dark draw correctly", wrong.isEmpty, wrong.isEmpty ? "5 pages × 2 looks: right ground, readable title" : "wrong: \(wrong.joined(separator: ", "))")

    // 15. Free's weekly sessions: counted since Monday 00:00 (Quit All clean-ups don't count), resetting next Monday.
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/London")!
    let wed = cal.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 15))!          // a Wednesday
    let mon = cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 0, minute: 5))!
    let sun = cal.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 23))!          // last week
    let fake: [[String: Any]] = [["date": mon], ["date": wed.addingTimeInterval(-60)], ["date": wed.addingTimeInterval(-30), "kind": "quit all"], ["date": sun]]
    let wk = DesktopModel.week(fake, now: wed, calendar: cal)
    let resetOK = cal.dateComponents([.weekday, .hour, .minute], from: wk.reset) == DateComponents(hour: 0, minute: 0, weekday: 2)
    let full = DesktopModel.week((0..<14).map { _ in ["date": wed.addingTimeInterval(-10)] }, now: wed, calendar: cal).left
    check(15, "Free's weekly sessions", wk.used == 2 && wk.left == 8 && wk.resetDay == "Monday" && resetOK && full == 0,
          "used \(wk.used), left \(wk.left), resets \(wk.resetDay) 00:00 \(resetOK); never below 0: \(full)")

    // 16. View As: Free, Pro and Max each change what the window shows, and Actual goes back to the real licence.
    var seen = [String]()
    for k in ["free", "pro", "max", ""] {
        if k.isEmpty { std.removeObject(forKey: "desktopViewAs") } else { std.set(k, forKey: "desktopViewAs") }
        seen.append("\(k.isEmpty ? "actual" : k)=\(DesktopModel.tier)/\(DesktopModel.licensed ? "paid" : "free")")
    }
    std.removeObject(forKey: "desktopViewAs")
    check(16, "View As Free / Pro / Max", seen == ["free=free/free", "pro=pro/paid", "max=max/paid", "actual=free/free"], seen.joined(separator: ", "))

    // ——— Pricing: pricing.json is the one source; the app must follow it and keep to his rules ———
    let pr = Pricing.bundled
    // 17. His price rules hold in the shipped copy: Free / Pro / Max with their taglines, monthly £5 / £10, once = 10×
    //     monthly, round numbers only (5s and 0s), 14 days of Pro, Free at 10 sessions a week, Pro the one marked best.
    var rules = [String]()
    if let p = pr {
        if ["free", "pro", "max"].map({ p.tiers[$0]?.name ?? "" }) != ["Free", "Pro", "Max"] { rules.append("tier names") }
        if p.tiers.values.contains(where: { $0.tagline.isEmpty }) { rules.append("a tagline is empty") }
        if p.tiers["pro"]?.monthly != 5 || p.tiers["max"]?.monthly != 10 || p.tiers["free"]?.monthly != 0 { rules.append("monthly prices") }
        for k in ["pro", "max"] { if let t = p.tiers[k], t.once != t.monthly * 10 { rules.append("\(k) once ≠ 10× monthly") } }
        let all = p.tiers.values.flatMap { [$0.monthly] + ($0.once.map { [$0] } ?? []) }
        if all.contains(where: { $0 % 5 != 0 }) { rules.append("a price that isn't a round number") }
        if p.trial_days != 14 || p.trial_tier != "pro" { rules.append("trial") }
        if p.free_sessions_per_week != 10 { rules.append("Free sessions a week") }
        if p.tiers["pro"]?.best != true || p.tiers["max"]?.best == true { rules.append("Pro not the best value") }
        if p.lead.tier != "pro" || p.lead.plan != "monthly" { rules.append("lead isn't Pro monthly") }
    } else { rules.append("pricing.json missing or unreadable") }
    check(17, "pricing rules", rules.isEmpty, rules.isEmpty ? "Free/Pro/Max; £0/£5/£10 a month; £50/£100 once (10×); round; 14 days of Pro; Free 10 a week; Pro is best value" : rules.joined(separator: "; "))

    // 18. The app takes its numbers from pricing.json, never its own: the weekly count, the Preview's days, the
    //     Upgrade window's prices, and the checkout link for each plan.
    let co = Pricing.checkout(tier: "pro", plan: "once").absoluteString
    let usesFile = pr.map { DesktopModel.freeWeekly == $0.free_sessions_per_week && DesktopModel.trialDaysLeft == $0.trial_days } ?? false
    check(18, "the app uses pricing.json", usesFile && co == "https://paradoxica.uk/focus/checkout/?tier=pro&plan=once",
          "weekly count and Preview days from the file: \(usesFile); checkout link \(co)")

    // 19. The shipped copy matches the live site (paradoxica.uk/focus/pricing.json). A difference means the site has
    //     moved on: refresh focus/pricing.json and release. Offline: noted, not failed.
    var live: Any?, liveNote = "offline: not compared"
    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: URLRequest(url: Pricing.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)) { d, _, _ in
        live = d.flatMap { try? JSONSerialization.jsonObject(with: $0) }; sem.signal()
    }.resume()
    _ = sem.wait(timeout: .now() + 12)
    let shipped = (try? Data(contentsOf: Bundle.main.url(forResource: "pricing", withExtension: "json") ?? URL(fileURLWithPath: "pricing.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) }
    var same = true
    if let l = live as? NSDictionary, let b = shipped as? NSDictionary { same = l.isEqual(b); liveNote = same ? "identical to the live site" : "the live site differs: refresh focus/pricing.json" }
    check(19, "shipped prices match the site", same, liveNote)

    // 20. The Pro tags in the app match the site's table: Tools, Modes, History and custom shortcuts are limited or
    //     absent on Free and present on Pro and Max; sessions a week is the Free figure on Free and Unlimited on Pro.
    var table = [String: [Pricing.Cell]]()
    pr?.features.forEach { g in g.rows.forEach { r in if case .text(let name) = r.first { table[name] = Array(r.dropFirst()) } } }
    func row(_ starts: String) -> [Pricing.Cell]? { table.first { $0.key.hasPrefix(starts) }?.value }
    func freeLimited(_ c: [Pricing.Cell]?) -> Bool { guard let c, c.count == 3 else { return false }
        if case .yes(true) = c[0] { return false }; if case .yes(false) = c[1] { return false }; if case .yes(false) = c[2] { return false }; return true }
    let tagged = ["Tools", "Modes", "History", "Custom shortcuts"].filter { !freeLimited(row($0)) }
    var weekly = false
    if let w = row("Sessions a week"), w.count == 3, case .text(let f0) = w[0], case .text(let f1) = w[1] { weekly = pr.map { $0.fill(f0) } == "10" && f1 == "Unlimited" }
    check(20, "Pro tags match the site's table", tagged.isEmpty && weekly, tagged.isEmpty ? "Tools, Modes, History, custom shortcuts: limited on Free, in Pro and Max; sessions a week 10 / Unlimited: \(weekly)" : "not limited on Free in the table: \(tagged.joined(separator: ", "))")

    // 21. The Upgrade window draws in Light and Dark with all three plans, and Free locks (View As) show their panel.
    var upOK = true
    for look in ["dark", "light"] {
        guard let r = guiRender(["upgrade", "trial=narrow", "look=\(look)"]) else { upOK = false; continue }
        let s = CGFloat(r.pixelsWide) / 1000
        // the Pro card's solid button sits in the middle of the window, in ink
        upOK = upOK && (Int(440 * s)..<Int(560 * s)).contains { x in (Int(380 * s)..<Int(520 * s)).contains { y in look == "dark" ? lum(r, x, y) > 0.93 : lum(r, x, y) < 0.07 } }
    }
    let lockPic = guiRender(["tools", "tier=free", "viewas=free", "trial=narrow"])
    var locked = false
    if let r = lockPic { let s = CGFloat(r.pixelsWide) / 1000; locked = (Int(780 * s)..<Int(930 * s)).contains { x in lum(r, x, Int(262 * s)) > 0.93 } }   // the panel's Upgrade Now
    check(21, "Upgrade window and Free locks", upOK && locked, "Upgrade window in Light and Dark: \(upOK); Tools locked with Upgrade Now as Free: \(locked)")

    print("gui: \(failures == 0 ? "all passed" : "\(failures) failed")")
    return Int32(failures)
}
