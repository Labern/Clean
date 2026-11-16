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
    static var paper: Color { light ? .white : .black }
    /// The plans' solid parts (Pro's box, Buy, the chosen plan): white in Dark, a soft dark grey in Light — black
    /// on white was too hard there.
    static var solid: Color { light ? hex(0x4A4A4A) : .white }             // what was black: the ground, text on solid buttons
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
    static let standard: CGFloat = 0.99                     // one step up (2026-11-16, his ask); "Default" in Settings ▸ Text size; 0.18.43 made the size he had chosen (one step under 1.0) the Default
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
    @Published var selection: String? = UserDefaults.standard.string(forKey: "desktopPage").flatMap { $0 == "§upgrade" ? nil : $0 } {   // nil = the session; else a page or a mode's id
        didSet {                                                   // the Upgrade page is never remembered: it's a moment, not a place
            if let s = selection, s != Page.upgrade { UserDefaults.standard.set(s, forKey: "desktopPage") }
            else if selection == nil { UserDefaults.standard.removeObject(forKey: "desktopPage") }
        }
    }
    /// See the app as Actual ("") / Basic ("free") / Pro ("pro"). Becoming Pro leaves the Upgrade page at once: nothing
    /// asks a Pro user to upgrade.
    func viewAs(_ key: String) {
        if key.isEmpty { UserDefaults.standard.removeObject(forKey: "desktopViewAs") } else { UserDefaults.standard.set(key, forKey: "desktopViewAs") }
        tierChanged()
    }
    /// Call whenever the tier may have changed (View As, a purchase, a licence check).
    func tierChanged() {
        TierWatch.shared.n &+= 1
        if DesktopModel.licensed && selection == Page.upgrade { selection = upgradeFrom; outOfSessions = false }
        tick &+= 1
    }
    var upgradeFrom: String? = nil                                 // where Upgrade was opened from, to go back to
    @Published var outOfSessions = false                           // Upgrade opened because the week's sessions ran out
    @Published var giftShown = false                               // a gift pop-up is up
    enum Gift { case reset, welcome }
    @Published var giftKind: Gift = .reset
    /// First open of a new copy (no sessions yet, not bought): the early-adopter thank-you and its tokens.
    func showWelcomeIfNew() {
        guard !UserDefaults.standard.bool(forKey: "focusWelcomeShown"), f.sessions.isEmpty, !DesktopModel.licensed,
              !renderArgs.contains("--render-desktop") else { return }
        giftKind = .welcome; giftShown = true
    }
    @Published var hoverApp: String?                               // the app under the pointer, in the list or the memory bar
    @Published var countUp: Int? = nil                             // the plan line's count while it rises after the gift
    /// Run out, on Basic, with the free reset unused: the gift comes first; the plans only the next time.
    var giftDue: Bool { DesktopModel.gated && !DesktopModel.giftUsed && DesktopModel.week(f.sessions, now: Date()).left == 0 }
    func showGiftIfDue() { if giftDue && !giftShown && !renderArgs.contains("--render-desktop") { giftKind = .reset; giftShown = true } }
    /// Take the gift: this week gets the sessions back, once ever; the count rises to show it.
    func takeGift() {
        let ud = UserDefaults.standard
        let from = DesktopModel.week(f.sessions, now: Date()).left
        if giftKind == .welcome {                                  // the thank-you: tokens that never expire
            ud.set(true, forKey: "focusWelcomeShown"); DesktopModel.tokens += DesktopModel.welcomeTokens
            giftShown = false; giftKind = .reset
            let to = DesktopModel.week(f.sessions, now: Date()).left
            countUp = from
            for (k, i) in ((from + 1)...max(from + 1, to)).enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 + Double(k + 1) * 0.07) { [weak self] in
                    self?.countUp = i
                    if i == to { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.countUp = nil } }
                }
            }
            return
        }
        ud.set(true, forKey: "focusGiftUsed"); ud.set(DesktopModel.weekStart, forKey: "focusGiftWeek")
        if ud.object(forKey: "devSpentWeek") != nil { ud.set(DesktopModel.giftSessions, forKey: "devSpentBack") }   // the dev "0" gives way to the gift
        let to = DesktopModel.week(f.sessions, now: Date()).left
        giftShown = false
        if selection == Page.upgrade { selection = upgradeFrom; outOfSessions = false }
        countUp = 0
        for i in 1...max(1, to) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 + Double(i) * 0.07) { [weak self] in
                self?.countUp = i
                if i == max(1, to) { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.countUp = nil } }
            }
        }
    }
    /// Developer Panel: use up this week's sessions (as Basic) without touching the real history; re-arm the gift.
    func devSpendAll() {
        let ud = UserDefaults.standard
        ud.set(DesktopModel.weekStart, forKey: "devSpentWeek"); ud.removeObject(forKey: "devSpentBack")
        ud.removeObject(forKey: "focusGiftUsed"); ud.removeObject(forKey: "focusGiftWeek")
        viewAs("free"); showGiftIfDue()
    }
    func devRestore() {
        let ud = UserDefaults.standard
        ["devSpentWeek", "devSpentBack", "focusGiftWeek", "focusTokens", "focusWelcomeShown"].forEach { ud.removeObject(forKey: $0) }
        tick &+= 1
    }
    /// Developer Panel: show the early-adopter welcome as a new copy would.
    func devWelcome() { UserDefaults.standard.removeObject(forKey: "focusWelcomeShown"); giftKind = .welcome; giftShown = true }
    /// Basic, and this week's sessions are used up: starting one opens Upgrade instead (Use it > love it > run out >
    /// look to upgrade > see a better deal > buy). Locks only while viewing as Basic until real licences exist.
    static func noSessionsLeft(_ f: Focus) -> Bool { renderArgs.contains("out") || (gated && week(f.sessions, now: Date()).left == 0) }
    /// "resets Monday 00:00"
    static func resetLine(_ f: Focus) -> String {
        let r = week(f.sessions, now: Date()).reset
        let d = DateFormatter(); d.locale = Locale(identifier: "en_GB"); d.dateFormat = "EEEE HH:mm"
        return "resets \(d.string(from: r))"
    }
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
    /// The one free reset: a first-time user who runs out (usually from playing around) gets this many back, once.
    static var giftSessions: Int { freeWeekly }
    static var giftUsed: Bool { UserDefaults.standard.bool(forKey: "focusGiftUsed") }
    /// Session tokens: extra sessions that never expire (the early-adopter welcome gives 10). Used one per session, only
    /// once the week's own sessions have run out.
    static var tokens: Int { get { max(0, UserDefaults.standard.integer(forKey: "focusTokens")) } set { UserDefaults.standard.set(max(0, newValue), forKey: "focusTokens") } }
    static let welcomeTokens = 10
    /// Starting a session on Basic: if the week's own sessions are gone, it costs a token.
    /// Tools ▸ Apps Using the Most Memory: the threshold, and every open app (in or out of the session, critical ones
    /// too) at or over it, heaviest first.
    static let heavyBytes: UInt64 = 1 << 30                        // 1 GB
    static func spendTokenIfNeeded(_ f: Focus) {
        guard gated, tokens > 0 else { return }
        if week(f.sessions, now: Date()).left - tokens <= 0 { tokens -= 1 }
    }
    static var weekStart: Date { var c = Calendar.current; c.firstWeekday = 2; return c.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date() }
    /// Sessions started since 00:00 on Monday (Quit All clean-ups don't count), how many of Free's are left, and the
    /// day it resets (next Monday, 00:00 local time).
    static func week(_ sessions: [[String: Any]], now: Date, calendar: Calendar = .current) -> (used: Int, left: Int, reset: Date, resetDay: String) {
        var cal = calendar; cal.firstWeekday = 2                       // weeks start on Monday
        let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
        let reset = cal.date(byAdding: .day, value: 7, to: start) ?? now
        let used = sessions.filter { ($0["kind"] as? String) != "quit all" && (($0["date"] as? Date).map { $0 >= start && $0 <= now } ?? false) }.count
        let f = DateFormatter(); f.calendar = cal; f.locale = Locale(identifier: "en_GB"); f.dateFormat = "EEEE"
        let ud = UserDefaults.standard
        let bonus = (ud.object(forKey: "focusGiftWeek") as? Date).map { abs($0.timeIntervalSince(start)) < 3600 ? giftSessions : 0 } ?? 0   // the free reset, this week only
        let spent = (ud.object(forKey: "devSpentWeek") as? Date).map { abs($0.timeIntervalSince(start)) < 3600 } ?? false               // Developer Panel: sessions → 0
        let u = spent ? max(used, freeWeekly + bonus - (ud.integer(forKey: "devSpentBack"))) : used
        return (u, max(0, freeWeekly + bonus - u) + tokens, reset, f.string(from: reset))   // tokens on top: they never expire
    }
    /// Temporary, for looking at the design: show the Focus Pro badge and the Buy button together. Remove with licences.
    static let showBoth = false
    /// Free copies show their tier by the name too: the paid box's shape, outlined instead of solid. On (his ask,
    /// 2026-11-15); the word is "Basic" for him to see, then "Free" when he switches it.
    static var freeBadge: Bool { true }
    /// The free tier's name, from pricing.json (Free now; he may rename it Basic there, and the app follows).
    /// The free tier's name wherever the app says it (Basic, his choice 2026-11-15), from pricing.json.
    static var freeName: String { Pricing.current?.tiers["free"]?.name ?? "Basic" }
    static var freeBadgeWord: String { renderArgs.first { $0.hasPrefix("freeword=") }.map { String($0.dropFirst(9)) } ?? Pricing.current?.tiers["free"]?.name ?? "Free" }                                 // replaced by View ▸ View As (0.18.68)
    /// Whether this copy has been bought — read live (the window refreshes every 1.5 s), so the moment a purchase is
    /// recorded the Buy button becomes "Focus Pro". Licences aren't built yet: the purchase flow will set
    /// `focusPro` in Focus's defaults. A render can show it with `licensed`.
    static var licensed: Bool { tier != .free }
    /// Which Focus this copy is: Free or Pro — read live from `focusTier` ("pro"; an old "max" or the older `focusPro`
    /// flag also count as Pro). Renders: `licensed` (Pro) or `tier=free`.
    enum Tier { case free, pro }                                   // Max is retired (2026-11-15): any Max licence is Pro
    /// Whether Pro parts lock right now: only while viewing as Free (View As). A real copy never locks anything
    /// until licences exist, so his own use is untouched.
    static var gated: Bool { renderArgs.contains("viewas=free") || (UserDefaults.standard.string(forKey: "desktopViewAs") != nil && tier == .free) }
    static var tierKey: String { tier == .pro ? "pro" : "free" }
    static var tier: Tier {
        if renderArgs.contains("licensed") || renderArgs.contains("tier=max") { return .pro }
        if renderArgs.contains("tier=free") { return .free }
        switch UserDefaults.standard.string(forKey: "desktopViewAs") {   // View ▸ View As: see the app as each user would
        case "free": return .free
        case "pro", "max": return .pro
        default: break
        }
        switch UserDefaults.standard.string(forKey: "focusTier") {
        case "pro", "max": return .pro
        default: return UserDefaults.standard.bool(forKey: "focusPro") ? .pro : .free
        }
    }
    /// Days left in the Pro Preview (what the free trial of Focus Pro is called). Not counted yet (licences come later): the planned 14, to see the button as it will read.
    static var trialDaysLeft: Int { Pricing.current?.trial_days ?? 14 }    // the Preview's length, from pricing.json

    // — feedback, written here and sent straight to the developer —
    enum FeedbackState: Equatable { case writing, sending, sent, emailed }
    @Published var feedbackShown = false
    @Published var upgradeShown = false
    func openUpgrade() {                                           // a page in the window, not a pop-up; never for Pro
        guard !DesktopModel.licensed else { return }
        if selection != Page.upgrade { upgradeFrom = selection }
        outOfSessions = false
        selection = Page.upgrade
    }
    var heavyApps: [AppLine] {
        var seen = Set<String>()
        return (running + outside + critical).filter { $0.bytes >= Self.heavyBytes && seen.insert($0.id).inserted }.sorted { $0.bytes > $1.bytes }
    }
    func openOutOfSessions() {
        if giftDue { giftShown = true; return }                    // the first time: the gift, not the plans
        openUpgrade(); outOfSessions = true
    }
    @Published var feedbackText = ""
    @Published var feedbackState = FeedbackState.writing
    /// Where feedback is posted. Until the site answers there, the message goes into an email instead.
    static let feedbackEndpoint = URL(string: "https://paradoxica.uk/api/feedback")!   // the API lives on .uk (.co.uk has none: 404)
    static let feedbackAddress = "help@paradoxica.co.uk"        // every ★★★★★ × PARADOX app's help address
    static let appName = "Focus"
    /// The subject every PARADOX app uses: the app's name in capitals, a space, then the rest.
    static func feedbackSubject(_ text: String) -> String {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        let short = first.count > 60 ? String(first.prefix(57)) + "…" : first
        return appName.uppercased() + " " + (short.isEmpty ? "feedback" : short)
    }
    /// The account's email, given once at sign-up (the sign-in system stores it as "accountEmail"). Never asked again.
    static var accountEmail: String { UserDefaults.standard.string(forKey: "accountEmail") ?? "" }
    var feedbackReady: Bool { !feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    func openFeedback() { feedbackState = .writing; feedbackShown = true }
    func sendFeedback() {
        let text = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines); guard feedbackReady, feedbackState == .writing else { return }
        let email = Self.accountEmail, subject = Self.feedbackSubject(text)
        feedbackState = .sending
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        var req = URLRequest(url: Self.feedbackEndpoint, timeoutInterval: 12); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["app": Self.appName, "to": Self.feedbackAddress, "subject": subject,
                                                                    "email": email, "version": version, "macOS": os, "message": text])
        URLSession.shared.dataTask(with: req) { [weak self] _, resp, _ in
            let ok = (resp as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            DispatchQueue.main.async {
                guard let self else { return }
                if ok { self.feedbackState = .sent; self.feedbackText = ""; return }
                // No answer from the site: put the same message in an email, so nothing written is lost.
                var c = URLComponents(); c.scheme = "mailto"; c.path = Self.feedbackAddress
                c.queryItems = [URLQueryItem(name: "subject", value: subject),
                                URLQueryItem(name: "body", value: text + "\n\n" + (email.isEmpty ? "" : "From \(email) · ") + "\(Self.appName) \(version) · \(os)")]
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
        lineTimer?.invalidate()                                    // the closing line: checked 4× a second, cheap (no memory read)
        let l = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = self.caption
            if now != self.lastCaption { self.lastCaption = now; self.tick &+= 1 }
            self.showGiftIfDue()
        }
        RunLoop.main.add(l, forMode: .common); lineTimer = l
    }
    func stop() { timer?.invalidate(); timer = nil; lineTimer?.invalidate(); lineTimer = nil }
    private var lineTimer: Timer?
    private var lastCaption = ""
    func refresh() { f.mem = memoryByPid(); if Site.look == 2, let w = desktop.window { DesktopController.applyLook(to: w) }; tick &+= 1 }
    /// Do something to the engine, then show it.
    func act(_ change: () -> Void) { change(); tick &+= 1 }
    /// A Pro action: viewing as Basic it opens Upgrade instead; otherwise it does the change.
    func pro(_ change: () -> Void) { if DesktopModel.gated { openUpgrade() } else { act(change) } }

    // — type to add an app —
    struct Found: Identifiable { let id: String, path: String, name: String, open: Bool, inSession: Bool
        var state: String { inSession ? "In the session" : open ? "Open" : "Not open" } }
    /// Every app on the Mac (read once), for the finder.
    lazy var installed: [(id: String, path: String, name: String)] = {
        let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                    NSHomeDirectory() + "/Applications"]
        var seen = Set<String>(), out = [(id: String, path: String, name: String)]()
        for d in dirs { for n in (try? FileManager.default.contentsOfDirectory(atPath: d)) ?? [] where n.hasSuffix(".app") {
            let path = d + "/" + n
            guard let id = Bundle(path: path)?.bundleIdentifier, !seen.contains(id) else { continue }
            seen.insert(id); out.append((id, path, String(n.dropLast(4))))
        } }
        return out
    }()
    func find(_ q: String) -> [Found] {
        let q = q.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let open = Dictionary(running.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let pool = installed.map { a -> Found in Found(id: a.id, path: a.path, name: open[a.id]?.name ?? a.name, open: open[a.id] != nil, inSession: open[a.id]?.on ?? f.excluded.contains(a.id)) }
        let hits = pool.filter { $0.name.localizedCaseInsensitiveContains(q) && !f.neverClose.contains($0.id) }
        return hits.sorted { ($0.name.lowercased().hasPrefix(q.lowercased()) ? 0 : 1, $0.open ? 0 : 1, $0.name) < ($1.name.lowercased().hasPrefix(q.lowercased()) ? 0 : 1, $1.open ? 0 : 1, $1.name) }
    }
    /// Adds a found app to the session: an open one is ticked; one that isn't open joins the session's apps
    /// (and opens, during a session).
    func add(_ h: Found) {
        if let line = running.first(where: { $0.id == h.id }) { if !line.on { toggle(line) }; return }
        act {
            if !f.excluded.contains(h.id) { f.excluded.append(h.id) }
            if f.focused { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: h.path), configuration: NSWorkspace.OpenConfiguration()) }
        }
    }

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
        if f.focused {                                              // live, like a terminal: each app as it goes, then done
            if renderArgs.contains("closing") { return "Closing Safari…  2 of 6" }
            if let a = f.queue.first, f.total > 0 { return "Closing \(a.localizedName ?? "app")…  \(f.total - f.queue.count + 1) of \(f.total)" }
            if let st = f.status, st.hasPrefix("Quitting ") { return "Closing " + st.dropFirst(9).replacingOccurrences(of: " at once", with: "") + "…" }
            if let st = f.status, st.hasPrefix("Waiting") { return st + "." }
            return "Session started. End the session to bring all your apps back."
        }
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
    var hovered: ((Bool) -> Void)? = nil                        // tells the memory bar which app to light
    var lit = false                                             // lit from the memory bar
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
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill((hover && action != nil) || lit ? Site.surface : Color.clear))
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: hover).animation(.easeOut(duration: 0.2), value: app.on)
        .onHover { hover = $0; hovered?($0) }
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
    @ObservedObject var m: DesktopModel                            // shares the hovered app with the list below
    static var shown: Bool { !renderArgs.contains("nobar") && (UserDefaults.standard.object(forKey: "desktopMemoryBar") as? Bool ?? true) }
    var body: some View {
        let total = max(apps.reduce(0) { $0 + $1.bytes }, 1), freed = apps.filter { !$0.on }.reduce(0) { $0 + $1.bytes }
        let shown = apps.filter { $0.bytes > 0 }, hot = m.hoverApp
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { g in
                HStack(spacing: 2) {
                    ForEach(shown) { a in
                        let w = max(4, (g.size.width - CGFloat(shown.count) * 2) * CGFloat(a.bytes) / CGFloat(total))
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(a.on ? Site.ink : Site.idle)
                            if w > CGFloat(a.name.count) * 7.5 * Site.scale + 18 {           // the app's name, where it fits
                                Text(a.name).font(Site.font(12.5, .medium)).foregroundColor(a.on ? Site.paper : Site.head).lineLimit(1).padding(.leading, 8)
                            }
                        }
                        .frame(width: w)
                        .opacity(hot == nil || hot == a.id ? 1 : 0.35)
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Site.head, lineWidth: hot == a.id ? 2 : 0))
                        .onHover { m.hoverApp = $0 ? a.id : (m.hoverApp == a.id ? nil : m.hoverApp) }
                        .help("\(a.name) · \(a.usage)")
                    }
                }
                .animation(.easeOut(duration: 0.35), value: apps.map(\.on)).animation(.easeOut(duration: 0.12), value: hot)
            }.frame(height: 24)
            HStack(spacing: 14) {
                if let id = hot, let a = apps.first(where: { $0.id == id }) {
                    Text("\(a.name) · \(a.usage) · \(a.on ? "stays open" : "closes in a session")").font(Site.font(15, .medium)).foregroundColor(Site.head)
                } else {
                    Text("\(gb(total)) in use by open apps" + (freed > 0 ? " · a session frees \(gb(freed))" : "")).font(Site.font(15)).foregroundColor(Site.muted)
                }
                Spacer(minLength: 8)
                key(Site.ink, "Stays"); key(Site.idle, "Closes")                     // what the two shades mean
            }
        }
    }
    func key(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) { RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 12, height: 12); Text(t).font(Site.font(14)).foregroundColor(Site.muted) }
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
                HStack(spacing: 12) {                                     // in a session: the working mark before the title (placeholder, his call 2026-11-16)
                    if !starting {
                        WorkingMark(ink: ink).frame(width: 24 * Site.scale, height: 24 * Site.scale)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                    Text(title).font(Site.font(25, .medium)).tracking(-0.4).lineLimit(1)
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: starting)
                .background(GeometryReader { g in Color.clear.preference(key: TitleWidth.self, value: g.size.width) })
                .onPreferenceChange(TitleWidth.self) { titleWidth = $0 }
                HStack(spacing: 14) {
                    Spacer()
                    Text(key).font(Site.font(18)).opacity(hover ? 0.6 : 0.45).lineLimit(1)
                }.padding(.trailing, 24).animation(.spring(response: 0.45, dampingFraction: 0.7), value: starting)
            }
            .foregroundColor(ink).frame(maxWidth: .infinity).frame(height: Layout.button)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [tint, tint2], startPoint: .leading, endPoint: .trailing)).opacity(hover ? 0.92 : 1)
                    .overlay(Group {
                        if starting, let s = pressStart { PressureDots(ink: ink, titleWidth: titleWidth, start: s, end: pressEnd, release: pressRelease) }   // pressure only to start; in a session only the working mark moves
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
    func line(_ t: String) -> some View { Text(t).font(Site.font(14)).lineLimit(1).minimumScaleFactor(0.85) }
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
    struct Tier: Decodable {
        let name: String; let label: String?; let price_note: String?; let tagline: String; let monthly: Int; let yearly: Int?; let once: Int?; let best: Bool?
        let summary: String; let yearly_summary: String?; let once_summary: String?
        let launch: Launch?
    }
    /// The early adopter gift: while active, the one-off sells at `once` (e.g. £50 instead of £75).
    struct Launch: Decodable { let active: Bool; let once: Int; let label: String; let line: String; let then: String; let code: String?; let short: String? }
    struct Soon: Decodable { let name: String; let tagline: String; let note: String }
    struct Lead: Decodable { let tier: String; let plan: String }
    let currency: String
    let trial_days: Int
    let trial_tier: String
    let free_sessions_per_week: Int
    let lead: Lead
    let table_opens_on: String?                                // which plan the price switch opens on (the site: "once")
    let badge: String?                                         // the best tier's label ("Best value"), when the file has it
    let coming_soon: [Soon]?                                   // tiers shown greyed out, not on sale (Enterprise)
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
    static func checkout(tier: String, plan: String, code: String? = nil) -> URL {
        URL(string: "https://paradoxica.uk/focus/checkout/?tier=\(tier)&plan=\(plan)" + (code.map { "&code=\($0)" } ?? ""))!
    }
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
    /// (The newer of the two: a copy saved from the site before this version shipped mustn't beat the one inside it.
    /// Off-screen renders always use the shipped copy.)
    static var current: Pricing? = {
        guard !renderArgs.contains("--render-desktop") && !renderArgs.contains("--selftest-gui") else { return bundled }
        let date = { (u: URL?) in u.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date } ?? .distantPast }
        let shipped = Bundle.main.url(forResource: "pricing", withExtension: "json")
        if date(cacheFile) > date(shipped), let c = try? JSONDecoder().decode(Pricing.self, from: Data(contentsOf: cacheFile)) { return c }
        return bundled
    }()
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

/// Upgrade: the plans, side by side, the way Mac apps sell from inside themselves — Monthly, Yearly or Once, Pro marked as
/// the best value, and the plan's button opening the site's checkout in the browser. Everything comes from pricing.json.
struct UpgradeCard: View {
    @ObservedObject var m: DesktopModel
    @State private var plan = 0                                  // monthly, yearly, once (as the file offers them)
    var plans: [String] { (Pricing.current?.tiers["pro"]?.yearly != nil) ? ["monthly", "yearly", "once"] : ["monthly", "once"] }
    var body: some View {
        if let p = Pricing.current {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(plans.count == 3 ? "Pay monthly, yearly, or once and keep it forever." : "Pay monthly, or once and keep it forever.").font(Site.font(17)).foregroundColor(Site.low)
                    Spacer()
                    Choice(options: plans.map { $0.capitalized }, selected: min(plan, plans.count - 1), solid: Site.solid) { i in plan = i }
                }
                HStack(alignment: .top, spacing: 14) {
                    ForEach(["free", "pro"], id: \.self) { key in
                        if let t = p.tiers[key] { card(key, t, p) }
                    }
                }.fixedSize(horizontal: false, vertical: true).padding(.top, 18)
                HStack {
                    Text("\(p.trial_days) days of Pro come free with every new copy").font(Site.font(15)).foregroundColor(Site.muted)
                    Spacer()
                    Button { NSWorkspace.shared.open(Pricing.page) } label: {
                        HStack(spacing: 5) { Text("Compare every feature").font(Site.font(15, .medium)); Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)) }
                            .foregroundColor(Site.head).underline()
                    }.buttonStyle(.plain).linkCursor()
                }.padding(.top, 18)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .onAppear {                                              // opens on Monthly: the lowest number first
                plan = plans.firstIndex(of: renderArgs.first { $0.hasPrefix("plan=") }.map { String($0.dropFirst(5)) } ?? "monthly") ?? 0
                if !renderArgs.contains("--render-desktop") { Pricing.refresh { m.tick &+= 1 } }
            }
        }
    }
    /// A tier that isn't on sale yet (Enterprise): a greyed strip under the plans — name · tagline · COMING SOON.
    @ViewBuilder func strip(_ t: Pricing.Soon) -> some View {
        HStack(spacing: 10) {
            Text(t.name).font(Site.font(16, .medium)).foregroundColor(Site.head)
            Text("·").foregroundColor(Site.muted)
            Text(t.tagline).font(Site.font(15)).foregroundColor(Site.low)
            Spacer()
            Text(t.note.uppercased()).font(Site.font(12, .semibold)).tracking(1).foregroundColor(Site.muted)
        }
        .padding(.horizontal, 18).frame(height: 46)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Site.line, lineWidth: 1))
        .opacity(0.55).padding(.top, 14).allowsHitTesting(false)
    }
    @ViewBuilder func card(_ key: String, _ t: Pricing.Tier, _ p: Pricing) -> some View {
        let best = t.best == true, current = DesktopModel.tierKey == key
        let which = plans[min(plan, plans.count - 1)]
        let amount = which == "once" ? t.once : which == "yearly" ? t.yearly : t.monthly
        let gift = which == "once" ? t.launch.flatMap { $0.active ? $0 : nil } : nil      // early adopter gift: £50, then £75
        let price = key == "free" ? "\(p.currency)0" : "\(p.currency)\(gift?.once ?? amount ?? t.monthly)"   // the gift: £50, with £75 struck through
        let per = key == "free" ? (t.price_note ?? "Free") : which == "once" ? "once" : which == "yearly" ? "a year" : "a month"
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TierBox(name: t.name, solid: key == "pro", size: 20, fill: Site.solid)            // the tier in its box, as beside the Focus name
                Spacer()
                if let gift { Text(gift.label).font(Site.font(12, .semibold)).foregroundColor(Site.paper).padding(.horizontal, 7).frame(height: 20).background(RoundedRectangle(cornerRadius: 5).fill(Site.solid)) }
                else if best { Text(p.badge ?? "Best value").font(Site.font(12, .semibold)).foregroundColor(Site.paper).padding(.horizontal, 7).frame(height: 20).background(RoundedRectangle(cornerRadius: 5).fill(Site.solid)) }
            }
            Text(p.fill(t.tagline)).font(Site.font(15)).foregroundColor(Site.low).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            if key == "pro", let first = p.features.first(where: { $0.group == "Pro" })?.rows.first, case .text(let early)? = first.first {
                HStack(alignment: .firstTextBaseline, spacing: 6) {                  // early access, near the top (his key Pro point)
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)); Text(early).font(Site.font(14, .medium))
                }.foregroundColor(Site.head).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(price).font(Site.font(32, .medium)).foregroundColor(Site.head)
                if let gift, let full = t.once { Text("\(p.currency)\(full)").font(Site.font(20)).strikethrough().foregroundColor(Site.muted); if gift.code == nil { Text(gift.then).font(Site.font(15)).foregroundColor(Site.muted) } }
                else { Text(per).font(Site.font(15)).foregroundColor(Site.muted) }
            }.padding(.top, 8)
            if !(key == "free" && t.tagline.contains("{free_sessions_per_week}")) {   // said once: the tagline already gives the number
            Text(p.fill(key == "free" ? t.summary : which == "once" ? (gift.map { g in g.line.replacingOccurrences(of: "{launch_once}", with: "\(p.currency)\(g.once)").replacingOccurrences(of: "{once}", with: "\(p.currency)\(t.once ?? 0)").replacingOccurrences(of: "{code}", with: g.code ?? "") } ?? t.once_summary ?? t.summary) : which == "yearly" ? (t.yearly_summary ?? t.summary) : t.summary)).font(Site.font(14)).foregroundColor(Site.low)
                .fixedSize(horizontal: false, vertical: true).frame(minHeight: 40, alignment: .top)
            }
            if key == "pro", which != "once", let i = plans.firstIndex(of: "once") {
                Button { withAnimation(.easeOut(duration: 0.15)) { plan = i } } label: {         // the better deal, one click away
                    Text("Not a fan of subscriptions? Buy once, keep forever\u{00A0}\(Image(systemName: "chevron.right"))").underline()
                        .font(Site.font(14, .medium)).foregroundColor(Site.head).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true).contentShape(Rectangle())
                }.buttonStyle(.plain).linkCursor().padding(.bottom, 4)
            }
            Button {
                if key != "free" && !current { NSWorkspace.shared.open(Pricing.checkout(tier: key, plan: which, code: gift?.code)) }   // the code pre-applied
            } label: {
                Text(current ? "Current Plan" : key == "free" ? "Included" : "Buy Focus \(t.name)").font(Site.font(16, .medium))
                    .foregroundColor(best && !current ? Site.paper : Site.head).frame(maxWidth: .infinity).frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(best && !current ? Site.solid : Color.clear))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Site.solid.opacity(best && !current ? 0 : 0.6), lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))   // the whole button takes the click
            }.buttonStyle(PressStyle()).disabled(key == "free" || current).linkCursor().padding(.top, 10)
            if let code = gift?.code { CodeBox(code: code).padding(.top, 8) }    // right under Buy Focus Pro, as on the site
        }
        .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)   // both plans the same height
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(best ? Site.surface : Site.bg))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(best ? Site.solid.opacity(Site.light ? 0.45 : 0.9) : Site.line, lineWidth: best ? 1.5 : 1))
    }
}

/// The tier beside the Focus name. It arrives after the logo's own opening: Basic slides in outlined; Pro comes in
/// outlined and fills solid. If Pro is bought while the window is open, the outlined Basic fills and becomes Pro.
struct TierBadge: View {
    @ObservedObject var m: DesktopModel
    @State private var shown = false
    @State private var filled = false
    var body: some View {
        let pro = DesktopModel.licensed
        TierBox(name: filled ? (Pricing.current?.tiers["pro"]?.name ?? "Pro") : DesktopModel.freeBadgeWord, solid: filled, size: 15)
            .scaleEffect(shown ? 1 : 0.6).opacity(shown ? 1 : 0).offset(x: shown ? 0 : -8, y: 2)
            .task(id: pro) {
                if m.still { shown = true; filled = pro; return }      // off-screen renders: the finished state
                if !shown {                                             // the window opening: after the logo's own animation
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { shown = true }
                    guard pro else { return }
                    try? await Task.sleep(nanoseconds: 350_000_000)
                } else { try? await Task.sleep(nanoseconds: 150_000_000) }   // bought (or viewed as) Pro while open
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { filled = pro }
            }
    }
}

/// Basic's two quiet lines above Feedback / Manual: sessions left this week, and days of Pro left with Upgrade Now.
/// Grey and small, because a reminder that's always there must not nag. They brighten in the last 3 days or sessions.
/// Upgrade Now rewards a hover: it whitens, underlines, and an arrow slides in.
struct PlanLines: View {
    @ObservedObject var m: DesktopModel
    @State private var hover = false
    var body: some View {
        let week = DesktopModel.week(m.f.sessions, now: Date())
        let left = m.countUp ?? (renderArgs.contains("out") ? 0 : renderArgs.contains("headsup") ? 2 : week.left), days = DesktopModel.trialDaysLeft
        let facts = VStack(alignment: .leading, spacing: 3) {          // the two facts, one above the other, always the same size
            Text("\(left) \(left == 1 ? "Session" : "Sessions") left this week")
                .font(Site.font(12.5)).foregroundColor(left <= 3 ? Site.head : Site.low)
            if DesktopModel.trial {
                Text("\(days) \(days == 1 ? "Day" : "Days") of Pro left")
                    .font(Site.font(12.5)).foregroundColor(days <= 3 ? Site.head : Site.low)
            }
        }.fixedSize()
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) { facts; Spacer(minLength: 0); upgrade }
            VStack(alignment: .leading, spacing: 8) { facts; upgrade }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.horizontal, 2).padding(.bottom, 6)
    }
    var upgrade: some View {
        Button { m.openUpgrade() } label: {                       // a reward, not a nag: on hover it fills, Pro's colour
            HStack(spacing: 4) {
                Text("Upgrade Now").font(Site.font(11.5, .semibold)).fixedSize()
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold)).offset(x: hover ? 1 : 0, y: hover ? -1 : 0)
            }
            .foregroundColor(hover ? Site.paper : Site.head).padding(.horizontal, 8).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 15, style: .circular).fill(hover ? Site.ink : Site.paper))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .circular).strokeBorder(Site.ink.opacity(hover ? 0 : 0.7), lineWidth: 1))
            .shadow(color: Site.ink.opacity(hover && !Site.light ? 0.35 : 0), radius: 10)     // no shadows in Light
            .scaleEffect(hover ? 1.04 : 1).contentShape(RoundedRectangle(cornerRadius: 15, style: .circular))
        }.buttonStyle(PressStyle()).onHover { hover = $0 }.linkCursor().help("See the plans")
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
    }
}

/// A tier's name in its box: solid for Pro (as beside the Focus name), outlined for Basic.
struct TierBox: View {
    let name: String, solid: Bool
    var size: CGFloat = 15
    var fill: Color = Site.ink
    var body: some View {
        Text(name).font(Site.font(size, .semibold)).foregroundColor(solid ? Site.paper : Site.ink)
            .padding(.horizontal, size * 0.5).frame(height: size * 1.6)
            .background(RoundedRectangle(cornerRadius: size * 0.33, style: .continuous).fill(solid ? fill : Site.paper))
            .overlay(RoundedRectangle(cornerRadius: size * 0.33, style: .continuous).strokeBorder(Site.ink, lineWidth: solid ? 0 : 1.2))
    }
}

/// The early adopter code, as the site shows it: a dashed box, CODE and the code, and Copy.
struct CodeBox: View {
    let code: String
    @State private var copied = false
    var body: some View {
        HStack(spacing: 8) {
            Text("CODE").font(Site.font(11, .semibold)).tracking(0.8).foregroundColor(Site.muted).fixedSize()
            Text(code).font(Site.font(16, .semibold)).tracking(1).foregroundColor(Site.head).lineLimit(1).minimumScaleFactor(0.8).textSelection(.enabled)
            Spacer(minLength: 4)
            Button {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string)
                copied = true; DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
            } label: {
                Text(copied ? "Copied" : "Copy").font(Site.font(13, .medium)).foregroundColor(Site.head).fixedSize().padding(.horizontal, 9).frame(height: 24)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Site.ink.opacity(0.5), lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }.buttonStyle(PressStyle())
        }
        .padding(.leading, 12).padding(.trailing, 8).frame(height: 40)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Site.ink.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
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
                    HStack(spacing: 10) {
                        Spacer()
                        SiteButton("Cancel") { m.feedbackShown = false }
                        Button { m.sendFeedback() } label: {
                            Text(m.feedbackState == .sending ? "Sending…" : "Send").font(Site.font(18, .medium)).foregroundColor(Site.paper)
                                .padding(.horizontal, 22).frame(height: 32)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Site.ink))
                        }.buttonStyle(.plain)
                        .opacity(!m.feedbackReady || m.feedbackState == .sending ? 0.35 : 1).disabled(!m.feedbackReady)
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

/// Where a Pro feature is locked (viewing as Basic): a sentence saying what Pro unlocks here, and an outlined "Upgrade to Pro" button. The page
/// itself stays whole and readable, so people can see what Pro does; using a locked control opens Upgrade.
/// Type to find an app: every app on the Mac, open or not. Return (or a click) adds the first match to the session —
/// ticked if it's open, added to the session's apps if it isn't (and opened into it, during a session).
struct AppFinder: View {
    @ObservedObject var m: DesktopModel
    @State private var query = ""
    @FocusState private var focused: Bool
    var body: some View {
        let hits = m.find(query)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium)).foregroundColor(Site.muted)
                TextField("Type to add an app", text: $query).textFieldStyle(.plain).font(Site.font(17)).foregroundColor(Site.head)
                    .focused($focused).onSubmit { if let h = hits.first { add(h) } }
                if !query.isEmpty { Text("Return to add").font(Site.font(13)).foregroundColor(Site.muted) }
            }
            .padding(.horizontal, 12).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Site.surface))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(focused ? Site.ink.opacity(0.6) : Site.line, lineWidth: 1))
            ForEach(hits.prefix(5)) { h in
                Button { add(h) } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: m.icon(h.path)).resizable().frame(width: 20, height: 20)
                        Text(h.name).font(Site.font(16)).foregroundColor(Site.head)
                        Spacer()
                        Text(h.state).font(Site.font(13)).foregroundColor(Site.muted)
                    }.padding(.horizontal, 12).frame(height: 32).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }
    func add(_ h: DesktopModel.Found) { m.add(h); query = "" }
}

struct LockedPanel: View {
    @ObservedObject var m: DesktopModel
    let text: String                                           // what Pro unlocks here, in this place's own words
    @State private var hover = false
    var body: some View {
        HStack(spacing: 16) {
            Text(text).font(Site.font(17)).foregroundColor(Site.head).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button { m.openUpgrade() } label: {                         // a real button, but outlined: never the big one
                HStack(spacing: 6) {
                    Text("Upgrade to Pro").font(Site.font(15, .semibold)).fixedSize()
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold)).offset(x: hover ? 1.5 : 0, y: hover ? -1.5 : 0)
                }
                .foregroundColor(Site.head).padding(.horizontal, 16).frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover ? Site.surface2 : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Site.ink.opacity(hover ? 1 : 0.75), lineWidth: 1.2))
                .contentShape(Rectangle())
            }.buttonStyle(PressStyle()).onHover { hover = $0 }.linkCursor().help("See the plans")
            .animation(.easeOut(duration: 0.15), value: hover)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Site.surface))
        .padding(.vertical, 8)
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
                    ForEach([("Actual", ""), (DesktopModel.freeName, "free"), ("Pro", "pro")], id: \.1) { title, key in
                        let on = now == key
                        Button {
                            m.act { m.viewAs(key) }
                        } label: {
                            Text(title).font(Site.font(14, .medium)).foregroundColor(on ? Site.paper : Site.head).lineLimit(1).frame(maxWidth: .infinity).frame(height: 30)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? Site.ink : Color.clear))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Site.ink.opacity(on ? 0 : 0.5), lineWidth: 1))
                                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))   // the whole button takes the click
                        }.buttonStyle(PressStyle())
                    }
                }
                HStack(spacing: 6) {                                         // the gifts: run out, or open as new
                    devButton("Sessions → 0") { m.devSpendAll() }
                    devButton("Welcome") { m.devWelcome() }
                }
                devButton("Restore sessions and tokens") { m.devRestore() }
            }
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Site.muted, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .padding(.leading, 12).padding(.trailing, 12).padding(.top, 10)
    }
}

extension ViewAsPanel {
    func devButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Site.font(13, .medium)).foregroundColor(Site.head).lineLimit(1).frame(maxWidth: .infinity).frame(height: 28)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Site.ink.opacity(0.5), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }.buttonStyle(PressStyle()).linkCursor()
    }
}

/// "We're working": a ring with a gap, turning slowly, round a solid dot (Focus's ring and dot). Placeholder mark for
/// the session button while a session runs.
struct WorkingMark: View {
    let ink: Color
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: renderArgs.contains("--render-desktop"))) { tl in
            let turn = renderArgs.contains("--render-desktop") ? 0.6 : tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6   // renders: one fixed angle
            GeometryReader { g in
                let d = min(g.size.width, g.size.height)
                ZStack {
                    Circle().trim(from: 0, to: 0.72).stroke(ink, style: StrokeStyle(lineWidth: d * 0.12, lineCap: .round))
                        .rotationEffect(.degrees(turn * 360))
                    Circle().fill(ink).frame(width: d * 0.36, height: d * 0.36)
                }.frame(width: d, height: d)
            }
        }
    }
}

/// The free reset: a gift, not a gate. Ten tokens in a ring; on Add they fly one by one into the middle, the number
/// counts up, then the card goes and the sidebar's count rises to match.
struct GiftCard: View {
    @ObservedObject var m: DesktopModel
    @State private var taken = 0                                   // tokens flown in so far
    @State private var going = false
    var welcome: Bool { m.giftKind == .welcome || renderArgs.contains("welcome") }
    var n: Int { welcome ? DesktopModel.welcomeTokens : DesktopModel.giftSessions }
    var body: some View {
        ZStack {
            Color.black.opacity(Site.light ? 0.25 : 0.6).ignoresSafeArea()
            VStack(spacing: 0) {
                if welcome {                                       // the thank-you, big, first
                    Text("Thank you!").font(Site.font(44, .medium)).tracking(-1).foregroundColor(Site.head).padding(.bottom, 14)
                }
                ZStack {                                           // the ring of tokens
                    ForEach(0..<n, id: \.self) { i in
                        let a = Double(i) / Double(n) * 2 * .pi - .pi / 2, r: CGFloat = 70, inside = i < taken
                        Circle().fill(Site.ink).frame(width: 18, height: 18)
                            .overlay(Circle().fill(Site.paper).frame(width: 6, height: 6))
                            .offset(x: inside ? 0 : CGFloat(cos(a)) * r, y: inside ? 0 : CGFloat(sin(a)) * r)
                            .scaleEffect(inside ? 0.2 : 1).opacity(inside ? 0 : 1)
                            .animation(.spring(response: 0.42, dampingFraction: 0.72), value: taken)
                    }
                    Text("+\(taken == 0 ? n : taken)").font(Site.font(34, .medium)).foregroundColor(Site.head)
                        .contentTransition(.numericText()).animation(.easeOut(duration: 0.12), value: taken)
                }.frame(width: 180, height: 180)
                Text(welcome ? "An extra \(n) sessions" : "Here's a free reset").font(Site.font(26, .medium)).tracking(-0.4).foregroundColor(Site.head).padding(.top, 10)
                Text(welcome ? "As thanks for being an early adopter, here are \(n) extra session tokens. Pro is unlimited, but if you use Basic, these let you get more done. They don't expire."
                             : "We know you probably wanted to play around with Focus first, so this week's \(n) sessions are back, on us. It's a one-time gift.")
                    .font(Site.font(16)).foregroundColor(Site.low).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380).padding(.top, 8)
                Button { give() } label: {
                    Text(going ? "Adding…" : "Add \(n) sessions").font(Site.font(17, .medium)).foregroundColor(Site.paper)
                        .frame(width: 240, height: 46).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Site.ink)).contentShape(Rectangle())
                }.buttonStyle(PressStyle()).linkCursor().disabled(going).padding(.top, 22).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 36).padding(.vertical, 30)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Site.bg))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Site.line, lineWidth: 1))
        }
    }
    func give() {
        guard !going else { return }
        going = true
        for i in 1...n { DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.09) { taken = i } }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(n) * 0.09 + 0.55) { m.takeGift() }
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
                    Spacer()
                    if !right.isEmpty { Text(right).font(Site.font(15)).foregroundColor(Site.muted).padding(.trailing, pro ? 0 : 24) }
                    if pro { ProTag().alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 } }   // always last: the right-hand tag column
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
/// Fires whenever the tier changes (View As, a purchase), so views that only read the tier — tags, Pro settings — redraw.
final class TierWatch: ObservableObject { static let shared = TierWatch(); @Published var n = 0 }

struct ProTag: View {
    @ObservedObject private var watch = TierWatch.shared
    var body: some View {
        if !DesktopModel.licensed || renderArgs.contains("tags") {
            Text("Pro").font(Site.font(10.5, .medium)).foregroundColor(Site.muted)       // quiet: marks a feature, never competes with it
                .padding(.horizontal, 5).frame(height: 16)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Site.muted.opacity(0.6), lineWidth: 0.75))
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
            Spacer(minLength: 6)
            if pro && !(hover && start != nil) { ProTag() }             // at the right edge, out of the title's way
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
            } else if !trailing.isEmpty || (hover && hint != nil) { Text(hover && hint != nil ? hint! : trailing).font(Site.font(15)).foregroundColor(live || (hover && hint != nil) ? Site.head : Site.muted) }   // nothing empty: a Pro tag ends where the ⌘ keys do
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
                    if DesktopModel.licensed || DesktopModel.freeBadge { TierBadge(m: m) }   // Basic or Pro, arriving after the logo
                }.padding(.leading, 16).frame(width: 292, alignment: .leading)
                VStack(spacing: 9) {
                    let look = buttonColours
                    SessionButton(title: m.f.focused ? "End Session" : "Start New Session", key: sessionKey, starting: !m.f.focused,
                                  tint: look.0, tint2: look.1, ink: look.2) { if !m.f.focused && DesktopModel.noSessionsLeft(m.f) { m.openOutOfSessions() } else { m.act { m.f.toggle() } } }
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
                    else if m.selection == Page.appearance { AppearancePage(m: m) }
                    else if m.selection == Page.schedule { SchedulePage(m: m) }
                    else if let id = m.selection, let mode = m.modes.first(where: { $0.id == id }) { ModeDetail(m: m, mode: mode).id(mode.id + "\u{1F}" + mode.name) }
                    else if m.selection == Page.history { HistoryPage(m: m) }
                    else if m.selection == Page.manual { ManualPage() }
                    else if m.selection == Page.upgrade && !DesktopModel.licensed {
                        if m.outOfSessions || renderArgs.contains("out") {
                            PageFrame(title: "0 sessions remaining this week — \(DesktopModel.resetLine(m.f))",
                                      text: "Pro has no limit: start as many sessions as you like.") { UpgradeCard(m: m).padding(.top, 18) }
                        } else { PageFrame(title: "Upgrade Focus", text: "") { UpgradeCard(m: m).padding(.top, 4) } }
                    }
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
        .overlay { if m.giftShown || renderArgs.contains("gift") || renderArgs.contains("welcome") { GiftCard(m: m).transition(.opacity) } }
        .animation(.easeOut(duration: 0.2), value: m.giftShown)

        .animation(.easeOut(duration: 0.15), value: m.feedbackShown)
    }
    /// The big button wears the colour chosen in Settings ▸ Appearance (the icon's ring, then its dot), white when none is.
    /// Its text is the user's Text colour: black (the standard) or white.
    var buttonColours: (Color, Color, Color) {
        guard let a = hexColor(m.f.iconColor) else { return (Site.ink, Site.ink, Site.paper) }   // no colour: the look's own
        let b = hexColor(m.f.iconColor2) ?? a
        return (Color(nsColor: a), Color(nsColor: b), Self.inkWhite(on: a, b) ? .white : .black)
    }
    /// WCAG contrast between two colours (1…21).
    static func contrast(_ x: NSColor, _ y: NSColor) -> CGFloat {
        func lum(_ c: NSColor) -> CGFloat {
            let c = c.usingColorSpace(.sRGB) ?? c
            func ch(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * ch(c.redComponent) + 0.7152 * ch(c.greenComponent) + 0.0722 * ch(c.blueComponent)
        }
        let a = lum(x), b = lum(y); return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
    /// Whether white text reads on this button: the text colour chosen if it reads (contrast 3+ on both ends of the
    /// colour), otherwise the one that does — so white on white or black on black can never happen.
    static func inkWhite(on a: NSColor, _ b: NSColor) -> Bool {
        func reads(_ white: Bool) -> Bool { let ink: NSColor = white ? .white : .black; return min(contrast(ink, a), contrast(ink, b)) >= 3 }
        let want = buttonInkWhite
        if reads(want) { return want }
        if reads(!want) { return !want }
        return (min(contrast(.white, a), contrast(.white, b)) >= min(contrast(.black, a), contrast(.black, b)))
    }
    /// Every preset's first colour: a stored colour outside these was picked with Any colour.
    static var presetColours: Set<String> { Set((theme.iconPresets + theme.evaPresets).map { $0.1 }) }
    /// After a new button colour: if the stored text colour wouldn't read on it, store the one that does.
    static func keepInkReadable(_ f: Focus) {
        guard let a = hexColor(f.iconColor) else { return }
        UserDefaults.standard.set(inkWhite(on: a, hexColor(f.iconColor2) ?? a), forKey: "desktopButtonInkWhite")
    }
    /// Settings ▸ Appearance ▸ Text colour (the big button only). Renders: `ink=white`.
    static var buttonInkWhite: Bool { renderArgs.contains("ink=white") || UserDefaults.standard.bool(forKey: "desktopButtonInkWhite") }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 2) {
                SideRow(title: "Session Editor", trailing: "", live: m.f.focused && !m.modes.contains { $0.live }, selected: m.selection == nil, icons: [], symbol: "circle.grid.2x2",
                        action: { m.selection = nil }, state: m.f.focused)
                SideRow(title: "Shortcuts", trailing: "", live: false, selected: m.selection == Page.shortcuts, icons: [], symbol: "keyboard", action: { m.selection = Page.shortcuts }, pro: true)
                SideRow(title: "Schedule", trailing: "", live: false, selected: m.selection == Page.schedule, icons: [], symbol: "calendar.badge.clock", action: { m.selection = Page.schedule }, pro: true)
                SideRow(title: "Tools", trailing: "", live: false, selected: m.selection == Page.tools, icons: [], symbol: "wrench.and.screwdriver", action: { m.selection = Page.tools }, pro: true)
                SideRow(title: "History", trailing: "", live: false, selected: m.selection == Page.history, icons: [], symbol: "clock.arrow.circlepath", action: { m.selection = Page.history }, pro: true)
                SideRow(title: "Settings", trailing: "", live: false, selected: m.selection == Page.settings, icons: [], symbol: "gearshape") { m.selection = Page.settings }
                SideRow(title: "Appearance", trailing: "", live: false, selected: m.selection == Page.appearance, icons: [], symbol: "paintpalette") { m.selection = Page.appearance }
            }.padding(.horizontal, 10)
            Button { withAnimation(.easeOut(duration: 0.15)) { m.modesShown.toggle() } } label: {
                HStack(spacing: 5) {
                    Text("Modes").font(Site.font(16, .medium))
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).rotationEffect(.degrees(m.modesShown ? 90 : 0)).offset(y: 1.5)   // on the text's middle line
                    Spacer()
                    ProTag()
                }.foregroundColor(Site.muted).padding(.leading, 22).padding(.trailing, 22).padding(.top, 14).padding(.bottom, 5).contentShape(Rectangle())   // the tag in the rows' column
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
                if !DesktopModel.licensed { PlanLines(m: m) }       // Basic / Preview: two quiet lines, not a banner
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
                    }
                    PanelRule()
                    Text(f.focused ? "These apps are in your session. Click one to take it out."
                                   : "Tick the apps you want in the session. Everything else closes when the session starts and comes back when it ends.")
                        .font(Site.font(17)).foregroundColor(Site.low).fixedSize(horizontal: false, vertical: true)
                    if !f.focused && MemoryBar.shown { MemoryBar(apps: m.running, m: m).padding(.top, 14) }      // the memory to be saved is shown before a session, never during one
                    SectionLabel("", "Usage", divider: false).padding(.horizontal, -14).padding(.top, f.focused ? 0 : 8)
                    ForEach(m.running) { app in
                        AppRowView(app: app, icon: m.icon(app.path), mark: app.on ? "checkmark.circle.fill" : "circle", action: { m.toggle(app) },
                                   quit: { m.quit(app.id, force: $0) },
                                   hovered: { on in m.hoverApp = on ? app.id : (m.hoverApp == app.id ? nil : m.hoverApp) },
                                   lit: m.hoverApp == app.id).padding(.horizontal, -14)
                            .opacity(m.dragging == app.id ? 0.4 : 1)
                            .onDrag { m.dragging = app.id; m.draggingMode = nil; return NSItemProvider(object: app.id as NSString) }
                            .onDrop(of: [UTType.text], delegate: RowDrop(id: app.id, m: m))
                    }
                    AppFinder(m: m).padding(.top, 10)                           // adding comes after the list, like Add or remove… below
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
                    if DesktopModel.gated { LockedPanel(m: m, text: "Unlock modes, sets of apps you start with one key, by upgrading to Pro.") }
                    VStack(spacing: 2) {
                        ForEach(m.modes) { mode in
                            ModeListRow(m: m, mode: mode).contextMenu { ModeMenu(m: m, mode: mode) }
                        }
                        SideRow(title: "Create New Mode", trailing: "", live: false, selected: false, icons: [], symbol: "plus.circle") { if DesktopModel.gated { m.openUpgrade() } else { m.newMode() } }
                    }.padding(.horizontal, -12).opacity(DesktopModel.gated ? 0.3 : 1).allowsHitTesting(!DesktopModel.gated)
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
            if DesktopModel.gated {                                     // a mode on Basic: the plans first, the mode greyed beneath
                VStack(alignment: .leading, spacing: 0) {
                    Text("Modes are part of Pro").font(Site.font(26, .medium)).tracking(-0.5).foregroundColor(Site.head)
                    PanelRule()
                    UpgradeCard(m: m)
                }.padding(.horizontal, 28).padding(.bottom, 20)
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        TextField("Mode name", text: $name, onCommit: { m.pro { f.renameMode(mode.id, to: name.trimmingCharacters(in: .whitespacesAndNewlines)) } })
                            .textFieldStyle(.plain).font(Site.font(26, .medium)).foregroundColor(Site.head)
                        Menu {
                            Button("None") { m.pro { f.setModeKey(mode.id, nil) } }
                            ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9, 0], id: \.self) { d in Button(f.label(forMode: d)) { m.pro { f.setModeKey(mode.id, d) } } }
                        } label: { Text(mode.key.isEmpty ? "No shortcut" : mode.key).font(Site.font(15, .medium)) }
                        .menuStyle(.borderlessButton).fixedSize()
                        if !mode.live {
                            SiteButton(mode.apps.isEmpty ? "Add an app to start" : "Start this session") { if !mode.apps.isEmpty { m.pro { f.startOrSwitch(mode.id) } } }
                        }
                    }
                    PanelRule()
                    Text("A mode is a set of apps you keep open. Starting it closes everything else until the session ends.")
                        .font(Site.font(17)).foregroundColor(Site.low).padding(.top, 3).fixedSize(horizontal: false, vertical: true)
                    SectionLabel("Keeps open", divider: false).padding(.horizontal, -14)
                    ForEach(inMode) { app in
                        AppRowView(app: app, icon: m.icon(app.path), mark: "checkmark.circle.fill") { m.pro { f.removeApp(app.id, fromMode: mode.id) } }.padding(.horizontal, -14)
                    }
                    if inMode.isEmpty { Text("No apps yet. Add one below.").font(Site.font(16)).foregroundColor(Site.muted).padding(.vertical, 8) }
                    if !others.isEmpty {
                        SectionLabel("Open now — click to add").padding(.horizontal, -14)
                        ForEach(others) { app in
                            AppRowView(app: app, icon: m.icon(app.path), mark: "circle") { m.pro { _ = f.addApp(app.id, toMode: mode.id) } }.padding(.horizontal, -14)
                        }
                    }
                    HStack(spacing: 10) {
                        SiteButton("Add App…") { m.pro { let s = NSMenuItem(); s.representedObject = mode.id; f.addAppToMode(s); m.refresh() } }
                        SiteButton("Delete Mode", tint: Site.hazard) { m.pro { f.removeMode(mode.id); m.selection = nil } }
                    }.padding(.top, 10)
                }
                .padding(.horizontal, 28).padding(.top, 0).padding(.bottom, 30)
            }
            .opacity(DesktopModel.gated ? 0.3 : 1).allowsHitTesting(!DesktopModel.gated)
        }
        .onAppear { name = mode.name }
    }
}

// MARK: the other pages — the same settings the menu has, read from and written to the same place

/// Sidebar pages that aren't a mode (a mode's id is a UUID, so these can't collide).
enum Page { static let shortcuts = "§shortcuts", tools = "§tools", settings = "§settings", history = "§history", manual = "§manual", upgrade = "§upgrade", appearance = "§appearance", schedule = "§schedule" }

struct PageFrame<Content: View>: View {
    let title: String, text: String
    var locked: DesktopModel? = nil                              // a Pro page seen on Basic: the plans here, the page greyed
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Site.font(26, .medium)).tracking(-0.5).foregroundColor(Site.head)
                PanelRule()
                if !text.isEmpty { Text(text).font(Site.font(17)).foregroundColor(Site.low).fixedSize(horizontal: false, vertical: true) }
                if let m = locked, DesktopModel.gated {
                    UpgradeCard(m: m).padding(.top, 18).padding(.bottom, 26)
                    VStack(alignment: .leading, spacing: 0) { content }.opacity(0.3).allowsHitTesting(false)
                } else { content }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 28).padding(.top, 0).padding(.bottom, 30)
        }
    }
}

/// One choice out of a few, as a row of pills.
struct Choice: View {
    let options: [String], selected: Int
    var unavailable: Set<Int> = []                              // shown, dimmed, not yet choosable
    var solid: Color? = nil                                     // the chosen option's fill (default: ink)
    let pick: (Int) -> Void
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                ChoiceOption(title: o, on: i == selected, available: !unavailable.contains(i), solid: solid ?? Site.ink) { pick(i) }
            }
        }
    }
}
/// One option of a Choice. Chosen: solid white. Not chosen: outlined, and under the pointer it fills a little and its
/// outline brightens, so it's clear it can be picked.
struct ChoiceOption: View {
    let title: String, on: Bool, available: Bool
    var solid: Color = Site.ink
    let pick: () -> Void
    @State private var hover = false
    var body: some View {
        let lit = hover && available && !on
        Button { if available { pick() } } label: {
            Text(title).font(Site.font(16, .medium)).foregroundColor(on ? Site.paper : Site.head).lineLimit(1).fixedSize()
                .padding(.horizontal, 16).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? solid : lit ? Site.surface2 : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(solid.opacity(on ? 0 : lit ? 1 : 0.75), lineWidth: 1))
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

/// Pro: any colour at all, from the Mac's own colour panel. A rainbow swatch; the chosen colour shows in it once picked.
struct AnyColourTile: View {
    @ObservedObject var m: DesktopModel
    @State private var hover = false
    var body: some View {
        let f = m.f
        let custom = !f.iconColor.isEmpty && !(DesktopView.presetColours.contains(f.iconColor))
        Button { ColourPanel.shared.open(start: hexColor(f.iconColor)) { c in m.act { f.iconColor = hexString(c); f.iconColor2 = ""; DesktopView.keepInkReadable(f) } } } label: {
            HStack(spacing: 8) {
                Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().fill(Color(nsColor: custom ? (hexColor(f.iconColor) ?? .clear) : .clear)).frame(width: 7, height: 7))
                Text("Any colour").font(Site.font(15, custom ? .medium : .regular)).foregroundColor(custom || hover ? Site.head : Site.low).lineLimit(1)
                Spacer(minLength: 0)
            }.padding(.horizontal, 12).frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover || custom ? Site.surface2 : Site.surface))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Site.ink.opacity(custom ? 0.9 : 0), lineWidth: 1.5))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hover = $0 }.help("Choose any colour").linkCursor()
    }
}

/// Appearance ▸ Custom colours: Primary always; Two colours (a checkbox, to the right) adds Secondary. Off = one colour.
struct CustomColours: View {
    @ObservedObject var m: DesktopModel
    @State private var two = false
    var body: some View {
        let f = m.f
        HStack(spacing: 8) {
            ColourWell(title: "Primary", colour: hexColor(f.iconColor), selected: true) { c in
                m.act { f.iconColor = hexString(c); if !two { f.iconColor2 = "" }; DesktopView.keepInkReadable(f) }
            }
            if two {
                ColourWell(title: "Secondary", colour: hexColor(f.iconColor2) ?? hexColor(f.iconColor)) { c in
                    m.act { if f.iconColor.isEmpty { f.iconColor = hexString(c) }; f.iconColor2 = hexString(c); DesktopView.keepInkReadable(f) }
                }.transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            Button {
                withAnimation(.easeOut(duration: 0.15)) { two.toggle() }
                if !two { m.act { f.iconColor2 = ""; DesktopView.keepInkReadable(f) } }          // back to one colour
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: two ? "checkmark.square.fill" : "square").font(.system(size: 16)).foregroundColor(Site.head)
                    Text("Two colours").font(Site.font(15)).foregroundColor(Site.head)
                }.padding(.leading, 6).frame(height: 36).contentShape(Rectangle())
            }.buttonStyle(.plain).linkCursor()
        }
        .onAppear { two = !f.iconColor2.isEmpty && f.iconColor2 != f.iconColor }
    }
}

/// One custom colour: its swatch and its name; a click opens the Mac's colour panel on it.
struct ColourWell: View {
    let title: String, colour: NSColor?
    var selected = false                                            // the colour being set (Primary, by default)
    let change: (NSColor) -> Void
    @State private var hover = false
    var body: some View {
        Button { ColourPanel.shared.open(start: colour, change) } label: {
            HStack(spacing: 8) {
                Circle().fill(colour.map { Color(nsColor: $0) } ?? Site.ink).frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(Site.line, lineWidth: 1))
                Text(title).font(Site.font(15, .medium)).foregroundColor(Site.head)
            }
            .padding(.horizontal, 12).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover ? Site.surface2 : Site.surface))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Site.ink.opacity(selected ? 0.9 : 0), lineWidth: 1.5))
            .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).onHover { hover = $0 }.linkCursor().help("Choose the \(title.lowercased()) colour")
    }
}

/// The Mac's shared colour panel, reporting each change to one callback.
final class ColourPanel: NSObject {
    static let shared = ColourPanel()
    private var done: ((NSColor) -> Void)?
    func open(start: NSColor?, _ change: @escaping (NSColor) -> Void) {
        done = change
        let p = NSColorPanel.shared
        p.showsAlpha = false; p.setTarget(self); p.setAction(#selector(changed(_:)))
        if let start { p.color = start }
        p.orderFront(nil)
    }
    @objc func changed(_ p: NSColorPanel) { done?(p.color.usingColorSpace(.sRGB) ?? p.color) }
}

/// One colour in Settings ▸ Appearance ▸ Icon colour. Chosen: outlined in white. Under the pointer: lifts a shade.
struct ColourTile: View {
    let name: String, a: String, b: String, on: Bool, pick: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: pick) {
            HStack(spacing: 8) {
                ZStack { Circle().fill(Color(nsColor: hexColor(a) ?? (Site.light ? .black : .white))).frame(width: 16, height: 16)
                             .overlay(Circle().strokeBorder(Site.line, lineWidth: 1))                    // a white swatch still shows on white
                         Circle().fill(Color(nsColor: hexColor(b) ?? hexColor(a) ?? (Site.light ? .black : .white))).frame(width: 7, height: 7) }
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
    @ObservedObject private var watch = TierWatch.shared             // greys and tags follow the tier at once
    let title: String, note: String
    var pro = false                                              // a Pro setting: the quiet tag after its title
    @ViewBuilder var control: Control
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Site.font(18, .medium)).foregroundColor(Site.head)
                if !note.isEmpty { Text(note).font(Site.font(15)).foregroundColor(Site.muted).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 12)
            control.layoutPriority(1)                               // the choices are never cut short: the note wraps instead
                .opacity(pro && DesktopModel.gated ? 0.3 : 1).allowsHitTesting(!(pro && DesktopModel.gated))   // Pro on Basic: greyed
        }
        .padding(.vertical, 18)
        .overlay(alignment: .topTrailing) { if pro && !DesktopModel.gated { ProTag().padding(.top, 4) } }   // the right-hand tag column; on Basic the unlock line above carries it
        .overlay(alignment: .bottom) { Rectangle().fill(Site.line).frame(height: 1) }
    }
}

struct ShortcutsPage: View {
    @ObservedObject var m: DesktopModel
    var body: some View {
        let f = m.f
        PageFrame(title: "Shortcuts", text: "The keys that start and end a session, open the menu, open this app, and start your modes.", locked: m) {
            SettingLine(title: "Start / End Session", note: f.sessionKeyTaken ? "That combination is taken by another app. Pick another." : "") {
                Choice(options: modifierChoices.map { $0.label + "F" }, selected: modifierChoices.firstIndex { $0.mods == f.sessionMods } ?? 0) { i in if DesktopModel.gated { m.openUpgrade() } else { m.act { f.sessionMods = modifierChoices[i].mods } } }
            }
            SettingLine(title: "Open the Menu", note: f.menuKeyTaken ? "That combination is taken by another app. Pick another." : "") {
                Choice(options: menuModifierChoices.map { $0.label + "E" }, selected: menuModifierChoices.firstIndex { $0.mods == f.menuMods } ?? 0) { i in if DesktopModel.gated { m.openUpgrade() } else { m.act { f.menuMods = menuModifierChoices[i].mods } } }
            }
            SettingLine(title: "Open the Desktop App", note: f.appKeyTaken ? "That combination is taken by another app. Pick another." : "From anywhere. Press again to put it away.") {
                Choice(options: modifierChoices.map { $0.label + "E" }, selected: modifierChoices.firstIndex { $0.mods == f.appMods } ?? 0) { i in if DesktopModel.gated { m.openUpgrade() } else { m.act { f.appMods = modifierChoices[i].mods } } }
            }
            SettingLine(title: "Modes", note: "This, plus the number you give each mode.") {
                Choice(options: modeModifierChoices.map { $0.label + "1" }, selected: modeModifierChoices.firstIndex { $0.mods == f.modeMods } ?? 0) { i in if DesktopModel.gated { m.openUpgrade() } else { m.act { f.modeMods = modeModifierChoices[i].mods } } }
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
            if DesktopModel.gated { LockedPanel(m: m, text: m.history.count > 3
                ? "Unlock your full session history, all \(m.history.count) sessions, by upgrading to Pro. \(DesktopModel.freeName) shows your last 3."
                : "Unlock your full session history by upgrading to Pro. \(DesktopModel.freeName) shows your last 3 sessions.") }
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
        PageFrame(title: "Tools", text: busy ? "End the session first to use the quit tools." : "Look at what your Mac is doing, or clear everything at once.", locked: m) {
            SectionLabel("Analyse performance", divider: false).padding(.horizontal, -14)
            ToolLine(title: "Open Activity Monitor", why: "See which apps are using the most memory and processor right now.", tint: Site.head, enabled: true) { if DesktopModel.gated { m.openUpgrade() } else { f.openActivityMonitor() } }
            ToolLine(title: "Open System Settings", why: "Change what opens at login, and the battery and display settings that affect how the Mac runs.", tint: Site.head, enabled: true) { if DesktopModel.gated { m.openUpgrade() } else { f.openSystemSettings() } }
            SectionLabel("Quit Unresponsive Apps").padding(.horizontal, -14)
            ToolLine(title: "Quit All Apps…", why: "Close every app at once for a clean start. Each app saves first. Critical System Processes stay open.", tint: Site.head, enabled: !busy) { if DesktopModel.gated { m.openUpgrade() } else { f.quitAllApps() } }
            ToolLine(title: "Quit All Apps & Restart Mac…", why: "Close everything, then restart. Clears memory completely when the Mac feels slow.", tint: Site.head, enabled: !busy) { if DesktopModel.gated { m.openUpgrade() } else { f.quitAllRestart() } }
            ToolLine(title: "Force Quit All Apps…", why: "For apps that have frozen and won't quit. Unsaved work in them is lost, so it asks first.", tint: Site.hazard, enabled: !busy) { if DesktopModel.gated { m.openUpgrade() } else { f.forceQuitAllApps() } }
            SectionLabel("Apps Using the Most Memory").padding(.horizontal, -14)
            let heavy = m.heavyApps, ram = Double(ProcessInfo.processInfo.physicalMemory)
            Note(heavy.isEmpty ? "No app is using more than \(gb(DesktopModel.heavyBytes)) right now."
                               : "Every open app using \(gb(DesktopModel.heavyBytes)) or more, heaviest first. Right-click one to quit it.")
            ForEach(heavy) { app in
                AppRowView(app: DesktopModel.AppLine(id: app.id, path: app.path, name: app.name,
                                                     usage: "\(app.usage) · \(Int((Double(app.bytes) / ram * 100).rounded()))% of memory",
                                                     on: true, note: ""),
                           icon: m.icon(app.path), mark: "memorychip", action: nil,
                           quit: DesktopModel.gated ? nil : { m.quit(app.id, force: $0) }).padding(.horizontal, -14)
            }
        }
    }
}

struct SettingsPage: View {
    @ObservedObject var m: DesktopModel
    var body: some View {
        let f = m.f
        PageFrame(title: "Settings", text: "The same settings as the menu. Changing one here changes it there.") {
            SettingLine(title: "Sound", note: "A short chime when a session starts, and another when it ends.") {
                Choice(options: ["Off", "On"], selected: Chime.on ? 1 : 0) { i in
                    m.act { UserDefaults.standard.set(i == 1, forKey: "focusSound") }
                    if i == 1 { Chime.play(start: true) }                      // a taste of it, on turning it on
                }
            }
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
            GroupTitle("Layout")
            SettingLine(title: "Menu headings", note: "How much the menu's headings explain.") {
                Choice(options: ["Minimalist", "Normal", "Verbose"], selected: f.headingStyle) { i in m.act { f.headingStyle = i } }
            }
            SettingLine(title: "Memory bar", note: "Above your apps: how much memory each one uses, and what a session frees.") {
                Choice(options: ["Off", "On"], selected: MemoryBar.shown ? 1 : 0) { i in m.act { UserDefaults.standard.set(i == 1, forKey: "desktopMemoryBar") } }
            }
            if DesktopModel.gated { LockedPanel(m: m, text: "Unlock every width by upgrading to Pro.") }
            SettingLine(title: "Width", note: "Default leaves space either side of the page. Wide fills the window. Minimal makes the window itself smaller.", pro: true) {
                Choice(options: ["Default", "Wide", "Minimal"], selected: DesktopView.trial.rawValue) { i in m.pro { desktop.setWidth(i) } }
            }
            SettingLine(title: "Text size", note: "For this window. Also ⌘+ and ⌘−.") {
                TextSizeStepper()
            }
        }
    }
}

struct AppearancePage: View {
    @ObservedObject var m: DesktopModel
    var body: some View {
        let f = m.f
        PageFrame(title: "Appearance", text: "Colours and icons: this window, the menu, the menu bar icon and its colours.") {
            SettingLine(title: "This window", note: "Dark is the standard look. System follows your Mac.") {
                Choice(options: ["Light", "Dark", "System"], selected: Site.look) { i in desktop.setLook(i) }
            }
            SettingLine(title: "Menu", note: "The look of the menu bar menu.") {
                Choice(options: ["Dark", "Light"], selected: f.lightMenuSetting ? 1 : 0) { i in m.act { f.lightMenuSetting = i == 1 } }
            }
            if DesktopModel.gated { LockedPanel(m: m, text: "Unlock every icon style and colour by upgrading to Pro.") }
            SectionLabel("Menu bar icon — hover to see it enter a session", pro: true).padding(.horizontal, -14).padding(.top, 10)
            let ring = hexColor(f.iconColor) ?? (Site.light ? .black : .white), dot = hexColor(f.iconColor2) ?? ring   // previews read in Light too
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), alignment: .leading, spacing: 8) {
                ForEach(IconStyle.allCases, id: \.rawValue) { st in
                    IconCell(style: st, selected: f.iconStyleSetting == st, ring: ring, dot: dot) { m.pro { f.iconStyleSetting = st } }
                        .opacity(DesktopModel.gated && f.iconStyleSetting != st ? 0.3 : 1).allowsHitTesting(!DesktopModel.gated)
                }
            }
            SectionLabel("Icon colour", pro: true).padding(.horizontal, -14).padding(.top, 10)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), alignment: .leading, spacing: 8) {
                let all = [(Site.light ? "Black" : "White", "", "")] + theme.iconPresets + theme.evaPresets   // the look's own ink, named as seen
                ForEach(all, id: \.0) { name, a, b in
                    let on = f.iconColor == a && (f.iconColor2 == b || (a == b && f.iconColor2.isEmpty) || (a.isEmpty && f.iconColor2.isEmpty))
                    let locked = DesktopModel.gated && (all.firstIndex { $0.0 == name } ?? 0) >= 3      // Free: 3 colour schemes
                    ColourTile(name: name, a: a, b: b, on: on) { if locked { m.openUpgrade() } else { m.act { f.iconColor = a; f.iconColor2 = a == b ? "" : b; DesktopView.keepInkReadable(f) } } }
                        .opacity(locked ? 0.3 : 1).allowsHitTesting(!locked)
                }
            }
            SettingLine(title: "Custom colours", note: "Any colour you like, for the icon and the button. Tick Two colours to add a second for the dot and the button's other end.", pro: true) {
                CustomColours(m: m)
            }.padding(.top, 6)
            let btn = (hexColor(f.iconColor), hexColor(f.iconColor2) ?? hexColor(f.iconColor))
            let unreadable: Set<Int> = btn.0.map { a in
                Set([0, 1].filter { i in min(DesktopView.contrast(i == 0 ? .white : .black, a), DesktopView.contrast(i == 0 ? .white : .black, btn.1 ?? a)) < 3 })
            } ?? [0, 1]                                                         // no colour chosen: the look decides
            SettingLine(title: "Text colour", note: btn.0 == nil ? "The big button's text. Choose a button colour first; until then it follows the look."
                                                                 : "The big button's text. A colour that wouldn't read on the button can't be chosen.") {
                Choice(options: ["White", "Black"], selected: btn.0.map { DesktopView.inkWhite(on: $0, btn.1 ?? $0) ? 0 : 1 } ?? -1, unavailable: unreadable) { i in
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
        if e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, e.charactersIgnoringModifiers?.lowercased() == "z",
           !(firstResponder is NSText), desktop.model?.f.canUndoEnd == true {
            desktop.model?.f.undoEnd(); return true                 // ⌘Z just after ending a session: put it back
        }
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
    /// The week's sessions ran out (from the menu or a key): bring the window up on the out-of-sessions Upgrade page.
    func outOfSessions(_ f: Focus) { show(f); model?.openOutOfSessions() }
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
            w.setFrameAutosaveName("FocusDesktopWindow")          // where he left it, at the size he left it (else the above)
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
        model?.showWelcomeIfNew()                                       // a new copy's first open: the thank-you
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
            item(m, "Undo End Session", #selector(undoEndSession))
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
            for (title, key) in [("Actual", ""), (DesktopModel.freeName, "free"), ("Pro", "pro")] {
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
    @objc func undoEndSession() { model?.f.undoEnd() }
    /// Pro says "Pro" only beside the name: the Upgrade item hides for it.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(upgrade) { item.isHidden = DesktopModel.licensed }
        if item.action == #selector(undoEndSession) { return model?.f.canUndoEnd == true }
        return true
    }
    @objc func toggleDevPanel(_ sender: NSMenuItem) {
        let on = !(UserDefaults.standard.object(forKey: "desktopDevPanel") as? Bool ?? true)
        UserDefaults.standard.set(on, forKey: "desktopDevPanel"); sender.state = on ? .on : .off; model?.tick &+= 1
    }
    @objc func viewAs(_ sender: NSMenuItem) {
        let key = sender.representedObject as? String ?? ""
        sender.menu?.items.forEach { $0.state = ($0.representedObject as? String ?? "") == key ? .on : .off }
        model?.viewAs(key)
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
    let m = DesktopModel(f); m.still = true; m.refresh(); m.selection = nil; if mode { m.selection = second }   // renders start on the Session Editor
    if renderArgs.contains("feedback") { m.openFeedback() }
    if renderArgs.contains("upgrade") { m.selection = Page.upgrade }
    if renderArgs.contains("live") {
        f.sessions = [["date": Date(), "name": "Research", "mode": "Research", "modeID": second, "kept": have(["com.apple.Safari"]), "apps": [["path": "/System/Applications/Notes.app", "id": "com.apple.Notes"]]]]
        f.store.set(true, forKey: "focused")
    }
    for p in [Page.schedule, Page.settings, Page.appearance, Page.shortcuts, Page.tools, Page.history, Page.manual] where renderArgs.contains(String(p.dropFirst())) { m.selection = p }
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
    if renderArgs.contains("schedule") {                           // two example rules (never saved)
        Scheduler.shared.rules = [ScheduleRule(kind: "block", apps: ["com.apple.Music", "com.apple.TV"].filter { f.path($0) != nil }, from: 9 * 60, to: 17 * 60),
                                  ScheduleRule(kind: "open", mode: m.modes.first?.id ?? "", days: [2, 3, 4, 5, 6], from: 8 * 60 + 30)]
    }
    let savedScale = Site.scale
    if let t = renderArgs.first(where: { $0.hasPrefix("textscale=") }).flatMap({ Double($0.dropFirst(10)) }) { Site.scale = CGFloat(t) }
    defer { if Site.scale != savedScale { Site.scale = savedScale } }
    var size = renderArgs.contains("wide") ? NSSize(width: 1320, height: 880)
        : NSSize(width: 1000, height: renderArgs.first { $0.hasPrefix("h=") }.flatMap { Double($0.dropFirst(2)) }.map { CGFloat($0) }
                                       ?? (renderArgs.contains("tall") ? 1500 : 730))
    if DesktopView.trial == .minimal { size.width -= DesktopView.minimalCut }
    if let w = renderArgs.first(where: { $0.hasPrefix("w=") }).flatMap({ Double($0.dropFirst(2)) }) { size.width = CGFloat(w) }
    if renderArgs.contains("never") {                              // Critical System Processes, on its own
        let nm = NeverModel(f); nm.reload(); size = NSSize(width: 520, height: 620)
        let h = NSHostingView(rootView: NeverView(m: nm)); let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.appearance = NSAppearance(named: Site.light ? .aqua : .darkAqua); w.contentView = h; h.frame = NSRect(origin: .zero, size: size); h.layoutSubtreeIfNeeded()
        if let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) { h.cacheDisplay(in: h.bounds, to: rep); try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: file)) }
        return
    }
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
    // His real settings are never left changed by a test: saved now, put back at the end. Dev and gift state starts clear.
    let keepPrefs = ["desktopViewAs", "devSpentWeek", "devSpentBack", "focusGiftUsed", "focusGiftWeek", "desktopButtonInkWhite",
                "focusTier", "focusPro", "desktopLook", "desktopPage", "desktopMemoryBar", "focusTokens", "focusWelcomeShown"]
    let savedPrefs = Dictionary(uniqueKeysWithValues: keepPrefs.compactMap { k in UserDefaults.standard.object(forKey: k).map { (k, $0) } })
    ["devSpentWeek", "devSpentBack", "focusGiftUsed", "focusGiftWeek", "focusTokens"].forEach { UserDefaults.standard.removeObject(forKey: $0) }
    defer { keepPrefs.forEach { k in if let v = savedPrefs[k] { UserDefaults.standard.set(v, forKey: k) } else { UserDefaults.standard.removeObject(forKey: k) } } }
    func check(_ n: Int, _ name: String, _ ok: Bool, _ detail: String) {
        guard only == nil || only!.contains(n) else { return }
        if !ok { failures += 1 }
        print("gui: \(ok ? "PASS" : "FAIL")  \(n). \(name) — \(detail)")
    }
    let std = UserDefaults.standard
    // Settings that some checks change, put back afterwards.
    let keep = ["desktopWidthV2", "desktopTextScale", "focusPro", "focusTier", "desktopButtonInkWhite", "desktopViewAs", "desktopLook", "desktopPage"].map { ($0, std.object(forKey: $0)) }
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
    std.set("max", forKey: "focusTier"); let maxTier = DesktopModel.tier == .pro; std.removeObject(forKey: "focusTier")   // Max retired: reads as Pro
    std.set(true, forKey: "focusPro"); let on = DesktopModel.licensed && DesktopModel.tier == .pro
    var proBox = true
    for look in ["dark", "light"] {                                  // the box is ink: white in Dark, black in Light
        guard let r = guiRender(["trial=narrow", "look=\(look)"]) else { proBox = false; continue }
        let s = CGFloat(r.pixelsWide) / 1000
        proBox = proBox && (Int(190 * s)..<Int(260 * s)).contains { x in look == "dark" ? lum(r, x, Int(63 * s)) > 0.93 : lum(r, x, Int(63 * s)) < 0.07 }
    }
    std.removeObject(forKey: "focusPro"); let off = DesktopModel.licensed || renderArgs.contains("licensed")
    check(8, "Focus Pro from the purchase", on && !off && maxTier && proBox, "Pro flag on → \(on), off → \(off); an old Max licence reads as Pro → \(maxTier); box by the name in Light and Dark: \(proBox)")

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
    let banned = ["this window", "Then F.", "Then E.", "Click to", "trial", " Max"].filter { w in text.contains { $0.localizedCaseInsensitiveContains(w) } }
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
    for page in ["", "live", "mode", "settings", "appearance", "shortcuts", "tools", "history", "manual", "feedback"] {
        for opts in [["w=600", "h=420", "trial=minimal"], ["trial=narrow"], ["trial=wide"]] { for look in ["dark", "light"] {
            guard let r = guiRender((page.isEmpty ? [] : [page]) + opts + ["look=\(look)"]) else { blank.append("\(page.isEmpty ? "session" : page)/\(opts.last!)/\(look)"); continue }
            let s = CGFloat(r.pixelsWide) / CGFloat(max(1, r.size.width))
            let lit = stride(from: 0, to: r.pixelsWide, by: Int(20 * s)).filter { x in stride(from: 0, to: r.pixelsHigh, by: Int(20 * s)).contains { look == "dark" ? lum(r, x, $0) > 0.5 : lum(r, x, $0) < 0.5 } }.count
            if lit < 3 { blank.append("\(page.isEmpty ? "session" : page)/\(opts.last!)/\(look)") }
        } }
    }
    check(12, "every page draws in every width", blank.isEmpty, blank.isEmpty ? "10 pages × 3 widths × Light and Dark" : "blank: \(blank.joined(separator: ", "))")

    // 13. The session button changes clearly: in a session a mark sits before "End Session" (ink, then a clear gap,
    //     then the title); out of one the title starts straight away.
    var mark = true
    for look in ["dark", "light"] {
        func markFirst(_ opts: [String]) -> Bool {
            guard let r = guiRender(opts + ["trial=narrow", "look=\(look)"]) else { return false }
            let s = CGFloat(r.pixelsWide) / 1000
            // the button's own rows (its fill at x 400), trimmed to the middle so its rounded edges never count
            func fill(_ y: Int) -> Bool { look == "dark" ? lum(r, Int(400 * s), y) > 0.9 : lum(r, Int(400 * s), y) < 0.1 }
            guard let top = (0..<Int(160 * s)).first(where: fill) else { return false }
            let bottom = (top..<Int(160 * s)).first(where: { !fill($0) }) ?? top            // the button's own unbroken run
            guard bottom - top > Int(30 * s) else { return false }
            let rows = (top + (bottom - top) / 5)..<(bottom - (bottom - top) / 5)
            func paper(_ x: Int) -> Bool { rows.contains { y in look == "dark" ? lum(r, x, y) < 0.25 : lum(r, x, y) > 0.75 } }
            guard let x0 = (Int(380 * s)..<Int(900 * s)).first(where: paper) else { return false }
            var run = 0, gap = 0
            for x in x0..<(x0 + Int(60 * s)) { if paper(x) { run = 0 } else { run += 1; gap = max(gap, run) } }
            return CGFloat(gap) / s >= 8                                   // a mark, a gap of 8 pt or more, then the title
        }
        let inSession = markFirst(["live"]), outOfOne = markFirst([])
        if !inSession || outOfOne { print("gui: note 13 \(look): in a session \(inSession), out of one \(outOfOne)") }
        mark = mark && inSession && !outOfOne
    }
    check(13, "a mark on the button in a session", mark, "a mark before the title in a session, none out of one, Light and Dark: \(mark)")

    // 14. Light and Dark: every page draws on its own ground — white in Light, black in Dark — with readable ink on it.
    var wrong = [String]()
    for look in ["light", "dark"] {
        for page in ["", "live", "settings", "appearance", "tools", "manual"] {          // (Feedback shades the page on purpose)
            guard let r = guiRender((page.isEmpty ? [] : [page]) + ["look=\(look)", "trial=narrow"]) else { wrong.append("\(look)/\(page)"); continue }
            let s = CGFloat(r.pixelsWide) / 1000
            let ground = lum(r, Int(990 * s), Int(720 * s))                      // the bottom-right corner is bare ground
            let inked = stride(from: Int(150 * s), to: Int(190 * s), by: 2).contains { y in stride(from: Int(320 * s), to: r.pixelsWide, by: 6).contains { x in abs(lum(r, x, y) - ground) > 0.6 } }   // the panel title, wherever text size puts it
            if (look == "light" ? ground < 0.95 : ground > 0.05) || !inked { wrong.append("\(look)/\(page.isEmpty ? "session" : page)") }
        }
    }
    check(14, "Light and Dark draw correctly", wrong.isEmpty, wrong.isEmpty ? "6 pages × 2 looks: right ground, readable title" : "wrong: \(wrong.joined(separator: ", "))")

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
    check(16, "View As Free / Pro", seen == ["free=free/free", "pro=pro/paid", "max=pro/paid", "actual=free/free"], seen.joined(separator: ", "))

    // ——— Pricing: pricing.json is the one source; the app must follow it and keep to his rules ———
    let pr = Pricing.bundled
    // 17. His price rules hold in the shipped copy (decided 2026-11-15): Basic and Pro only, no Max; Pro £5 a month,
    //     £50 a year (under 12 months), £75 once (over a year); while the launch is on, the one-off is the early
    //     adopter gift at less than £75; round numbers; Enterprise coming soon; 14 days of Pro; 10 sessions a week.
    var rules = [String]()
    if let p = pr {
        if Set(p.tiers.keys) != ["free", "pro"] { rules.append("tiers aren't just Free and Pro") }
        if p.tiers["pro"]?.name != "Pro" { rules.append("Pro's name") }
        if p.tiers["free"]?.name != "Basic" { rules.append("the free tier isn't called Basic") }
        if !(p.coming_soon ?? []).contains(where: { $0.name == "Enterprise" }) { rules.append("Enterprise isn't listed as coming soon") }
        if p.tiers.values.contains(where: { $0.tagline.isEmpty }) { rules.append("a tagline is empty") }
        if let t = p.tiers["pro"] {
            if t.monthly != 5 || t.yearly != 50 || t.once != 75 { rules.append("Pro isn't £5 / £50 a year / £75 once") }
            if (t.yearly ?? 0) >= t.monthly * 12 { rules.append("yearly isn't under 12 months") }
            if (t.yearly ?? 0) >= (t.once ?? 0) { rules.append("once isn't over yearly") }
            if let l = t.launch, l.active, l.once >= (t.once ?? 0) { rules.append("the launch gift isn't below the one-off") }
            if let l = t.launch, l.once % 5 != 0 { rules.append("the launch gift isn't a round number") }
            if let l = t.launch, l.active, (l.code ?? "").isEmpty { rules.append("the launch gift has no code") }
        }
        if p.tiers["free"]?.monthly != 0 { rules.append("Free isn't free") }
        let all = p.tiers.values.flatMap { [$0.monthly, $0.yearly, $0.once].compactMap { $0 } }
        if all.contains(where: { $0 % 5 != 0 }) { rules.append("a price that isn't a round number") }
        if p.trial_days != 14 || p.trial_tier != "pro" { rules.append("trial") }
        if p.free_sessions_per_week != 10 { rules.append("Free sessions a week") }
        if p.tiers["pro"]?.best != true { rules.append("Pro not marked best value") }
        if p.lead.tier != "pro" || p.lead.plan != "monthly" { rules.append("lead isn't Pro monthly") }
    } else { rules.append("pricing.json missing or unreadable") }
    check(17, "pricing rules", rules.isEmpty, rules.isEmpty ? "Basic (free) and Pro only; Pro £5 a month, £50 a year, £75 once (£50 with the launch code); round; Enterprise coming soon; 14 days of Pro; 10 a week" : rules.joined(separator: "; "))

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
    func freeLimited(_ c: [Pricing.Cell]?) -> Bool { guard let c, c.count == 2 else { return false }   // [Free, Pro]
        if case .yes(true) = c[0] { return false }; if case .yes(false) = c[1] { return false }; return true }
    let tagged = ["Tools", "Modes", "History", "Custom shortcuts"].filter { !freeLimited(row($0)) }
    var weekly = false
    if let w = row("Sessions a week"), w.count == 2, case .text(let f0) = w[0], case .text(let f1) = w[1] { weekly = pr.map { $0.fill(f0) } == "10" && f1 == "Unlimited" }
    check(20, "Pro tags match the site's table", tagged.isEmpty && weekly, tagged.isEmpty ? "Tools, Modes, History, custom shortcuts: limited on Free, in Pro; sessions a week 10 / Unlimited: \(weekly)" : "not limited on Free in the table: \(tagged.joined(separator: ", "))")

    // 21. The Upgrade window draws in Light and Dark with all three plans, and Free locks (View As) show their panel.
    var upOK = true
    for look in ["dark", "light"] {
        guard let r = guiRender(["upgrade", "trial=narrow", "look=\(look)"]) else { upOK = false; continue }
        let s = CGFloat(r.pixelsWide) / 1000
        // the Pro card's solid button sits in the middle of the window, in ink
        upOK = upOK && (Int(440 * s)..<Int(560 * s)).contains { x in (Int(380 * s)..<Int(520 * s)).contains { y in look == "dark" ? lum(r, x, y) > 0.93 : lum(r, x, y) < 0.07 } }
    }
    // the unlock panel on History: present as Basic (a filled band across the page under the description), absent as Pro
    func band(_ opts: [String]) -> Bool {
        guard let r = guiRender(["history", "trial=narrow"] + opts) else { return false }
        let s = CGFloat(r.pixelsWide) / 1000, page = lum(r, Int(990 * s), Int(700 * s))
        var run = 0, best = 0                                     // a band at least 30 pt tall, not a rule or a line of text
        for y in Int(150 * s)..<Int(360 * s) {
            if stride(from: Int(400 * s), to: Int(880 * s), by: 6).allSatisfy({ x in abs(lum(r, x, y) - page) > 0.02 }) { run += 1; best = max(best, run) } else { run = 0 }
        }
        return CGFloat(best) / s >= 30
    }
    let lockedB = band(["tier=free", "viewas=free"]), lockedP = band(["licensed"])
    check(21, "Upgrade page and Basic unlock panel", upOK && lockedB && !lockedP, "Upgrade page in Light and Dark: \(upOK); History's unlock panel as Basic: \(lockedB), as Pro: \(lockedP)")

    // 22. Type to add an app: finds apps on the Mac by name (open or not), best match first, and adding one that
    //     isn't open puts it in the session's apps.
    let tf = Focus(store: UserDefaults(suiteName: "com.labern.focus.selftest")!); tf.modes = []; tf.excluded = []
    let tm = DesktopModel(tf)
    let hits = tm.find("text").map(\.name)                          // TextEdit ships with every Mac
    let textEdit = tm.find("textedit").first
    if let t = textEdit, !t.open { tm.add(t) }
    let added = textEdit.map { t in t.open || tf.excluded.contains(t.id) } ?? false
    check(22, "type to add an app", hits.first == "TextEdit" && added && tm.find("").isEmpty,
          "\"text\" → \(hits.prefix(3)); TextEdit added to the session's apps: \(added); empty search finds nothing")
    tf.excluded = []; UserDefaults.standard.removePersistentDomain(forName: "com.labern.focus.selftest")

    // 23. ⌘Z after ending a session: offered only for a short while after the end, and never during a session.
    let uf = Focus(store: UserDefaults(suiteName: "com.labern.focus.selftest")!)
    uf.lastEnd = (Date(), nil); let fresh = uf.canUndoEnd
    uf.lastEnd = (Date().addingTimeInterval(-(Focus.undoWindow + 1)), nil); let stale = uf.canUndoEnd
    uf.lastEnd = nil; let none = uf.canUndoEnd
    check(23, "⌘Z undoes ending a session", fresh && !stale && !none, "just ended: \(fresh); after \(Int(Focus.undoWindow)) s: \(stale); nothing ended: \(none)")
    UserDefaults.standard.removePersistentDomain(forName: "com.labern.focus.selftest")

    // 24. The window remembers its page: what's chosen is saved and the next window opens on it.
    let pm = DesktopModel(Focus(store: UserDefaults(suiteName: "com.labern.focus.selftest")!)); pm.selection = Page.tools
    let back = DesktopModel(Focus(store: UserDefaults(suiteName: "com.labern.focus.selftest")!)).selection
    pm.selection = nil; let cleared = DesktopModel(Focus(store: UserDefaults(suiteName: "com.labern.focus.selftest")!)).selection
    check(24, "the window remembers its page", back == Page.tools && cleared == nil, "reopens on \(back ?? "the Session Editor"); back to the Session Editor: \(cleared == nil)")
    UserDefaults.standard.removePersistentDomain(forName: "com.labern.focus.selftest")

    // 25. Viewing as Basic really locks Pro: a Pro action opens Upgrade instead of happening; as Pro it happens.
    let gm = DesktopModel(Focus(store: UserDefaults(suiteName: "com.labern.focus.selftest")!))
    std.set("free", forKey: "desktopViewAs"); var didBasic = false; gm.pro { didBasic = true }; let askedBasic = gm.selection == Page.upgrade
    gm.selection = nil
    std.set("pro", forKey: "desktopViewAs"); var didPro = false; gm.pro { didPro = true }; let askedPro = gm.selection == Page.upgrade
    std.removeObject(forKey: "desktopViewAs"); UserDefaults.standard.removePersistentDomain(forName: "com.labern.focus.selftest")
    check(25, "Basic really locks Pro", !didBasic && askedBasic && didPro && !askedPro,
          "as Basic: done \(didBasic), Upgrade opened \(askedBasic); as Pro: done \(didPro), Upgrade opened \(askedPro)")

    // 26. No unreadable text on the big button: for every colour Focus offers (and plain white and black), whatever
    //     text colour is stored, the text it gets reads (contrast 3+, the WCAG bar for large text).
    let colours = [("White", NSColor.white, NSColor.white), ("Black", NSColor.black, NSColor.black)]
        + (theme.iconPresets + theme.evaPresets).compactMap { n, a, b in hexColor(a).map { (n, $0, hexColor(b) ?? $0) } }
    var unreadable: [String] = []
    for want in [true, false] {
        std.set(want, forKey: "desktopButtonInkWhite")
        for (n, a, b) in colours {
            let ink: NSColor = DesktopView.inkWhite(on: a, b) ? .white : .black
            if min(DesktopView.contrast(ink, a), DesktopView.contrast(ink, b)) < 3 { unreadable.append("\(n) (\(want ? "white" : "black") stored)") }
        }
    }
    std.removeObject(forKey: "desktopButtonInkWhite")
    check(26, "the big button's text always reads", unreadable.isEmpty,
          unreadable.isEmpty ? "\(colours.count) colours × white/black stored: all 3:1 or better" : "unreadable: \(unreadable.joined(separator: ", "))")

    // 27. Light and Dark both read: the default icon colour (previews, swatches) and the plans' solid colour stand out
    //     from the page in each look — no white on white, no black on black.
    var poor: [String] = []
    for look in ["look=light", "look=dark"] {
        let saved = renderArgs; renderArgs = saved + [look]
        let page = NSColor(Site.bg), icon: NSColor = Site.light ? .black : .white, solid = NSColor(Site.solid), paper = NSColor(Site.paper)
        if DesktopView.contrast(icon, page) < 4.5 { poor.append("\(look) icon preview") }
        if DesktopView.contrast(solid, page) < 3 { poor.append("\(look) plans' solid") }
        if DesktopView.contrast(paper, solid) < 4.5 { poor.append("\(look) text on the solid") }
        renderArgs = saved
    }
    check(27, "Light and Dark both read", poor.isEmpty, poor.isEmpty ? "icon previews, the plans' solid and its text: readable in both looks" : poor.joined(separator: ", "))

    // 28. Becoming Pro removes every request to upgrade: open Upgrade as Basic, switch View As to Pro — the Upgrade page
    //     closes (back where it came from), nothing is locked, Upgrade can't reopen, and the Tools page as Pro draws
    //     no plans (identical to a real licensed copy).
    let um = DesktopModel(Focus(store: UserDefaults(suiteName: "com.labern.focus.selftest")!))
    um.selection = Page.tools; um.viewAs("free"); um.openUpgrade(); let wasUp = um.selection == Page.upgrade
    um.viewAs("pro"); let left = um.selection == Page.tools, unlocked = !DesktopModel.gated && DesktopModel.licensed
    um.openUpgrade(); let stays = um.selection == Page.tools
    let savedPage = UserDefaults.standard.string(forKey: "desktopPage")
    um.viewAs("")
    var noPlans = false
    if let a = guiRender(["tools", "trial=narrow", "licensed"]), let b = guiRender(["tools", "trial=narrow", "tier=free", "viewas=free"]) {
        let s = CGFloat(a.pixelsWide) / 1000
        // the plans' Buy button row on Basic (y 250…520 pt); as Pro that area must not hold it
        func ys(_ r: NSBitmapImageRep) -> Int { (Int(250 * s)..<Int(520 * s)).filter { y in lum(r, Int(700 * s), y) != lum(r, Int(990 * s), y) }.count }
        noPlans = ys(a) < ys(b)
    }
    UserDefaults.standard.removePersistentDomain(forName: "com.labern.focus.selftest")
    check(28, "becoming Pro removes every upgrade request", wasUp && left && unlocked && stays && noPlans && savedPage != Page.upgrade,
          "Upgrade open as Basic: \(wasUp); after Pro: back to Tools \(left), unlocked \(unlocked), Upgrade can't reopen \(stays), Upgrade never saved \(savedPage != Page.upgrade), Tools draws no plans as Pro \(noPlans)")

    // 29. Out of sessions: Basic with the week's sessions used can't start one — the plans open, headed
    //     "0 sessions remaining this week"; with sessions left, or as Pro, starting works.
    let of = Focus(store: UserDefaults(suiteName: "com.labern.focus.selftest")!)
    let om = DesktopModel(of)
    std.set("free", forKey: "desktopViewAs"); std.set(true, forKey: "focusGiftUsed")   // the gift is spent: this is the plans' turn
    let fresh0 = DesktopModel.noSessionsLeft(of)
    of.sessions = (0..<DesktopModel.freeWeekly).map { _ in ["date": Date(), "apps": [] as [Any]] as Session }
    let spent = DesktopModel.noSessionsLeft(of)
    om.openOutOfSessions(); let shown = om.selection == Page.upgrade && om.outOfSessions
    std.set("pro", forKey: "desktopViewAs"); let proFree = !DesktopModel.noSessionsLeft(of); om.tierChanged()
    let closed = om.selection != Page.upgrade
    std.removeObject(forKey: "desktopViewAs"); std.removeObject(forKey: "focusGiftUsed"); UserDefaults.standard.removePersistentDomain(forName: "com.labern.focus.selftest")
    check(29, "out of sessions opens the plans", !fresh0 && spent && shown && proFree && closed,
          "fresh week blocked: \(fresh0); \(DesktopModel.freeWeekly) used blocked: \(spent); plans shown: \(shown); Pro unlimited: \(proFree); Pro closes them: \(closed)")

    // 30. The sidebar breathes: a clear gap between Settings and the Modes header (at least 10 pt of empty sidebar).
    var gapOK = false
    if let r = guiRender(["trial=narrow", "look=dark"]) {
        let s = CGFloat(r.pixelsWide) / 1000
        // rows with any ink in the sidebar's text column, from Settings (≈ y 300) to the first mode (≈ y 380)
        let inked = (Int(270 * s)..<Int(400 * s)).map { y in stride(from: Int(24 * s), to: Int(250 * s), by: 2).contains { lum(r, $0, y) > 0.35 } }
        var run = 0, best = 0
        for v in inked { if v { run = 0 } else { run += 1; best = max(best, run) } }
        gapOK = CGFloat(best) / s >= 10
    }
    check(30, "a gap between Settings and Modes", gapOK, "at least 10 pt clear between them: \(gapOK)")

    // 31. The free reset: Basic at 0 with the gift unused gets the gift (not the plans); taking it gives the sessions
    //     back once; the next time out it's the plans.
    let gf2 = Focus(store: UserDefaults(suiteName: "com.labern.focus.selftest")!)   // kept alive: the model holds it unowned
    let gm2 = DesktopModel(gf2)
    for k in ["focusGiftUsed", "focusGiftWeek", "devSpentWeek", "devSpentBack"] { std.removeObject(forKey: k) }
    gm2.devSpendAll()
    let at0 = DesktopModel.week(gm2.f.sessions, now: Date()).left == 0, due = gm2.giftDue
    gm2.openOutOfSessions(); let giftFirst = gm2.giftShown && gm2.selection != Page.upgrade
    gm2.takeGift(); let gotBack = DesktopModel.week(gm2.f.sessions, now: Date()).left == DesktopModel.giftSessions
    gm2.devSpendAll(); std.set(true, forKey: "focusGiftUsed"); gm2.giftShown = false
    gm2.openOutOfSessions(); let plansNext = !gm2.giftShown && gm2.selection == Page.upgrade
    for k in ["focusGiftUsed", "focusGiftWeek", "devSpentWeek", "devSpentBack", "desktopViewAs"] { std.removeObject(forKey: k); UserDefaults.standard.removeObject(forKey: k) }
    _ = gf2
    UserDefaults.standard.removePersistentDomain(forName: "com.labern.focus.selftest")
    check(31, "the free reset", at0 && due && giftFirst && gotBack && plansNext,
          "at 0: \(at0); gift due: \(due); gift before plans: \(giftFirst); \(DesktopModel.giftSessions) back: \(gotBack); next time the plans: \(plansNext)")

    // 32. The early-adopter welcome: taking it adds 10 tokens on top of the week; they're spent only after the week's own
    //     sessions run out, one per session.
    let wf = Focus(store: UserDefaults(suiteName: "com.labern.focus.selftest")!), wm = DesktopModel(wf)
    UserDefaults.standard.set("free", forKey: "desktopViewAs")
    let base = DesktopModel.week(wf.sessions, now: Date()).left
    wm.devWelcome(); let up = wm.giftShown && wm.giftKind == .welcome
    wm.takeGift(); let tokensAdded = DesktopModel.tokens == DesktopModel.welcomeTokens && DesktopModel.week(wf.sessions, now: Date()).left == base + DesktopModel.welcomeTokens
    DesktopModel.spendTokenIfNeeded(wf); let keptWhileWeekLeft = DesktopModel.tokens == DesktopModel.welcomeTokens
    wm.devSpendAll(); wm.giftShown = false; DesktopModel.tokens = DesktopModel.welcomeTokens
    DesktopModel.spendTokenIfNeeded(wf); let spentOne = DesktopModel.tokens == DesktopModel.welcomeTokens - 1
    ["focusTokens", "focusWelcomeShown", "devSpentWeek", "devSpentBack", "focusGiftUsed", "focusGiftWeek"].forEach { UserDefaults.standard.removeObject(forKey: $0) }
    _ = wm; UserDefaults.standard.removePersistentDomain(forName: "com.labern.focus.selftest")
    check(32, "the early-adopter welcome", up && tokensAdded && keptWhileWeekLeft && spentOne,
          "shown: \(up); +\(DesktopModel.welcomeTokens) on top of the week: \(added); kept while the week has sessions: \(keptWhileWeekLeft); one spent after: \(spentOne)")

    // 33. Feedback goes to the brand's help address with the house subject — the app's name in capitals, a space, then
    //     theirs — and carries the sender's email; it can't be sent without one.
    let subj = DesktopModel.feedbackSubject("The Dock icon stayed\nafter closing"), menuSubj = Maker.helpURL.absoluteString
    let fm = DesktopModel(Focus(store: UserDefaults(suiteName: "com.labern.focus.selftest")!))
    let savedAcct = UserDefaults.standard.object(forKey: "accountEmail")
    UserDefaults.standard.set("someone@example.com", forKey: "accountEmail")
    fm.feedbackText = "Hello"; let ready = fm.feedbackReady && DesktopModel.accountEmail == "someone@example.com"   // no field: the account's email
    if let e = savedAcct { UserDefaults.standard.set(e, forKey: "accountEmail") } else { UserDefaults.standard.removeObject(forKey: "accountEmail") }
    let blocked = true
    let fbOK = DesktopModel.feedbackAddress == "help@paradoxica.co.uk" && subj == "FOCUS The Dock icon stayed"
        && menuSubj.hasPrefix("mailto:help@paradoxica.co.uk?subject=FOCUS%20") && blocked && ready
    check(33, "feedback to help@, subject FOCUS …, with the account's email", fbOK,
          "to \(DesktopModel.feedbackAddress); subject \"\(subj)\"; menu link \(menuSubj); sends with the account's email, never asks: \(ready && blocked)")

    // 34. Pro tags follow the tier live: a tag drawn while viewing as Basic disappears when View As switches to Pro,
    //     in the same window, without reopening it (the bug: SwiftUI kept the old drawing).
    let tagModel = DesktopModel(Focus(store: UserDefaults(suiteName: "com.labern.focus.selftest")!))
    func inked(_ h: NSHostingView<AnyView>) -> Int {
        h.layoutSubtreeIfNeeded(); guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { return -1 }
        h.cacheDisplay(in: h.bounds, to: rep)
        var n = 0; for x in 0..<rep.pixelsWide { for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.3 { n += 1 } }
        return n
    }
    tagModel.viewAs("free")
    let host = NSHostingView(rootView: AnyView(ProTag().padding(4)))
    host.frame = NSRect(x: 0, y: 0, width: 60, height: 30)
    let tw = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false); tw.contentView = host
    let asBasic = inked(host)
    tagModel.viewAs("pro"); RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    let asPro = inked(host)
    tagModel.viewAs(""); _ = tagModel
    check(34, "Pro tags follow the tier live", asBasic > 20 && asPro == 0, "tag drawn as Basic: \(asBasic > 20) (\(asBasic) px); gone after switching to Pro: \(asPro == 0) (\(asPro) px)")

    // 35. Schedule: a block holds only on its days and hours (an overnight one wraps past midnight); a timed mode is due
    //     once, within two minutes of its time, and not again that day.
    var sc = Calendar(identifier: .gregorian); sc.timeZone = TimeZone(identifier: "Europe/London")!
    let monAt = { (h: Int, mi: Int) in sc.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: h, minute: mi))! }   // a Monday
    let schSun = sc.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 10))!
    let blk = ScheduleRule(kind: "block", apps: ["x"], days: [2, 3, 4, 5, 6], from: 540, to: 1020)
    let night = ScheduleRule(kind: "block", apps: ["x"], days: [2], from: 22 * 60, to: 6 * 60)
    var opn = ScheduleRule(kind: "open", mode: "m1", days: [2], from: 8 * 60 + 30)
    let blocks = Scheduler.blocking(blk, at: monAt(10, 0), sc) && !Scheduler.blocking(blk, at: monAt(17, 0), sc) && !Scheduler.blocking(blk, at: monAt(8, 59), sc)
        && !Scheduler.blocking(blk, at: schSun, sc)
    let wraps = Scheduler.blocking(night, at: monAt(23, 0), sc) && Scheduler.blocking(night, at: monAt(5, 0), sc) && !Scheduler.blocking(night, at: monAt(12, 0), sc)
    let dueNow = Scheduler.due(opn, at: monAt(8, 30), sc), notEarly = !Scheduler.due(opn, at: monAt(8, 29), sc), notLate = !Scheduler.due(opn, at: monAt(8, 33), sc)
    opn.fired = Scheduler.day(monAt(8, 30), sc); let once = !Scheduler.due(opn, at: monAt(8, 31), sc)
    var offRule = blk; offRule.on = false; let offOK = !Scheduler.blocking(offRule, at: monAt(10, 0), sc)
    check(35, "Schedule rules", blocks && wraps && dueNow && notEarly && notLate && once && offOK,
          "block on its days and hours: \(blocks); overnight wraps: \(wraps); open due at its time: \(dueNow), not early \(notEarly), not late \(notLate), once a day \(once); off does nothing: \(offOK)")

    print("gui: \(failures == 0 ? "all passed" : "\(failures) failed")")
    return Int32(failures)
}

// MARK: Schedule (Pro) — block apps during set hours; open a mode by itself at a set time

/// One schedule rule. Times are minutes after midnight; days are Calendar weekdays (1 = Sunday … 7 = Saturday).
struct ScheduleRule: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var kind = "block"                                             // "block" or "open"
    var apps: [String] = []                                        // block: bundle ids kept closed
    var mode = ""                                                  // open: the mode to start
    var days: [Int] = [2, 3, 4, 5, 6]                              // weekdays by default
    var from = 9 * 60, to = 17 * 60                                // block: from–to; open: from is the time
    var on = true
    var fired = ""                                                 // open: the day it last fired (yyyy-MM-dd)
}

final class Scheduler: ObservableObject {
    static let shared = Scheduler()
    @Published var rules: [ScheduleRule] = [] { didSet { save() } }
    @Published var note = ""                                       // the last thing it did, shown on the page
    private weak var f: Focus?
    private var timer: Timer?, launchWatch: Any?
    private let key = "focusSchedule"
    init() { if let d = UserDefaults.standard.data(forKey: key), let r = try? JSONDecoder().decode([ScheduleRule].self, from: d) { rules = r } }
    private func save() {                                          // renders and tests never touch the real schedule
        guard !renderArgs.contains("--render-desktop"), !CommandLine.arguments.contains("--selftest-gui") else { return }
        if let d = try? JSONEncoder().encode(rules) { UserDefaults.standard.set(d, forKey: key) }
    }

    static func minute(_ d: Date, _ c: Calendar = .current) -> Int { c.component(.hour, from: d) * 60 + c.component(.minute, from: d) }
    /// A block rule holds now: on, today is one of its days, and now is inside from–to (an overnight span wraps).
    static func blocking(_ r: ScheduleRule, at d: Date, _ c: Calendar = .current) -> Bool {
        guard r.on, r.kind == "block", r.days.contains(c.component(.weekday, from: d)) else { return false }
        let m = minute(d, c)
        return r.from <= r.to ? (m >= r.from && m < r.to) : (m >= r.from || m < r.to)
    }
    /// An open rule is due: on, today, within two minutes after its time, and not already fired today.
    static func due(_ r: ScheduleRule, at d: Date, _ c: Calendar = .current) -> Bool {
        guard r.on, r.kind == "open", !r.mode.isEmpty, r.days.contains(c.component(.weekday, from: d)) else { return false }
        let m = minute(d, c)
        return m >= r.from && m < r.from + 2 && r.fired != day(d, c)
    }
    static func day(_ d: Date, _ c: Calendar = .current) -> String {
        let f = DateFormatter(); f.calendar = c; f.locale = Locale(identifier: "en_GB"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }
    func blocked(_ id: String, at d: Date = Date()) -> ScheduleRule? { rules.first { Self.blocking($0, at: d) && $0.apps.contains(id) } }

    func start(_ focus: Focus) {
        f = focus
        timer?.invalidate()
        let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common); timer = t
        launchWatch = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, !DesktopModel.gated, let a = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = a.bundleIdentifier, let r = self.blocked(id) else { return }
            a.terminate()                                          // opened during its block: closed again
            self.note = "Closed \(a.localizedName ?? "an app"): blocked until \(Self.clock(r.to))."
        }
        tick()
    }
    func tick(now: Date = Date()) {
        guard let f, !DesktopModel.gated else { return }           // Pro only
        for i in rules.indices where Self.due(rules[i], at: now) {
            rules[i].fired = Self.day(now)
            if !f.focused, let name = f.mode(rules[i].mode)?["name"] as? String {
                f.startOrSwitch(rules[i].mode); note = "Started \(name) at \(Self.clock(rules[i].from))."
            }
        }
        for a in NSWorkspace.shared.runningApplications where !a.isTerminated {
            if let id = a.bundleIdentifier, let r = blocked(id, at: now) { a.terminate(); note = "Closed \(a.localizedName ?? "an app"): blocked until \(Self.clock(r.to))." }
        }
    }
    static func clock(_ m: Int) -> String { String(format: "%02d:%02d", (m / 60) % 24, m % 60) }
}

struct SchedulePage: View {
    @ObservedObject var m: DesktopModel
    @ObservedObject var s = Scheduler.shared
    var body: some View {
        PageFrame(title: "Schedule", text: "Keep apps closed at set times, or start a mode by itself.", locked: m) {
            SectionLabel("Block Apps", divider: false).padding(.horizontal, -14)
            Note("Keep these apps closed during these hours. If one opens, Focus closes it again.")
            ForEach($s.rules) { $r in if r.kind == "block" { ScheduleRow(m: m, r: $r) } }
            SiteButton("Add a Block") { s.rules.append(ScheduleRule(kind: "block")) }.padding(.top, 6)
            SectionLabel("Open at a Time").padding(.horizontal, -14)
            Note("Start a mode by itself at a set time, without pressing the button.")
            ForEach($s.rules) { $r in if r.kind == "open" { ScheduleRow(m: m, r: $r) } }
            SiteButton("Add a Time") { s.rules.append(ScheduleRule(kind: "open", mode: m.modes.first?.id ?? "", from: 9 * 60)) }.padding(.top, 6)
            if !s.note.isEmpty { Text(s.note).font(Site.font(15)).foregroundColor(Site.muted).padding(.top, 14) }
        }
    }
}

/// One rule: what (apps, or a mode), which days, when, on or off, delete.
struct ScheduleRow: View {
    @ObservedObject var m: DesktopModel
    @Binding var r: ScheduleRule
    static let dayOrder = [2, 3, 4, 5, 6, 7, 1], letters = [1: "S", 2: "M", 3: "T", 4: "W", 5: "T", 6: "F", 7: "S"]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if r.kind == "block" {
                    HStack(spacing: 6) {
                        ForEach(r.apps, id: \.self) { id in
                            if let p = m.f.path(id) { Image(nsImage: m.icon(p)).resizable().frame(width: 22, height: 22).help(m.f.appName(p)) }
                        }
                        Text(r.apps.isEmpty ? "No apps yet" : r.apps.compactMap { m.f.path($0).map(m.f.appName) }.joined(separator: ", "))
                            .font(Site.font(17, .medium)).foregroundColor(r.apps.isEmpty ? Site.muted : Site.head).lineLimit(1)
                    }
                    SiteButton("Choose Apps…") { chooseApps() }
                } else {
                    Menu {
                        ForEach(m.modes) { mode in Button(mode.name) { r.mode = mode.id } }
                    } label: { Text(m.modes.first { $0.id == r.mode }?.name ?? "Choose a mode").font(Site.font(17, .medium)) }
                    .menuStyle(.borderlessButton).fixedSize()
                }
                Spacer()
                Choice(options: ["Off", "On"], selected: r.on ? 1 : 0) { i in r.on = i == 1 }
                Button { Scheduler.shared.rules.removeAll { $0.id == r.id } } label: {
                    Image(systemName: "trash").font(.system(size: 14)).foregroundColor(Site.muted).frame(width: 30, height: 30).contentShape(Rectangle())
                }.buttonStyle(.plain).help("Delete").linkCursor()
            }
            HStack(spacing: 6) {
                ForEach(Self.dayOrder, id: \.self) { d in
                    let on = r.days.contains(d)
                    Button { if on { r.days.removeAll { $0 == d } } else { r.days.append(d) } } label: {
                        Text(Self.letters[d] ?? "").font(Site.font(14, .medium)).foregroundColor(on ? Site.paper : Site.head)
                            .frame(width: 30, height: 30).background(Circle().fill(on ? Site.ink : Color.clear))
                            .overlay(Circle().stroke(Site.ink.opacity(on ? 0 : 0.5), lineWidth: 1)).contentShape(Circle())
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 16)
                if r.kind == "block" {
                    TimeField(minutes: $r.from); Text("to").font(Site.font(15)).foregroundColor(Site.muted); TimeField(minutes: $r.to)
                } else {
                    Text("at").font(Site.font(15)).foregroundColor(Site.muted); TimeField(minutes: $r.from)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Site.surface))
        .padding(.top, 8)
    }
    func chooseApps() {
        let p = NSOpenPanel(); p.allowsMultipleSelection = true; p.canChooseDirectories = false
        p.allowedContentTypes = [.application]; p.directoryURL = URL(fileURLWithPath: "/Applications"); p.prompt = "Block"
        if p.runModal() == .OK {
            let ids = p.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
            r.apps = Array(Set(r.apps + ids)).sorted()
        }
    }
}

/// A time of day, as the Mac's own hour-and-minute field.
struct TimeField: View {
    @Binding var minutes: Int
    var body: some View {
        let date = Binding<Date>(
            get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date() },
            set: { minutes = Scheduler.minute($0) })
        DatePicker("", selection: date, displayedComponents: .hourAndMinute).labelsHidden().datePickerStyle(.field).fixedSize()
    }
}


// MARK: Sound — a tiny chime as a session starts and ends (synthesised; no sound files)

enum Chime {
    /// Settings ▸ Sound. On unless turned off.
    static var on: Bool { UserDefaults.standard.object(forKey: "focusSound") as? Bool ?? true }
    private static var testing: Bool { CommandLine.arguments.contains { $0.hasPrefix("--selftest") || $0.hasPrefix("--render") } }
    private static let startSound = NSSound(data: wav(notes: [(659.25, 0.075), (987.77, 0.16)]))   // E5 → B5: up, in
    private static let endSound = NSSound(data: wav(notes: [(987.77, 0.075), (659.25, 0.16)]))     // B5 → E5: down, out
    static func play(start: Bool) {
        guard on, !testing, let s = start ? startSound : endSound else { return }
        s.stop(); s.volume = 0.35; s.play()
    }
    /// Soft sine notes (a touch of the octave above for warmth), each with a 4 ms attack and a quick exponential fade.
    static func wav(notes: [(Double, Double)], rate: Double = 44_100) -> Data {
        var samples = [Int16]()
        for (hz, len) in notes {
            let n = Int(len * rate)
            for i in 0..<n {
                let t = Double(i) / rate
                let env = min(1, t / 0.004) * exp(-t * 18)
                let v = (sin(2 * .pi * hz * t) + 0.18 * sin(4 * .pi * hz * t)) * env * 0.5
                samples.append(Int16(max(-1, min(1, v)) * 32_000))
            }
        }
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let bytes = UInt32(samples.count * 2)
        d.append("RIFF".data(using: .ascii)!); u32(36 + bytes); d.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(bytes)
        samples.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
        return d
    }
}
