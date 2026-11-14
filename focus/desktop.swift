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

/// The website's design tokens (its :root block), so the window and the site are one look.
enum Site {
    static func hex(_ h: UInt32) -> Color { Color(red: Double((h >> 16) & 255) / 255, green: Double((h >> 8) & 255) / 255, blue: Double(h & 255) / 255) }
    static let bg = Color.black, surface = hex(0x1A1A1A), surface2 = hex(0x232323), line = hex(0x2A2A2A)
    static let head = Color.white, body = hex(0xEEEEEE), low = hex(0xD0D1D2), muted = hex(0x8E8E8E), hazard = hex(0xED4E3B)
    enum Weight { case regular, medium, semibold }
    /// Graphik, the site's face (it ships with macOS as a downloadable system font); Helvetica Neue if it's absent.
    static func font(_ size: CGFloat, _ w: Weight = .regular) -> Font {
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
            .onAppear {
                guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { t = 1; return }
                t = 0; let began = Date()
                let tm = Timer(timeInterval: 1.0 / 60, repeats: true) { tm in
                    let x = CGFloat(Date().timeIntervalSince(began) - 0.25) / 0.7        // a beat, then 0.7 s
                    t = min(max(x, 0), 1); if x >= 1 { tm.invalidate() }
                }
                RunLoop.main.add(tm, forMode: .common); timer = tm
            }
            .onDisappear { timer?.invalidate() }
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
    func start() {
        refresh()
        timer?.invalidate()
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common); timer = t
    }
    func stop() { timer?.invalidate(); timer = nil }
    func refresh() { f.mem = memoryByPid(); tick &+= 1 }
    /// Do something to the engine, then show it.
    func act(_ change: () -> Void) { change(); tick &+= 1 }

    // — the engine, read for the views —
    struct AppLine: Identifiable { let id: String, path: String, name: String, usage: String, on: Bool, note: String }
    func icon(_ path: String) -> NSImage { let i = NSWorkspace.shared.icon(forFile: path); i.size = NSSize(width: 128, height: 128); return i }   // the full-size artwork
    var running: [AppLine] {
        f.sorted(f.apps().compactMap { a in a.bundleIdentifier.flatMap { id in a.bundleURL.map { (id, $0.path) } } }).map { id, p in
            let size = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }.map(f.memory) ?? 0
            let parked = f.focused && f.isParked(id)
            return AppLine(id: id, path: p, name: f.appName(p), usage: size > 0 ? gb(size) : "", on: f.focused ? !parked : f.excluded.contains(id), note: parked ? "leaving…" : "")
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
    @State private var hover = false
    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: 34, height: 34).opacity(app.on ? 1 : 0.55)
            Text(app.name).font(Site.font(15, .medium)).foregroundColor(app.on ? Site.head : Site.muted)
            Spacer(minLength: 12)
            Text(app.note.isEmpty ? app.usage : app.note).font(Site.font(13)).foregroundColor(Site.muted).monospacedDigit()
            Image(systemName: hover && action != nil ? (app.on ? "xmark.circle.fill" : "plus.circle") : mark)
                .font(.system(size: 19)).foregroundColor(app.on ? Site.head : Site.muted).frame(width: 24)
        }
        .padding(.horizontal, 14).frame(height: 52)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover && action != nil ? Site.surface : Color.clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { action?() }
    }
}

struct SectionLabel: View {
    let left: String, right: String
    init(_ left: String, _ right: String = "") { self.left = left; self.right = right }
    var body: some View {
        HStack { Text(left); Spacer(); Text(right).padding(.trailing, 38) }
            .font(Site.font(12, .medium)).foregroundColor(Site.muted).padding(.horizontal, 14).padding(.top, 22).padding(.bottom, 6)
    }
}

/// The site's button: white, black ink — or an outline for the quieter actions.
struct SiteButton: View {
    let title: String, key: String, filled: Bool, tint: Color, action: () -> Void
    init(_ title: String, key: String = "", filled: Bool = true, tint: Color = Site.head, action: @escaping () -> Void) {
        self.title = title; self.key = key; self.filled = filled; self.tint = tint; self.action = action
    }
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack { Text(title).font(Site.font(15, .medium)); if !key.isEmpty { Spacer(); Text(key).font(Site.font(13)).opacity(0.55) } }
                .foregroundColor(filled ? .black : tint)
                .padding(.horizontal, 18).frame(height: filled ? 48 : 36)
                .frame(maxWidth: filled ? .infinity : nil)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(filled ? Color.white.opacity(hover ? 0.88 : 1) : (hover ? Site.surface : Color.clear)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(filled ? Color.clear : Site.line, lineWidth: 1))
        }
        .buttonStyle(.plain).onHover { hover = $0 }
    }
}

struct SideRow: View {
    let title: String, trailing: String, live: Bool, selected: Bool, icons: [NSImage], symbol: String?, action: () -> Void
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
            Text(title).font(Site.font(14, selected ? .medium : .regular)).lineLimit(1)
            Spacer(minLength: 6)
            if live { Circle().fill(Site.head).frame(width: 7, height: 7) }
            Text(trailing).font(Site.font(12)).foregroundColor(Site.muted)
        }
        .foregroundColor(selected ? Site.head : Site.low)
        .padding(.horizontal, 12).frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? Site.surface2 : hover ? Site.surface : Color.clear))
        .contentShape(Rectangle()).onHover { hover = $0 }.onTapGesture(perform: action)
    }
}

// MARK: the window's content

struct DesktopView: View {
    @ObservedObject var m: DesktopModel
    var body: some View {
        let _ = m.tick
        HStack(spacing: 0) {
            sidebar.frame(width: 248)
            Rectangle().fill(Site.line).frame(width: 1)
            Group { if let id = m.selection, let mode = m.modes.first(where: { $0.id == id }) { ModeDetail(m: m, mode: mode).id(mode.id + "\u{1F}" + mode.name) }   // renamed in the menu: the field follows else { SessionDetail(m: m) } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Site.bg).preferredColorScheme(.dark)
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if m.still { Image(nsImage: siteLogo(96)).resizable().interpolation(.high).frame(width: 38, height: 38) } else { LogoView(side: 38) }
                Text("Focus").font(Site.font(24, .medium)).foregroundColor(Site.head)
            }.padding(.leading, 18).padding(.top, 52).padding(.bottom, 22)
            VStack(spacing: 2) {
                SideRow(title: "Session", trailing: m.f.focused ? "On" : "", live: m.f.focused, selected: m.selection == nil, icons: [], symbol: "circle.grid.2x2") { m.selection = nil }
            }.padding(.horizontal, 10)
            Text("Modes").font(Site.font(12, .medium)).foregroundColor(Site.muted).padding(.leading, 22).padding(.top, 22).padding(.bottom, 6)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(m.modes) { mode in
                        SideRow(title: mode.name, trailing: mode.key, live: mode.live, selected: m.selection == mode.id,
                                icons: mode.apps.compactMap { m.f.path($0) }.map(m.icon), symbol: nil) { m.selection = mode.id }
                    }
                    SideRow(title: "Create New Mode", trailing: "", live: false, selected: false, icons: [], symbol: "plus.circle") { m.newMode() }
                }.padding(.horizontal, 10)
            }
            Spacer(minLength: 8)
            HStack(alignment: .top, spacing: 2) {
                if let b = brandLockup { Image(nsImage: b).resizable().interpolation(.high).aspectRatio(1080.0 / 112.0, contentMode: .fit).frame(width: 150) }
                else { Text("★★★★★ × PARADOX").font(Site.font(12, .medium)).foregroundColor(Site.head) }
                Text("™").font(Site.font(8)).foregroundColor(Site.head).offset(y: -1)
            }.padding(.leading, 20).padding(.bottom, 20)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(f.focused ? (f.displayName ?? "In Session") : "Keep open this session").font(Site.font(32, .medium)).foregroundColor(Site.head)
                    Text(f.focused ? "Click an app to take it out of the session, or to bring one back."
                                   : "Tick the apps you want to keep. Everything else closes when the session starts and comes back when it ends.")
                        .font(Site.font(15)).foregroundColor(Site.low).padding(.top, 8).fixedSize(horizontal: false, vertical: true)
                    SectionLabel("Apps in Session", "Usage").padding(.horizontal, -14)
                    ForEach(m.running) { app in
                        AppRowView(app: app, icon: m.icon(app.path), mark: app.on ? "checkmark.circle.fill" : "circle") { m.toggle(app) }.padding(.horizontal, -14)
                    }
                    if !m.outside.isEmpty {
                        SectionLabel("Apps Outside Session").padding(.horizontal, -14)
                        ForEach(m.outside) { app in
                            AppRowView(app: app, icon: m.icon(app.path), mark: "circle") { m.toggle(app) }.padding(.horizontal, -14)
                        }
                    }
                    SectionLabel("Critical System Processes — never quit").padding(.horizontal, -14)
                    ForEach(m.critical) { app in
                        AppRowView(app: app, icon: m.icon(app.path), mark: "lock.circle.fill", action: nil).padding(.horizontal, -14)
                    }
                    SiteButton("Add or remove…", filled: false) { f.showNever() }.padding(.top, 10)
                }
                .padding(.horizontal, 34).padding(.top, 46).padding(.bottom, 24)
            }
            Rectangle().fill(Site.line).frame(height: 1)
            VStack(spacing: 10) {
                SiteButton(f.focused ? "End Session" : "Start New Session", key: sessionKey) { m.act { f.toggle() } }
                Text(f.sessionCaption()).font(Site.font(12)).foregroundColor(Site.muted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 34).padding(.vertical, 18)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        TextField("Mode name", text: $name, onCommit: { m.act { f.renameMode(mode.id, to: name.trimmingCharacters(in: .whitespacesAndNewlines)) } })
                            .textFieldStyle(.plain).font(Site.font(32, .medium)).foregroundColor(Site.head)
                        Menu {
                            Button("None") { m.act { f.setModeKey(mode.id, nil) } }
                            ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9, 0], id: \.self) { d in Button(f.label(forMode: d)) { m.act { f.setModeKey(mode.id, d) } } }
                        } label: { Text(mode.key.isEmpty ? "No shortcut" : mode.key).font(Site.font(14, .medium)) }
                        .menuStyle(.borderlessButton).fixedSize()
                    }
                    Text("A mode is a set of apps you keep open. Starting it closes everything else until the session ends.")
                        .font(Site.font(15)).foregroundColor(Site.low).padding(.top, 8).fixedSize(horizontal: false, vertical: true)
                    SectionLabel("Keeps open").padding(.horizontal, -14)
                    ForEach(inMode) { app in
                        AppRowView(app: app, icon: m.icon(app.path), mark: "checkmark.circle.fill") { m.act { f.removeApp(app.id, fromMode: mode.id) } }.padding(.horizontal, -14)
                    }
                    if inMode.isEmpty { Text("No apps yet. Add one below.").font(Site.font(14)).foregroundColor(Site.muted).padding(.vertical, 12) }
                    if !others.isEmpty {
                        SectionLabel("Open now — click to add").padding(.horizontal, -14)
                        ForEach(others) { app in
                            AppRowView(app: app, icon: m.icon(app.path), mark: "circle") { m.act { _ = f.addApp(app.id, toMode: mode.id) } }.padding(.horizontal, -14)
                        }
                    }
                    HStack(spacing: 10) {
                        SiteButton("Add App…", filled: false) { let s = NSMenuItem(); s.representedObject = mode.id; f.addAppToMode(s); m.refresh() }
                        SiteButton("Delete Mode", filled: false, tint: Site.hazard) { m.act { f.removeMode(mode.id); m.selection = nil } }
                    }.padding(.top, 14)
                }
                .padding(.horizontal, 34).padding(.top, 46).padding(.bottom, 24)
            }
            Rectangle().fill(Site.line).frame(height: 1)
            VStack(spacing: 10) {
                SiteButton(mode.live ? "End Session" : "Start \(mode.name)", key: mode.key) { if !mode.apps.isEmpty || mode.live { m.act { f.startOrSwitch(mode.id) } } }
                    .opacity(mode.apps.isEmpty && !mode.live ? 0.4 : 1)
                Text(mode.apps.isEmpty ? "Add at least one app before starting this mode."
                     : mode.live ? "Ending the session reopens everything this mode closed."
                     : "Keeps \(f.names(mode.apps)) open and closes everything else until the session ends.")
                    .font(Site.font(12)).foregroundColor(Site.muted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 34).padding(.vertical, 18)
        }
        .onAppear { name = mode.name }
    }
}

// MARK: the window

/// Owns the desktop window. While it is open Focus is an ordinary app (in the Dock and ⌘⇥, with the site's logo);
/// when it closes Focus goes back to being only its menu bar icon.
/// ⌘H (and ⌘W) put the window away and return Focus to its menu bar icon, as Wispr Flow does. Only while the
/// window is open: Focus takes no such key otherwise.
final class DesktopWindow: NSWindow {
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        if e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, let ch = e.charactersIgnoringModifiers?.lowercased(), ch == "h" || ch == "w" {
            close(); return true
        }
        return super.performKeyEquivalent(with: e)
    }
}
final class DesktopController: NSObject, NSWindowDelegate {
    var window: NSWindow?, model: DesktopModel?
    var shown: Bool { window?.isVisible == true }
    func show(_ f: Focus) {
        if window == nil {
            let m = DesktopModel(f); model = m
            let w = DesktopWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 660),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden; w.title = "Focus"
            w.backgroundColor = .black; w.appearance = NSAppearance(named: .darkAqua)
            w.isMovableByWindowBackground = true; w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 780, height: 540)
            w.contentView = NSHostingView(rootView: DesktopView(m: m))
            w.setFrameAutosaveName("FocusDesktop"); if w.frame.origin == .zero { w.center() }
            w.delegate = self; window = w
        }
        model?.start()
        NSApp.setActivationPolicy(.regular)                      // now in the Dock and ⌘⇥…
        NSApp.applicationIconImage = siteLogo(512, grid: true)   // …with the site's logo
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    func hide() { window?.close() }
    func windowWillClose(_ n: Notification) {
        model?.stop()
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
    let size = NSSize(width: 940, height: 660)
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
