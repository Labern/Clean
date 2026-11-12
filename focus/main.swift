// Focus — park the big apps (Chrome, Obsidian, Keynote…) so their memory goes to the work, then bring them
// back exactly as they were. Quitting is slow and safe: one app at a time, each asked to quit normally (so it
// saves its state, and unsaved work still prompts), waiting for it to finish before the next. Never forced.
// Restoring relaunches them one at a time with their windows (Chrome with its last session).
// Menu bar only. One file, no dependencies, no permissions.
//   ⌘⇧F   start a session (quit everything not kept) · again: bring it all back
//   ⌘⇧E   open the Focus menu: click apps to keep them for this session, then Start Session Now
// Never touched, ever: system apps (/System/Library/CoreServices), menu bar apps, Focus itself, and the
// user's own saved Critical System Processes. Nothing about any particular user's apps is built in.
// The system ⌘⇥ is never replaced or altered (user's rule: native only).
import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI
import Darwin

// Earlier builds switched the system ⌘⇥ off (private SkyLight call). That setting outlives the process, so every
// launch switches it back on — heals any Mac left without ⌘⇥ by an old build. Focus never switches it off.
func systemSwitcher(_ on: Bool) {
    guard let lib = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
          let fn = dlsym(lib, "CGSSetSymbolicHotKeyEnabled") else { return }
    let set = unsafeBitCast(fn, to: (@convention(c) (Int32, Bool) -> Int32).self)
    _ = set(1, on); _ = set(2, on)
}
func healSystemSwitcher() { systemSwitcher(true) }

func hotkey(_ id: UInt32, _ key: Int, _ mods: Int) -> EventHotKeyRef? {
    var ref: EventHotKeyRef?
    RegisterEventHotKey(UInt32(key), UInt32(mods), EventHotKeyID(signature: 0x464F_4355, id: id), GetEventDispatcherTarget(), 0, &ref)
    return ref
}
func symbol(_ name: String, _ colors: [NSColor]? = nil) -> NSImage? {
    let i = NSImage(systemSymbolName: name, accessibilityDescription: nil)
    guard let colors else { return i }
    return i?.withSymbolConfiguration(.init(paletteColors: colors))
}

/// Every colour the custom menu views use. One token set: swap it to re-theme the whole menu.
struct Theme {
    var accent = NSColor.controlAccentColor
    var onAccent = NSColor.white
    var hover = NSColor.labelColor.withAlphaComponent(0.08)
    var text = NSColor.labelColor
    var faint = NSColor.secondaryLabelColor
    var dropped = NSColor.tertiaryLabelColor
    var hudBg = NSColor(white: 0.07, alpha: 0.88)                // the session pill
    var hudInk = NSColor.white
    var hudEdge = NSColor(white: 1, alpha: 0.14)
    /// Icon colour grid: nine hues (columns) × four shades (rows: light → deep), and two-tone presets (ring, dot).
    /// Mu's purple is #A78BFA (sampled off the menu bar); the green is PARADOX teal2.
    var iconHues: [String] = ["FF5F5F", "FFAF5F", "FFD75F", "5FD787", "5FD7AF", "5FAFFF", "A78BFA", "FF87FF", "D0D0D0"]
    var iconPresets: [(String, String, String)] = [("Purple & Green", "A78BFA", "5FD7AF"), ("Pink & Teal", "FF87FF", "87D7D7"),
                                                   ("Violet & Gold", "AF87FF", "FFD75F"), ("Teal & Pink", "87D7D7", "FF87FF"),
                                                   ("All Purple", "A78BFA", "A78BFA")]
}
let theme = Theme()
let menuWidth: CGFloat = 320
let sessionKey = "⌘⇧F"
let chrome = "com.google.Chrome"

/// Every process with its parent and short name, read the way `ps` reads them (sysctl KERN_PROC_ALL).
/// (proc_listallpids silently skipped processes.)
struct Proc { let pid: pid_t, ppid: pid_t, name: String }
func processes() -> [Proc] {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0], size = 0
    let stride = MemoryLayout<kinfo_proc>.stride
    guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return [] }
    var buf = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 64)
    size = buf.count * stride
    guard sysctl(&mib, 4, &buf, &size, nil, 0) == 0 else { return [] }
    return buf.prefix(size / stride).map { k in
        var comm = k.kp_proc.p_comm
        let name = withUnsafeBytes(of: &comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return Proc(pid: k.kp_proc.p_pid, ppid: k.kp_eproc.e_ppid, name: name)
    }
}

/// Physical memory per process tree, the number Activity Monitor calls "Memory". An app's figure includes its
/// helpers (Chrome's renderers, Electron's GPU process…), which are its child processes.
func memoryByPid() -> [pid_t: UInt64] {
    var own: [pid_t: UInt64] = [:], kids: [pid_t: [pid_t]] = [:]
    for p in processes() where p.pid > 0 {
        kids[p.ppid, default: []].append(p.pid)
        var ru = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &ru) { $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(p.pid, RUSAGE_INFO_V4, $0) } }
        if ok == 0 { own[p.pid] = ru.ri_phys_footprint }
    }
    var total: [pid_t: UInt64] = [:]
    func sum(_ p: pid_t, _ depth: Int) -> UInt64 {
        if let t = total[p] { return t }
        let t = (own[p] ?? 0) + (depth > 8 ? 0 : (kids[p] ?? []).reduce(0) { $0 + sum($1, depth + 1) })
        total[p] = t; return t
    }
    for p in own.keys where p > 1 { _ = sum(p, 0) }
    return total
}

func gb(_ b: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .memory) }

func hexColor(_ h: String) -> NSColor? {
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
    return NSColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}
func hexString(_ c: NSColor) -> String {
    let c = c.usingColorSpace(.sRGB) ?? c
    return String(format: "%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
}
/// A copy of an image drawn in one colour, resolution-independent (so it stays sharp on Retina).
func tinted(_ img: NSImage, _ c: NSColor) -> NSImage {
    let o = NSImage(size: img.size, flipped: false) { r in img.draw(in: r); c.set(); r.fill(using: .sourceAtop); return true }
    o.isTemplate = false; return o
}
func swatch(_ c: NSColor?) -> NSImage {                         // a dot for the colour menu; nil = the default (half dark/light)
    NSImage(size: NSSize(width: 14, height: 14), flipped: false) { r in
        let dot = NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1))
        if let c { c.setFill(); dot.fill() } else {
            NSColor.labelColor.setFill(); dot.fill()
            NSColor.textBackgroundColor.setFill(); NSBezierPath(rect: NSRect(x: r.midX, y: 0, width: r.width / 2, height: r.height)).setClip()
            dot.fill()
        }
        NSColor.separatorColor.setStroke(); dot.lineWidth = 0.5; dot.stroke()
        return true
    }
}

/// Four shades of a hue: light, soft, true, deep.
func shades(_ hex: String) -> [String] {
    guard let c = hexColor(hex) else { return [] }
    return [c.blended(withFraction: 0.5, of: .white), c.blended(withFraction: 0.22, of: .white), c, c.blended(withFraction: 0.35, of: .black)]
        .compactMap { $0 }.map(hexString)
}

/// A click-to-pick grid of colour dots inside a menu (the menu stays open, so you can try a few).
final class ColorGrid: NSView {
    let colors: [[String]], pick: (String) -> Void
    var selected: String, hover: String?
    static let dot: CGFloat = 22, gap: CGFloat = 8, pad: CGFloat = 14
    init(_ columns: [[String]], selected: String, pick: @escaping (String) -> Void) {
        colors = columns; self.selected = selected; self.pick = pick
        let rows = columns.map(\.count).max() ?? 0
        super.init(frame: NSRect(x: 0, y: 0, width: Self.pad * 2 + CGFloat(columns.count) * (Self.dot + Self.gap) - Self.gap,
                                 height: 8 + CGFloat(rows) * (Self.dot + Self.gap) - Self.gap + 8))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { nil }
    func rect(_ col: Int, _ row: Int) -> NSRect {
        NSRect(x: Self.pad + CGFloat(col) * (Self.dot + Self.gap), y: bounds.height - 8 - CGFloat(row + 1) * Self.dot - CGFloat(row) * Self.gap, width: Self.dot, height: Self.dot)
    }
    func hit(_ e: NSEvent) -> String? {
        let p = convert(e.locationInWindow, from: nil)
        for (c, col) in colors.enumerated() { for (r, hex) in col.enumerated() where rect(c, r).insetBy(dx: -3, dy: -3).contains(p) { return hex } }
        return nil
    }
    override func mouseMoved(with e: NSEvent) { let h = hit(e); if h != hover { hover = h; needsDisplay = true } }
    override func mouseExited(with e: NSEvent) { hover = nil; needsDisplay = true }
    override func mouseDown(with e: NSEvent) {}
    override func mouseUp(with e: NSEvent) { if let h = hit(e) { selected = h; pick(h); needsDisplay = true } }
    override func draw(_ r: NSRect) {
        for (c, col) in colors.enumerated() { for (row, hex) in col.enumerated() {
            let d = rect(c, row), path = NSBezierPath(ovalIn: d.insetBy(dx: hover == hex ? 0 : 1.5, dy: hover == hex ? 0 : 1.5))
            hexColor(hex)?.setFill(); path.fill()
            if hex == selected {
                theme.text.setStroke(); let ring = NSBezierPath(ovalIn: d.insetBy(dx: -2.5, dy: -2.5)); ring.lineWidth = 1.5; ring.stroke()
            }
        } }
    }
}

/// The menu bar mark: a viewfinder ring with a centre dot. `t` is linear progress, 0 (at rest: four open
/// brackets, gaps at the compass points, small dot) to 1 (focused: one closed ring, bigger dot). With `hunt`
/// the ring first pulls in and comes back out — a lens finding focus — then the gaps close in place and the
/// dot swells. Each phase has its own eased slice of the timeline. Template image: follows light / dark bars.
func glyph(_ t: CGFloat, hunt: Bool = false, ring ringColor: NSColor? = nil, dot dotColor: NSColor? = nil) -> NSImage {
    func phase(_ a: CGFloat, _ b: CGFloat) -> CGFloat {          // 0…1 across [a, b], smoothstep-eased
        let x = min(max((t - a) / (b - a), 0), 1); return x * x * (3 - 2 * x)
    }
    let pull = hunt ? sin(.pi * phase(0, 0.55)) * 2.0 : 0
    let close = hunt ? phase(0.35, 0.85) : t                     // gap fraction closed
    let swell = hunt ? phase(0.45, 1) : t
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
        let c = NSPoint(x: r.midX, y: r.midY), radius = 6.5 - pull
        let gap = 23.4 * (1 - close)                                 // degrees; 0 = a closed ring
        let ring = NSBezierPath(); ring.lineWidth = 1.6
        if gap < 0.5 { ring.appendOval(in: NSRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)) }
        else { for k in 0..<4 {                                       // arcs centred on 45°, 135°… so gaps sit on the axes
            let mid = 45 + 90 * CGFloat(k)
            ring.move(to: NSPoint(x: c.x + radius * cos((mid - 45 + gap / 2) * .pi / 180), y: c.y + radius * sin((mid - 45 + gap / 2) * .pi / 180)))
            ring.appendArc(withCenter: c, radius: radius, startAngle: mid - 45 + gap / 2, endAngle: mid + 45 - gap / 2)
        } }
        ringColor?.setStroke(); ring.stroke()
        let dot = 1.75 + 1.25 * swell - (hunt ? pull * 0.3 : 0)      // radius: 1.75 at rest, 3 focused
        dotColor?.setFill(); NSBezierPath(ovalIn: NSRect(x: c.x - dot, y: c.y - dot, width: dot * 2, height: dot * 2)).fill()
        return true
    }
    img.isTemplate = ringColor == nil && dotColor == nil
    return img
}
func glyph(focused: Bool) -> NSImage { glyph(focused ? 1 : 0) }

/// A menu view that highlights under the pointer and stretches to the menu's width.
class HoverView: NSView {
    var hover = false { didSet { needsDisplay = true } }
    init(height: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: height))
        autoresizingMask = [.width]
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { nil }
    override func mouseEntered(with e: NSEvent) { hover = true }
    override func mouseExited(with e: NSEvent) { hover = false }
    // Take the whole click. Unhandled, mouseDown falls through to the menu, which can read it as a click-away and close.
    override func mouseDown(with e: NSEvent) {}
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
}

/// One app: icon, name, and a mark on the right. Clicking flips it without closing the menu, so several
/// can be set in one go. `on` uses `onMark`, off uses an empty circle; apps that will go read dimmer.
final class AppRow: HoverView {
    let name: String, icon: NSImage, detail: String, onMark: String, flip: () -> Bool
    var on: Bool
    init(_ name: String, _ icon: NSImage, detail: String = "", on: Bool, onMark: String = "checkmark.circle.fill", flip: @escaping () -> Bool) {
        self.name = name; self.icon = icon; self.detail = detail; self.on = on; self.onMark = onMark; self.flip = flip
        super.init(height: 26)
    }
    required init?(coder: NSCoder) { nil }
    override func mouseUp(with e: NSEvent) { on = flip(); needsDisplay = true }
    override func draw(_ r: NSRect) {
        if hover { theme.hover.setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 5, yRadius: 5).fill() }
        icon.draw(in: NSRect(x: 14, y: 5, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: on ? 1 : 0.55)
        (name as NSString).draw(at: NSPoint(x: 38, y: 4.5), withAttributes: [.font: NSFont.menuFont(ofSize: 13), .foregroundColor: on ? theme.text : theme.faint])
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: theme.faint]
        let d = detail as NSString
        d.draw(at: NSPoint(x: bounds.width - 42 - d.size(withAttributes: small).width, y: 6), withAttributes: small)
        let mark = on ? symbol(onMark, [theme.onAccent, theme.accent]) : symbol("circle", [theme.dropped])
        mark?.draw(in: NSRect(x: bounds.width - 32, y: 5, width: 16, height: 16))
    }
}

/// The big button at the bottom: the one action, its key, and a live caption of what it will do.
final class BigButton: HoverView {
    let title: () -> String, caption: () -> String, action: () -> Void
    var down = false { didSet { needsDisplay = true } }
    init(title: @escaping () -> String, caption: @escaping () -> String, action: @escaping () -> Void) {
        self.title = title; self.caption = caption; self.action = action
        super.init(height: 72)
    }
    required init?(coder: NSCoder) { nil }
    override func mouseDown(with e: NSEvent) { down = true }
    override func mouseUp(with e: NSEvent) {
        down = false
        enclosingMenuItem?.menu?.cancelTracking()
        DispatchQueue.main.async(execute: action)
    }
    override func draw(_ r: NSRect) {
        let pill = NSRect(x: 12, y: 26, width: bounds.width - 24, height: 38)
        (down ? theme.accent.blended(withFraction: 0.2, of: .black) : hover ? theme.accent.blended(withFraction: 0.1, of: .white) : theme.accent)?.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 9, yRadius: 9).fill()
        let big: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: theme.onAccent]
        (title() as NSString).draw(at: NSPoint(x: pill.minX + 14, y: pill.midY - 9), withAttributes: big)
        let key: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: theme.onAccent.withAlphaComponent(0.75)]
        let k = sessionKey as NSString
        k.draw(at: NSPoint(x: pill.maxX - 14 - k.size(withAttributes: key).width, y: pill.midY - 8.5), withAttributes: key)
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: theme.faint]
        let c = caption() as NSString
        c.draw(at: NSPoint(x: bounds.midX - c.size(withAttributes: small).width / 2, y: 6), withAttributes: small)
    }
}

/// The session snapshot as a rounded thumbnail; click to open it full size.
final class Thumb: HoverView {
    let img: NSImage, action: () -> Void
    init(_ img: NSImage, _ size: NSSize, action: @escaping () -> Void) {
        self.img = img; self.action = action
        super.init(height: size.height + 8)
    }
    required init?(coder: NSCoder) { nil }
    override func mouseUp(with e: NSEvent) { enclosingMenuItem?.menu?.cancelTracking(); DispatchQueue.main.async(execute: action) }
    override func draw(_ r: NSRect) {
        let rect = NSRect(x: 14, y: 4, width: bounds.width - 28, height: bounds.height - 8)
        let clip = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSGraphicsContext.saveGraphicsState(); clip.addClip()
        img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: hover ? 1 : 0.92)
        NSGraphicsContext.restoreGraphicsState()
        theme.dropped.setStroke(); clip.lineWidth = 1; clip.stroke()
    }
}

// MARK: session pill — the little show when a session starts or ends

func ease(_ x: CGFloat) -> CGFloat { min(max(x, 0), 1) }
func easeOut(_ x: CGFloat) -> CGFloat { let t = ease(x); return 1 - pow(1 - t, 3) }
func easeIn(_ x: CGFloat) -> CGFloat { let t = ease(x); return t * t * t }
func easeBack(_ x: CGFloat) -> CGFloat { let t = ease(x) - 1, k: CGFloat = 1.9; return 1 + (k + 1) * t * t * t + k * t * t }   // overshoot

/// An image drawn in one colour (for the template glyph on the dark pill).
func painted(_ img: NSImage, _ color: NSColor, _ size: NSSize) -> CGImage? {
    let out = NSImage(size: size, flipped: false) { r in img.draw(in: r); color.set(); r.fill(using: .sourceAtop); return true }
    return out.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

/// A click-through, full-screen, transparent overlay that plays one short timeline:
///   start: pill pops (zop) → hit stop + flash, mark snaps shut → app icons fan out → sucked into the menu bar
///          icon one by one → pill zips off sideways.
///   end:   the same in reverse — icons stream out of the menu bar icon into the pill → hit stop, mark opens → zip.
/// Driven frame by frame (120 Hz) rather than by CA animations, so the hit stop is an honest freeze.
final class SessionPill {
    var win: NSWindow?, timer: Timer?

    func play(start: Bool, icons: [NSImage], target: NSPoint, label: String) {
        timer?.invalidate(); win?.orderOut(nil)
        let screen = NSScreen.screens.first { $0.frame.contains(target) } ?? NSScreen.main!
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false; w.ignoresMouseEvents = true
        w.level = .statusBar; w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let root = CALayer(); w.contentView!.wantsLayer = true; w.contentView!.layer = root
        let s = screen.backingScaleFactor, origin = screen.frame.origin
        let tgt = CGPoint(x: target.x - origin.x, y: target.y - origin.y)

        // The pill: mark + one word, bottom centre — where the eye already is when the key goes down.
        let pill = CALayer(), size = CGSize(width: 136, height: 44)
        let home = CGPoint(x: screen.frame.width / 2, y: 96)
        pill.bounds = CGRect(origin: .zero, size: size); pill.position = home
        pill.backgroundColor = theme.hudBg.cgColor; pill.cornerRadius = 22
        pill.borderColor = theme.hudEdge.cgColor; pill.borderWidth = 1
        pill.shadowColor = NSColor.black.cgColor; pill.shadowOpacity = 0.45; pill.shadowRadius = 14; pill.shadowOffset = CGSize(width: 0, height: -4)
        let mark = CALayer(); mark.frame = CGRect(x: 16, y: 10, width: 24, height: 24); mark.contentsScale = s
        let word = CATextLayer(); word.string = label; word.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        word.fontSize = 15; word.foregroundColor = theme.hudInk.cgColor; word.contentsScale = s
        word.frame = CGRect(x: 50, y: 12, width: size.width - 62, height: 20)
        let flash = CALayer(); flash.frame = pill.bounds; flash.cornerRadius = 22; flash.backgroundColor = theme.hudInk.cgColor; flash.opacity = 0
        [mark, word, flash].forEach(pill.addSublayer)
        root.addSublayer(pill)

        // The apps: up to nine icons on an arc above the pill.
        let shown = Array(icons.prefix(9)), n = shown.count
        let tiles: [CALayer] = shown.map { img in
            let l = CALayer(); l.bounds = CGRect(x: 0, y: 0, width: 44, height: 44); l.contentsScale = s
            l.contents = img.cgImage(forProposedRect: nil, context: nil, hints: nil); l.opacity = 0
            root.addSublayer(l); return l
        }
        let fan: [CGPoint] = (0..<n).map { i in
            let a = n == 1 ? CGFloat.pi / 2 : CGFloat.pi * (0.78 - 0.56 * CGFloat(i) / CGFloat(n - 1))
            return CGPoint(x: home.x + cos(a) * 150, y: home.y + 26 + sin(a) * 92)
        }
        func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
        func setMark(_ t: CGFloat) { mark.contents = painted(glyph(t), theme.hudInk, NSSize(width: 24, height: 24)) }

        // Timeline (seconds). `stop` is the hit stop: nothing moves but the flash.
        let popIn = 0.16, stop = 0.10, stagger = 0.035, fly = 0.34
        let impact = start ? popIn : popIn + 0.10 + Double(max(n - 1, 0)) * stagger + fly + 0.12
        let after = impact + stop
        let flyDone = start ? after + 0.16 + 0.08 + Double(max(n - 1, 0)) * stagger + fly : impact
        let zipAt = (start ? flyDone : after + 0.06), zipLen = 0.22, end = zipAt + zipLen + 0.05
        setMark(start ? 0 : 1)

        w.orderFrontRegardless(); win = w
        let began = Date()
        let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] tm in
            let now = Date().timeIntervalSince(began)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            // pill: zop in, shake during the stop, zip out sideways at the end
            let inP = CGFloat(now / popIn)
            var sc = 0.4 + 0.6 * easeBack(inP), x = home.x, op = Float(ease(inP * 1.5))
            if now >= impact && now < after { x += CGFloat(sin(now * 260)) * 3 }
            if now >= zipAt {
                let z = CGFloat((now - zipAt) / zipLen)
                x += easeIn(z) * 420; op = Float(1 - easeIn(z)); sc = 1
                pill.transform = CATransform3DMakeScale(1 + 0.35 * easeIn(z), 1 - 0.18 * easeIn(z), 1)   // stretch as it goes
            } else { pill.transform = CATransform3DMakeScale(sc, sc, 1) }
            pill.position = CGPoint(x: x, y: home.y); pill.opacity = op
            // impact: the mark snaps, the flash decays
            if now >= impact && (mark.value(forKey: "snapped") as? Bool) != true { setMark(start ? 1 : 0); mark.setValue(true, forKey: "snapped") }
            flash.opacity = now >= impact ? Float(0.85 * (1 - ease(CGFloat((now - impact) / 0.16)))) : 0
            // icons
            for (i, l) in tiles.enumerated() {
                let d = Double(i) * stagger
                if start {
                    let burst = CGFloat((now - after - d * 0.5) / 0.16), suck = CGFloat((now - after - 0.24 - d) / fly)
                    if now < after { l.opacity = 0; continue }
                    if suck <= 0 {
                        l.position = lerp(home, fan[i], easeBack(burst)); l.opacity = Float(ease(burst * 2))
                        l.transform = CATransform3DMakeScale(0.5 + 0.5 * easeOut(burst), 0.5 + 0.5 * easeOut(burst), 1)
                    } else {
                        let k = easeIn(suck)
                        l.position = lerp(fan[i], tgt, k); l.opacity = Float(1 - ease((suck - 0.6) / 0.4))
                        l.transform = CATransform3DMakeScale(1 - 0.8 * k, 1 - 0.8 * k, 1)
                    }
                } else {
                    let out = CGFloat((now - popIn - d) / fly), drop = CGFloat((now - popIn - Double(max(n - 1, 0)) * stagger - fly - 0.02) / 0.12)
                    if out <= 0 { l.opacity = 0; continue }
                    if drop <= 0 {
                        let k = easeOut(out)
                        l.position = lerp(tgt, fan[i], k); l.opacity = Float(ease(out * 3))
                        l.transform = CATransform3DMakeScale(0.2 + 0.8 * k, 0.2 + 0.8 * k, 1)
                    } else {
                        let k = easeIn(drop)
                        l.position = lerp(fan[i], home, k); l.opacity = Float(1 - k)
                        l.transform = CATransform3DMakeScale(1 - 0.6 * k, 1 - 0.6 * k, 1)
                    }
                }
            }
            CATransaction.commit()
            if now > end { tm.invalidate(); self?.win?.orderOut(nil); self?.win = nil }
        }
        RunLoop.main.add(t, forMode: .common); timer = t
    }
}

typealias Session = [String: Any]                              // "date": Date, "apps": [["path": String, "hidden": Bool]]

final class Focus: NSObject, NSMenuDelegate {
    let ws = NSWorkspace.shared, store: UserDefaults
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    weak var button: BigButton?                                 // redrawn as rows change, so its caption is live
    var mem: [pid_t: UInt64] = [:]                              // refreshed each time the menu opens
    var queue: [NSRunningApplication] = [], total = 0           // the slow, one-at-a-time quit in progress
    var clearing = false, restartAfter = false, refused: [String] = []   // Tools ▸ Quit All (and Restart)
    var waiting: [NSRunningApplication] = []                    // asked to quit, still open after `patience`: a save prompt
    var patience: TimeInterval = 8
    var restartMac: () -> Void = {                              // the --selftest swaps this for a print
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "tell application \"loginwindow\" to «event aevtrrst»"]; try? p.run()
    }
    var status: String? { didSet { item.button?.toolTip = status ?? "Focus" } }
    lazy var never = NeverModel(self)
    let pill = SessionPill()
    /// Where Focus's own menu bar icon is on screen: the apps fly into it and back out of it.
    var iconPoint: NSPoint {
        if let f = item.button?.window?.frame, f.width > 0 { return NSPoint(x: f.midX, y: f.midY) }
        let s = NSScreen.main!.frame; return NSPoint(x: s.maxX - 60, y: s.maxY - 12)
    }
    var neverWindow: NSWindow?
    let when: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; f.doesRelativeDateFormatting = true; return f
    }()

    var sessions: [Session] {                                   // newest first, last 12 kept
        get { store.array(forKey: "sessions") as? [Session] ?? [] }
        set { store.set(Array(newValue.prefix(12)), forKey: "sessions") }
    }
    var excluded: [String] {                                    // "keep open": the user's per-session picks
        get { store.stringArray(forKey: "excluded") ?? [] }
        set { store.set(newValue, forKey: "excluded") }
    }
    var neverClose: [String] {                                  // "never close": the user's permanent list
        get { store.stringArray(forKey: "neverClose") ?? [] }
        set { store.set(newValue, forKey: "neverClose") }
    }
    var snapshots: Bool {                                       // screenshot at session start, deleted on restore
        get { store.object(forKey: "snapshots") as? Bool ?? true }
        set { store.set(newValue, forKey: "snapshots") }
    }
    /// ~/Library/Application Support/Focus — snapshots live here and nowhere else.
    lazy var folder: URL = {                                    // the self-test gets its own, so it can never prune a real snapshot
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(store == .standard ? "Focus" : "Focus-selftest", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    /// Menu bar icon colours as hex: primary = the ring, secondary = the dot ("" = same as the ring).
    /// Both "" = default (a template image, black/white like every other menu bar icon).
    var iconColor: String {
        get { store.string(forKey: "iconColor") ?? "" }
        set { store.set(newValue, forKey: "iconColor"); store.set(true, forKey: "colourTipSeen"); redrawIcon() }
    }
    var iconColor2: String {
        get { store.string(forKey: "iconColor2") ?? "" }
        set { store.set(newValue, forKey: "iconColor2"); store.set(true, forKey: "colourTipSeen"); redrawIcon() }
    }
    /// A new user sees the default (white) icon and one quiet hint that it can be theirs; gone once any colour is picked.
    var showColourTip: Bool { !store.bool(forKey: "colourTipSeen") && iconColor.isEmpty && iconColor2.isEmpty }
    @objc func colourTip() { store.set(true, forKey: "colourTipSeen"); openWheel(dot: false) }
    static let rainbow: NSImage = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { r in
        let dot = NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)); dot.addClip()
        NSGradient(colors: ["FF5F5F", "FFD75F", "5FD7AF", "5FAFFF", "A78BFA", "FF87FF"].compactMap(hexColor))?.draw(in: r, angle: 0)
        return true
    }
    var ringColor: NSColor? { hexColor(iconColor) }
    var dotColor: NSColor? { hexColor(iconColor2) ?? ringColor }
    /// Every icon frame goes through here, so the chosen colours hold through the focus animation too.
    func drawIcon(_ t: CGFloat, hunt: Bool = false) { item.button?.image = glyph(t, hunt: hunt, ring: ringColor, dot: dotColor) }
    func redrawIcon() { drawIcon(focused ? 1 : 0) }
    func setIcon(_ img: NSImage) { redrawIcon() }
    @objc func pickPreset(_ s: NSMenuItem) {
        let pair = s.representedObject as? [String] ?? ["", ""]
        iconColor = pair[0]; iconColor2 = pair.count > 1 ? pair[1] : ""
    }
    var wheelForDot = false
    @objc func wheelRing() { openWheel(dot: false) }
    @objc func wheelDot() { openWheel(dot: true) }
    @objc func dotSameAsRing() { iconColor2 = "" }
    /// The 360° colour wheel (macOS colour panel opened on its wheel; its eyedropper picks any colour on screen).
    func openWheel(dot: Bool) {
        wheelForDot = dot
        let p = NSColorPanel.shared
        p.showsAlpha = false; p.mode = .wheel
        p.color = (dot ? dotColor : ringColor) ?? .controlAccentColor
        p.setTarget(self); p.setAction(#selector(colorPanelChanged(_:)))
        // A menu bar app is often refused activation on macOS 14+, and the colour panel hides itself whenever its
        // app isn't active — so it would vanish the instant it opened. Keep it up regardless, floating.
        p.hidesOnDeactivate = false; p.level = .floating
        NSApp.activate(ignoringOtherApps: true); p.makeKeyAndOrderFront(nil); p.orderFrontRegardless()
    }
    @objc func colorPanelChanged(_ p: NSColorPanel) {            // live, as the wheel moves
        if wheelForDot { iconColor2 = hexString(p.color) } else { iconColor = hexString(p.color) }
    }
    var hideMode: Bool {                                        // hide instead of quit: instant, but keeps the memory
        get { store.bool(forKey: "hideMode") }
        set { store.set(newValue, forKey: "hideMode") }
    }
    var focused: Bool {
        get { store.bool(forKey: "focused") }
        set {
            let was = store.bool(forKey: "focused")
            store.set(newValue, forKey: "focused")
            if newValue != was { animateIcon(to: newValue) } else { setIcon(glyph(focused: newValue)) }
        }
    }
    /// The system's "reopen windows when an app relaunches" (System Settings ▸ Desktop & Dock ▸
    /// "Close windows when quitting an application", inverted). Without it a quit app comes back empty.
    var keepWindows: Bool {
        get { store.bool(forKey: "NSQuitAlwaysKeepsWindows") }
        set {
            CFPreferencesSetAppValue("NSQuitAlwaysKeepsWindows" as CFString, newValue as CFBoolean, kCFPreferencesAnyApplication)
            CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        }
    }

    init(store: UserDefaults = .standard) {
        self.store = store
        super.init()
        // macOS saves a status item's visibility under its autosave name in the app's defaults. A --selftest copy
        // hides its icon under its own name (so it never shows a second icon, and never hides the real one);
        // the real Focus always shows its icon.
        if store != .standard { item.autosaveName = "focus-selftest"; item.isVisible = false } else { item.isVisible = true }
        let menu = NSMenu(); menu.delegate = self; menu.minimumWidth = menuWidth; item.menu = menu
        if !store.bool(forKey: "setUp") { keepWindows = true; store.set(true, forKey: "setUp") }
        if store == .standard {                                 // the real Focus only — never a --selftest instance
            healSystemSwitcher()
        }
        setIcon(glyph(focused: focused))
        pruneSnapshots()
    }

    /// System apps (Finder & co. live in CoreServices), Focus itself, and the user's Never close list.
    func system(_ a: NSRunningApplication) -> Bool {
        a.bundleURL?.path.hasPrefix("/System/Library/CoreServices/") ?? true || a.bundleIdentifier == Bundle.main.bundleIdentifier
    }
    func protected(_ a: NSRunningApplication) -> Bool { system(a) || neverClose.contains(a.bundleIdentifier ?? "") }

    /// Dock / ⌘⇥ apps Focus may touch. Menu bar apps are `.accessory`: never listed, never touched.
    func apps() -> [NSRunningApplication] { ws.runningApplications.filter { $0.activationPolicy == .regular && !protected($0) } }
    func leaving() -> [NSRunningApplication] { apps().filter { !excluded.contains($0.bundleIdentifier ?? "") } }
    func memory(_ a: NSRunningApplication) -> UInt64 { mem[a.processIdentifier] ?? 0 }
    /// Apps the user could add to Never close: anything in the Dock that isn't a system app.
    func candidates() -> [String] { ws.runningApplications.filter { $0.activationPolicy == .regular && !system($0) }.compactMap(\.bundleIdentifier) }

    // MARK: session

    func park(quit: Bool) {
        let out = leaving()
        guard !out.isEmpty else { return }
        // Instant: the pill plays the moment the key goes down. The snapshot is grabbed in the background in the
        // same instant (the pill is still invisible then) and the quitting starts once it's on disk.
        pill.play(start: true, icons: out.compactMap { $0.bundleURL.map { ws.icon(forFile: $0.path) } }, target: iconPoint, label: "Focus")
        sessions.insert(["date": Date(), "apps": out.compactMap { a in a.bundleURL.map { ["path": $0.path, "hidden": a.isHidden] as [String: Any] } }], at: 0)
        focused = true
        let go = { [self] in
            if !quit { out.forEach { $0.hide() }; return }
            queue = out.sorted { memory($0) > memory($1) }; total = queue.count   // biggest first: memory comes back soonest
            quitNext()
        }
        guard snapshots, CGPreflightScreenCaptureAccess() else { return go() }   // no permission: skip silently, never prompt
        snapshot { [self] shot in
            if let shot { sessions = sessions.enumerated().map { $0.offset == 0 ? $0.element.merging(["shot": shot]) { $1 } : $0.element } }
            pruneSnapshots(); go()
        }
    }

    /// One app at a time: ask it to quit the normal way (it saves its state; unsaved work prompts), wait until it
    /// has really gone, pause, then the next. Never forced. An app still open after `patience` is almost always
    /// sitting on a "Save changes?" prompt: it goes on the waiting list and the queue moves on without it.
    func quitNext() {
        guard focused || clearing, let a = queue.first else { return finishQueue() }
        if protected(a) || (!clearing && excluded.contains(a.bundleIdentifier ?? "")) { queue.removeFirst(); return quitNext() }   // marked keep / critical since it began
        status = "Saving and quitting \(a.localizedName ?? "app") · \(total - queue.count + 1) of \(total)"
        a.terminate()
        let started = Date()
        func check() {
            guard queue.first === a else { return }             // cancelled by Bring Back
            if a.isTerminated || Date().timeIntervalSince(started) > patience {
                if !a.isTerminated { waiting.append(a) }
                queue.removeFirst()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.quitNext() }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: check)
            }
        }
        check()
    }

    /// The queue is done. Anything on the waiting list is brought forward so its save prompt is in front of you,
    /// not buried. A restart waits (up to 2 min) for those prompts to be answered; if one isn't, it's cancelled.
    func finishQueue() {
        queue = []; status = nil
        let wasClearing = clearing, restart = restartAfter
        clearing = false; restartAfter = false
        waiting = waiting.filter { !$0.isTerminated }
        if let first = waiting.first {
            status = "Waiting for you to save in " + waiting.compactMap(\.localizedName).joined(separator: ", ")
            first.unhide(); first.activate(options: [.activateAllWindows])
        }
        guard wasClearing && restart else { return watchWaiting() }
        let deadline = Date().addingTimeInterval(120)
        func check() {
            waiting = waiting.filter { !$0.isTerminated }
            if waiting.isEmpty { status = nil; return restartMac() }
            if Date() > deadline {
                refused = waiting.compactMap(\.localizedName); status = nil
                return tell("Restart cancelled", "\(refused.joined(separator: ", ")) didn't quit — still waiting for you to save something.")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: check)
        }
        check()
    }
    /// Clears the "waiting for you to save" status once those apps have gone (saved, or Don't Save).
    func watchWaiting() {
        waiting = waiting.filter { !$0.isTerminated }
        if waiting.isEmpty { if status?.hasPrefix("Waiting") == true { status = nil }; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.watchWaiting() }
    }

    /// Tools ▸ Quit All Apps (and optionally restart): everything goes except Critical System Processes, Focus and
    /// nothing else — "keep open" ticks don't apply. Same slow, safe quit; saved as a Past session.
    func quitAll(restart: Bool, only: Set<String>? = nil, confirm: Bool = true) {
        guard !focused, !clearing else { return }
        let out: [NSRunningApplication] = ws.runningApplications.filter { app in
            app.activationPolicy == .regular && !protected(app)
                && (only?.contains(app.bundleIdentifier ?? "") ?? true)
        }
        if confirm {
            let a = NSAlert()
            a.messageText = out.isEmpty ? (restart ? "Restart your Mac?" : "Nothing to quit") : "Quit \(apps(out.count))\(restart ? " and restart?" : "?")"
            a.informativeText = (out.isEmpty ? "" : out.compactMap(\.localizedName).joined(separator: ", ") + ".\n\n")
                + staysOpen() + "Apps with unsaved work ask first; nothing is forced."
                + (restart ? " Your Mac restarts once everything has quit." : " You can reopen them all from Past sessions.")
            if out.isEmpty && !restart { a.addButton(withTitle: "OK"); NSApp.activate(ignoringOtherApps: true); a.runModal(); return }
            a.addButton(withTitle: restart ? "Quit All & Restart" : "Quit All"); a.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        guard !out.isEmpty else { if restart { restartMac() }; return }
        sessions.insert(["date": Date(), "kind": "quit all",
                         "apps": out.compactMap { a in a.bundleURL.map { ["path": $0.path, "hidden": a.isHidden] as [String: Any] } }], at: 0)
        pill.play(start: true, icons: out.compactMap { $0.bundleURL.map { ws.icon(forFile: $0.path) } }, target: iconPoint, label: "Clear")
        clearing = true; restartAfter = restart; refused = []
        queue = out.sorted { memory($0) > memory($1) }; total = queue.count
        quitNext()
    }
    /// Says which of the user's own Critical System Processes are open and will stay — named from their list, never assumed.
    func staysOpen() -> String {
        let names = ws.runningApplications.filter { $0.activationPolicy == .regular && neverClose.contains($0.bundleIdentifier ?? "") }.compactMap(\.localizedName)
        return names.isEmpty ? "" : names.joined(separator: ", ") + (names.count == 1 ? " stays" : " stay") + " open (Critical System Processes). "
    }
    func tell(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true); a.runModal()
    }
    /// Tools ▸ Force Quit All: the blunt one. Same spared set; unsaved work is lost, so it asks first, in red.
    func forceQuitAll(only: Set<String>? = nil, confirm: Bool = true) {
        guard !focused, !clearing else { return }
        let out: [NSRunningApplication] = ws.runningApplications.filter { app in
            app.activationPolicy == .regular && !protected(app)
                && (only?.contains(app.bundleIdentifier ?? "") ?? true)
        }
        guard !out.isEmpty else { if confirm { tell("Nothing to force quit", "Only macOS's own apps and your Critical System Processes are open.") }; return }
        if confirm {
            let a = NSAlert(); a.alertStyle = .critical
            a.messageText = "Force quit \(apps(out.count))?"
            a.informativeText = out.compactMap(\.localizedName).joined(separator: ", ")
                + ".\n\nUnsaved work in these apps will be lost. " + staysOpen() + "You can reopen them all from Past sessions."
            a.addButton(withTitle: "Force Quit All"); a.addButton(withTitle: "Cancel")
            a.buttons[0].hasDestructiveAction = true
            NSApp.activate(ignoringOtherApps: true)
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        sessions.insert(["date": Date(), "kind": "force quit",
                         "apps": out.compactMap { a in a.bundleURL.map { ["path": $0.path, "hidden": a.isHidden] as [String: Any] } }], at: 0)
        pill.play(start: true, icons: out.compactMap { $0.bundleURL.map { ws.icon(forFile: $0.path) } }, target: iconPoint, label: "Clear")
        out.forEach { $0.forceTerminate() }
    }
    @objc func forceQuitAllApps() { forceQuitAll() }
    @objc func openActivityMonitor() { openApp("com.apple.ActivityMonitor") }
    @objc func openSystemSettings() { openApp("com.apple.systempreferences") }
    func openApp(_ id: String) {
        guard let url = ws.urlForApplication(withBundleIdentifier: id) else { return }
        ws.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    @objc func quitAllApps() { quitAll(restart: false) }
    @objc func quitAllRestart() { quitAll(restart: true) }

    /// Relaunch or unhide every app in the session, one at a time, windows restored; hidden ones stay hidden.
    func open(_ s: Session) {
        queue = []; status = nil; focused = false
        pill.play(start: false, icons: (s["apps"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }.map { ws.icon(forFile: $0) },
                  target: iconPoint, label: "Back")
        relaunch(ArraySlice(s["apps"] as? [[String: Any]] ?? []))
    }

    /// The whole main display, silently, via the system's own screencapture — off the main thread, so nothing
    /// waits on it. Only called once Screen Recording is already granted (it would prompt otherwise).
    /// Gives up after 2 s so a session never stalls on it.
    func snapshot(_ done: @escaping (String?) -> Void) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH.mm.ss"
        let path = folder.appendingPathComponent("session-\(f.string(from: Date())).jpg").path
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); p.arguments = ["-x", "-t", "jpg", path]
        var finished = false
        let finish = { (r: String?) in DispatchQueue.main.async { if !finished { finished = true; done(r) } } }
        p.terminationHandler = { _ in finish(FileManager.default.fileExists(atPath: path) ? path : nil) }
        do { try p.run() } catch { return finish(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if !finished { p.terminate(); finish(nil) } }
    }
    /// Keeps the newest snapshot and one spare; anything older goes. (Names are timestamps, so they sort by age.)
    func pruneSnapshots() {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasPrefix("session-") }.sorted()
        for name in names.dropLast(2) { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
    }
    func relaunch(_ rest: ArraySlice<[String: Any]>) {
        guard let e = rest.first else { return }
        if let path = e["path"] as? String {
            let hidden = e["hidden"] as? Bool ?? false
            if let a = ws.runningApplications.first(where: { $0.bundleURL?.path == path }) {
                if !hidden { a.unhide() }
            } else {
                let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = false; cfg.hides = hidden
                // Tabs back even though Chrome's own setting is "New Tab page" — but nothing plays until you click:
                // a restored YouTube tab must not start blaring (user's rule).
                if Bundle(path: path)?.bundleIdentifier == chrome { cfg.arguments = ["--restore-last-session", "--autoplay-policy=user-gesture-required"] }
                ws.openApplication(at: URL(fileURLWithPath: path), configuration: cfg)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { self.relaunch(rest.dropFirst()) }
    }

    /// Session apps still open after their turn: usually a save prompt waiting for you.
    func stragglers() -> [NSRunningApplication] {
        guard focused, !hideMode else { return [] }
        let waiting = Set(queue.map(\.processIdentifier))
        let paths = Set((sessions.first?["apps"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String })
        return ws.runningApplications.filter { paths.contains($0.bundleURL?.path ?? "") && !$0.isHidden && !protected($0) && !waiting.contains($0.processIdentifier) }
    }

    func toggle() {
        item.menu?.cancelTracking()
        if !focused { return park(quit: !hideMode) }
        if let s = sessions.first { open(s) } else { focused = false }
    }
    /// ~0.7 s at 60 fps, ease-out; runs in common modes so it plays even with the menu open.
    var anim: Timer?
    func animateIcon(to on: Bool) {
        anim?.invalidate()
        let start = Date(), duration = on ? 0.75 : 0.45
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] tm in
            let p = min(1, Date().timeIntervalSince(start) / duration), e = 1 - pow(1 - p, 3)
            if on { self?.drawIcon(p, hunt: true) } else { self?.drawIcon(1 - e) }   // in: phased timeline · out: ease back
            if p >= 1 { tm.invalidate() }
        }
        RunLoop.main.add(t, forMode: .common); anim = t
    }
    func showMenu() { item.button?.performClick(nil) }

    func flip(_ list: ReferenceWritableKeyPath<Focus, [String]>, _ id: String) -> Bool {
        self[keyPath: list] = self[keyPath: list].contains(id) ? self[keyPath: list].filter { $0 != id } : self[keyPath: list] + [id]
        button?.needsDisplay = true
        return self[keyPath: list].contains(id)
    }

    @objc func pick() {
        let p = NSOpenPanel()
        p.directoryURL = URL(fileURLWithPath: "/Applications"); p.allowedContentTypes = [.applicationBundle]
        p.allowsMultipleSelection = true; p.prompt = "Add"; p.message = "Choose apps Focus must never quit"
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK else { return }
        for url in p.urls { if let id = Bundle(url: url)?.bundleIdentifier, !neverClose.contains(id) { neverClose.append(id) } }
    }
    @objc func reopen(_ s: NSMenuItem) { open(sessions[s.tag]) }
    @objc func forget(_ s: NSMenuItem) { sessions.remove(at: s.tag) }
    @objc func snaps() {
        if !CGPreflightScreenCaptureAccess() { snapshots = true; CGRequestScreenCaptureAccess(); return }   // the one deliberate ask
        snapshots.toggle()
    }
    @objc func viewShot(_ s: NSMenuItem) { if let p = s.representedObject as? String { ws.open(URL(fileURLWithPath: p)) } }
    @objc func hiding() { hideMode.toggle() }
    @objc func windows() { keepWindows.toggle() }
    @objc func look() { stragglers().first?.activate() }       // bring the save prompt forward; never force
    @objc func showNever() {
        never.reload()
        if neverWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: NeverView(m: never)))
            w.title = "Critical System Processes"; w.styleMask = [.titled, .closable]; w.isReleasedWhenClosed = false; w.center()
            neverWindow = w
        }
        NSApp.activate(ignoringOtherApps: true); neverWindow?.makeKeyAndOrderFront(nil); neverWindow?.orderFrontRegardless()
    }
    @objc func login() {
        let s = SMAppService.mainApp
        try? (s.status == .enabled ? s.unregister() : s.register())
    }
    @objc func bye() { NSApp.terminate(nil) }

    // MARK: menu (rebuilt each time it opens, so it never goes stale)

    func appIcon(_ path: String) -> NSImage { let i = ws.icon(forFile: path); i.size = NSSize(width: 16, height: 16); return i }
    func appName(_ path: String) -> String { FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "") }
    func apps(_ n: Int) -> String { n == 1 ? "1 app" : "\(n) apps" }
    func path(_ id: String) -> String? { ws.urlForApplication(withBundleIdentifier: id)?.path }

    func menuNeedsUpdate(_ m: NSMenu) {
        m.removeAllItems()
        @discardableResult
        func add(_ title: String, _ action: Selector?, image: NSImage? = nil, to menu: NSMenu? = nil) -> NSMenuItem {
            let i = (menu ?? m).addItem(withTitle: title, action: action, keyEquivalent: "")
            i.target = self; i.image = image
            return i
        }
        func header(_ t: String, in menu: NSMenu? = nil) {
            if #available(macOS 14, *) { (menu ?? m).addItem(.sectionHeader(title: t)) } else { add(t, nil, to: menu).isEnabled = false }
        }
        func view(_ v: NSView, in menu: NSMenu? = nil) { let i = NSMenuItem(); i.view = v; (menu ?? m).addItem(i) }

        mem = memoryByPid()
        if let status { header(status) }
        if focused, let shot = sessions.first?["shot"] as? String, let img = NSImage(contentsOfFile: shot) {
            header("What you were doing — click to open")
            let w = menuWidth - 28, h = (w * img.size.height / max(img.size.width, 1)).rounded()
            view(Thumb(img, NSSize(width: w, height: h)) { [unowned self] in self.ws.open(URL(fileURLWithPath: shot)) })
            m.addItem(.separator())
        }

        // Keep open — this session's picks.
        header(focused ? "In session · kept open" : "Keep open this session — click to choose")
        let running = apps().compactMap { a in a.bundleIdentifier.flatMap { id in a.bundleURL.map { (id, $0.path) } } }
        let idle = excluded.filter { id in !running.contains { $0.0 == id } && !neverClose.contains(id) }.compactMap { id in path(id).map { (id, $0) } }
        for (id, p) in running + idle {
            let size = ws.runningApplications.first { $0.bundleIdentifier == id }.map(memory) ?? 0
            let detail = size > 0 ? gb(size) : ""
            view(AppRow(appName(p), appIcon(p), detail: detail, on: excluded.contains(id)) { [unowned self] in self.flip(\.excluded, id) })
        }

        // Critical system processes — never quit or hidden by Focus. Click to take one off; it moves up next time.
        m.addItem(.separator())
        header("Critical System Processes — never quit")
        for id in neverClose {
            guard let p = path(id) else { continue }
            view(AppRow(appName(p), appIcon(p), on: true, onMark: "lock.circle.fill") { [unowned self] in self.flip(\.neverClose, id) })
        }
        add("Add or remove…", #selector(showNever), image: symbol("plus.circle"))

        let left = stragglers()
        if !left.isEmpty {                                      // shown only when something is still eating memory
            m.addItem(.separator())
            add("Still open — probably a save prompt: " + left.compactMap(\.localizedName).joined(separator: ", "),
                #selector(look), image: symbol("exclamationmark.bubble"))
        }

        m.addItem(.separator())
        if showColourTip {
            add("Make the icon yours — pick its colours…", #selector(colourTip), image: Focus.rainbow)
            m.addItem(.separator())
        }
        if !sessions.isEmpty {
            let past = add("Past sessions", nil, image: symbol("clock.arrow.circlepath")), sub = NSMenu()
            for (n, s) in sessions.enumerated() {
                let list = s["apps"] as? [[String: Any]] ?? []
                let date = (s["date"] as? Date).map { when.string(from: $0) } ?? "?"
                let i = add("\(date) · \(apps(list.count))" + ((s["kind"] as? String).map { " · " + $0 } ?? ""), nil, to: sub), one = NSMenu()
                for p in list.compactMap({ $0["path"] as? String }) { add(appName(p), nil, image: appIcon(p), to: one) }
                one.addItem(.separator())
                if let shot = s["shot"] as? String, FileManager.default.fileExists(atPath: shot) { add("View snapshot", #selector(viewShot), image: symbol("photo"), to: one).representedObject = shot }
                add("Open all", #selector(reopen), image: symbol("arrow.up.forward.app"), to: one).tag = n
                add("Delete", #selector(forget), image: symbol("trash"), to: one).tag = n
                i.submenu = one
            }
            past.submenu = sub
        }
        let tools = add("Tools", nil, image: symbol("wrench.and.screwdriver")), tm = NSMenu()
        tm.autoenablesItems = false
        let busy = focused || clearing
        add("Quit All Apps…", #selector(quitAllApps), image: symbol("xmark.circle"), to: tm).isEnabled = !busy
        add("Quit All Apps & Restart Mac…", #selector(quitAllRestart), image: symbol("arrow.clockwise.circle"), to: tm).isEnabled = !busy
        add("Force Quit All Apps…", #selector(forceQuitAllApps), image: symbol("bolt.circle"), to: tm).isEnabled = !busy
        tm.addItem(.separator())
        add("Open Activity Monitor", #selector(openActivityMonitor), image: symbol("waveform.path.ecg"), to: tm)
        add("Open System Settings", #selector(openSystemSettings), image: symbol("gearshape.2"), to: tm)
        tm.addItem(.separator())
        let kept = neverClose.compactMap(path).map(appName)
        add(busy ? "End the session first" : kept.isEmpty ? "Add apps to Critical System Processes to keep them" : "Keeps " + kept.joined(separator: ", "), nil, to: tm).isEnabled = false
        tools.submenu = tm
        let settings = add("Settings", nil, image: symbol("gearshape")), sub = NSMenu()
        let two = { (a: NSColor?, b: NSColor?) -> NSImage in      // a mini icon in two colours, for menu rows
            let g = glyph(0, ring: a ?? .labelColor, dot: b ?? a ?? .labelColor); g.size = NSSize(width: 16, height: 16); return g
        }
        let colour = add("Icon Colour", nil, image: two(ringColor, dotColor), to: sub), cm = NSMenu()
        cm.minimumWidth = 300
        func hdr(_ t: String) { if #available(macOS 14, *) { cm.addItem(.sectionHeader(title: t)) } else { add(t, nil, to: cm).isEnabled = false } }
        hdr("Presets")
        let def = add("Default (white)", #selector(pickPreset(_:)), image: swatch(nil), to: cm); def.representedObject = ["", ""]
        def.state = iconColor.isEmpty && iconColor2.isEmpty ? .on : .off
        let acc = hexString(.controlAccentColor)
        let sys = add("System Accent", #selector(pickPreset(_:)), image: two(.controlAccentColor, .controlAccentColor), to: cm)
        sys.representedObject = [acc, ""]; sys.state = iconColor == acc && iconColor2.isEmpty ? .on : .off
        for (name, a, b) in theme.iconPresets {
            let i = add(name, #selector(pickPreset(_:)), image: two(hexColor(a), hexColor(b)), to: cm)
            i.representedObject = [a, a == b ? "" : b]
            i.state = iconColor == a && (iconColor2 == b || (a == b && iconColor2.isEmpty)) ? .on : .off
        }
        let grid = theme.iconHues.map(shades)
        hdr("Ring — primary")
        let gi = NSMenuItem(); gi.view = ColorGrid(grid, selected: iconColor) { [unowned self] h in self.iconColor = h }; cm.addItem(gi)
        add("Colour Wheel…", #selector(wheelRing), image: symbol("paintpalette"), to: cm)
        hdr("Dot — secondary")
        let gd = NSMenuItem(); gd.view = ColorGrid(grid, selected: iconColor2) { [unowned self] h in self.iconColor2 = h }; cm.addItem(gd)
        add("Same as Ring", #selector(dotSameAsRing), image: symbol("link"), to: cm).state = iconColor2.isEmpty ? .on : .off
        add("Colour Wheel…", #selector(wheelDot), image: symbol("paintpalette"), to: cm)
        colour.submenu = cm
        sub.addItem(.separator())
        add("Hide apps instead of quitting", #selector(hiding), to: sub).state = hideMode ? .on : .off
        if CGPreflightScreenCaptureAccess() {
            add("Take a snapshot when a session starts", #selector(snaps), to: sub).state = snapshots ? .on : .off
        } else {
            add("Allow snapshots… (asks for Screen Recording once)", #selector(snaps), image: symbol("camera"), to: sub)
        }
        add("Reopen windows as they were", #selector(windows), to: sub).state = keepWindows ? .on : .off
        add("Open at login", #selector(login), to: sub).state = SMAppService.mainApp.status == .enabled ? .on : .off
        sub.addItem(.separator())
        add("⌘⇧E opens this menu", nil, to: sub).isEnabled = false
        add("Quit Focus", #selector(bye), image: symbol("power"), to: sub)
        settings.submenu = sub

        m.addItem(.separator())
        let b = BigButton(
            title: { [unowned self] in self.focused ? "End Session" : "Start Session Now" },
            caption: { [unowned self] in
                if self.focused {
                    let n = self.apps((self.sessions.first?["apps"] as? [Any])?.count ?? 0)
                    return self.queue.isEmpty ? "Reopens \(n) as they were" : "Stops quitting and reopens \(n) as they were"
                }
                let out = self.leaving()
                let kept = self.ws.runningApplications.filter { $0.activationPolicy == .regular && !self.system($0) }.count - out.count
                if out.isEmpty { return "Nothing to \(self.hideMode ? "hide" : "quit") — everything is kept" }
                if self.hideMode { return "Hides \(self.apps(out.count)) · keeps \(kept)" }
                return "Saves and quits \(self.apps(out.count)) · frees ~\(gb(out.reduce(0) { $0 + self.memory($1) })) · keeps \(kept)"
            },
            action: { [unowned self] in self.toggle() })
        button = b; view(b)
    }
}

/// The Never close window: every app Focus could touch, with a switch. Switched on = Focus never quits or hides it.
final class NeverModel: ObservableObject {
    struct Entry: Identifiable { let id: String, name: String, icon: NSImage, running: Bool }
    unowned let f: Focus
    @Published var on: Set<String> = []
    @Published var entries: [Entry] = []
    init(_ f: Focus) { self.f = f }
    func reload() {
        on = Set(f.neverClose)
        let running = Set(f.candidates())
        var seen = Set<String>()
        entries = (f.neverClose + f.candidates().sorted { (f.path($0).map(f.appName) ?? "") < (f.path($1).map(f.appName) ?? "") })
            .filter { seen.insert($0).inserted }
            .compactMap { id in f.path(id).map { Entry(id: id, name: f.appName($0), icon: f.ws.icon(forFile: $0), running: running.contains(id)) } }
    }
    func set(_ id: String, _ v: Bool) {
        f.neverClose = v ? f.neverClose + [id] : f.neverClose.filter { $0 != id }
        on = Set(f.neverClose)
    }
    func add() { f.pick(); reload() }
}

struct NeverView: View {
    @ObservedObject var m: NeverModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Critical System Processes").font(.system(size: 20, weight: .semibold))
                Text("Focus never quits or hides the apps switched on here — the ones that must always run. macOS's own apps, menu bar–only apps and Focus itself are always safe.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            List(m.entries) { e in
                HStack(spacing: 10) {
                    Image(nsImage: e.icon).resizable().frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.name)
                        if !e.running { Text("Not open").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { m.on.contains(e.id) }, set: { m.set(e.id, $0) })).toggleStyle(.switch).labelsHidden()
                }
                .padding(.vertical, 3)
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
            HStack {
                Button("Add App…") { m.add() }
                Spacer()
                Button("Done") { NSApp.keyWindow?.close() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440, height: 560)
    }
}

/// `Focus --make-icon DIR`: writes the app icon set (the menu bar mark at rest, white on the pill's near-black,
/// on the macOS icon grid) so the icon is always drawn by the same glyph() as the menu bar and the pill.
if let i = CommandLine.arguments.firstIndex(of: "--make-icon"), CommandLine.arguments.count > i + 1 {
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (px, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"), (256, "128x128@2x"),
                       (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let u = CGFloat(px) / 1024                                     // 1024-pt grid: 824-pt tile, 100-pt margin
        let tile = NSRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
        let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * u, yRadius: 185 * u)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.35); shadow.shadowBlurRadius = 20 * u
        shadow.shadowOffset = NSSize(width: 0, height: -8 * u); shadow.set()
        NSGradient(starting: NSColor(white: 0.16, alpha: 1), ending: NSColor(white: 0.05, alpha: 1))!.draw(in: shape, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        theme.hudEdge.setStroke(); shape.lineWidth = max(1, 3 * u); shape.stroke()
        let mark = painted(glyph(0), theme.hudInk, NSSize(width: 512, height: 512))!
        NSGraphicsContext.current!.cgContext.draw(mark, in: tile.insetBy(dx: 120 * u, dy: 120 * u))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("icon_\(name).png"))
    }
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)                             // no Dock icon, not in Cmd-Tab

// One Focus at a time: a second copy (double launch, login item + manual open…) quits at once.
let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.labern.focus").filter { $0 != .current }
if CommandLine.arguments.contains("--pill-demo") {          // watch the start and end shows without a session
    let p = SessionPill(), ws = NSWorkspace.shared
    let icons = ["com.google.Chrome", "md.obsidian", "com.apple.iWork.Keynote", "com.apple.Preview", "com.readdle.SparkDesktop", "com.openai.chat"]
        .compactMap { ws.urlForApplication(withBundleIdentifier: $0) }.map { ws.icon(forFile: $0.path) }
    // `--pill-demo X Y`: the menu bar icon's centre in top-left screen points (as Accessibility reports it).
    let a = CommandLine.arguments, i = a.firstIndex(of: "--pill-demo")!, s = NSScreen.main!.frame
    let x = a.count > i + 2 ? Double(a[i + 1]) ?? Double(s.maxX - 560) : Double(s.maxX - 560), y = a.count > i + 2 ? Double(a[i + 2]) ?? 12 : 12
    let target = NSPoint(x: x, y: Double(s.maxY) - y)
    p.play(start: true, icons: icons, target: target, label: "Focus")
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { p.play(start: false, icons: icons, target: target, label: "Back") }
    DispatchQueue.main.asyncAfter(deadline: .now() + 4.4) { exit(0) }
    app.run()
}
if !others.isEmpty && !CommandLine.arguments.contains(where: { $0.hasPrefix("--selftest") }) { print("Focus is already running (pid \(others[0].processIdentifier))"); exit(0) }

/// `Focus --selftest`: the real session path, on TextEdit only, with its own settings store. Aborts before
/// touching anything if the session would include any other app.
/// `Focus --selftest-unsaved`: an app stuck on a save prompt (a stand-in that refuses to quit) must not stall
/// the queue: it goes on the waiting list after `patience`, the rest quits, and it is brought forward.
if CommandLine.arguments.contains("--selftest-unsaved") {
    let suite = "com.labern.focus.selftest"
    UserDefaults.standard.removePersistentDomain(forName: suite)
    let t = Focus(store: UserDefaults(suiteName: suite)!)
    t.patience = 3
    func say(_ s: String) { print("selftest:", s); fflush(stdout) }
    let edit = "com.labern.focus.savepromptstandin", preview = "com.apple.calculator"
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        let ids = t.apps().compactMap(\.bundleIdentifier)
        guard ids.contains(edit), ids.contains(preview) else { say("ABORT — needs the stand-in and Calculator running"); exit(1) }
        t.excluded = ids.filter { $0 != edit && $0 != preview }
        guard Set(t.leaving().compactMap(\.bundleIdentifier)) == [edit, preview] else { say("ABORT — would quit \(t.leaving().compactMap(\.bundleIdentifier))"); exit(1) }
        t.snapshots = false
        let started = Date()
        t.park(quit: true)
        func poll() {
            if t.queue.isEmpty && !(t.status ?? "").hasPrefix("Saving") {
                let secs = Int(Date().timeIntervalSince(started))
                say("queue finished in \(secs) s (must not wait 60 s on a save prompt): \(secs < 15 ? "✓" : "✗")")
                say("Calculator (the other app) quit: \(t.ws.runningApplications.contains { $0.bundleIdentifier == preview } ? "✗" : "✓")")
                say("stuck app on the waiting list: \(t.waiting.contains { $0.bundleIdentifier == edit } ? "✓" : "✗")  status: \(t.status ?? "nil")")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    say("stuck app brought forward (its prompt in front): \(t.ws.frontmostApplication?.bundleIdentifier == edit ? "✓" : "✗")")
                    UserDefaults.standard.removePersistentDomain(forName: suite)
                    exit(0)
                }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: poll)
        }
        poll()
    }
    app.run()
}
if CommandLine.arguments.contains("--selftest") {
    let suite = "com.labern.focus.selftest"
    UserDefaults.standard.removePersistentDomain(forName: suite)
    let t = Focus(store: UserDefaults(suiteName: suite)!)
    func say(_ s: String) { print("selftest:", s); fflush(stdout) }
    func later(_ s: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: f) }
    let edit = "com.apple.TextEdit"
    later(0.5) {
        t.excluded = t.apps().compactMap(\.bundleIdentifier).filter { $0 != edit }
        let out = t.leaving().compactMap(\.bundleIdentifier)
        guard out == [edit] else { say("ABORT — would quit \(out)"); exit(1) }
        say("session would quit only TextEdit ✓  (protected: \(t.ws.runningApplications.filter(t.protected).compactMap(\.localizedName)))")
        let t0 = Date()
        t.park(quit: true)
        say("park() returned in \(Int(Date().timeIntervalSince(t0) * 1000)) ms (must be instant)")
        later(1.5) {
        let shot = t.sessions.first?["shot"] as? String
        say("snapshot: \(shot.map { "\($0) (\((try? FileManager.default.attributesOfItem(atPath: $0)[.size]) ?? 0) bytes)" } ?? "NONE")")
        later(6) {
            let gone = !t.ws.runningApplications.contains { $0.bundleIdentifier == edit }
            say("TextEdit quit: \(gone ? "✓" : "✗ still running")  in session: \(t.focused)")
            t.toggle()
            later(4) {
                let back = t.ws.runningApplications.contains { $0.bundleIdentifier == edit }
                say("TextEdit back: \(back ? "✓" : "✗")  in session: \(t.focused)")
                say("snapshot kept after restore: \(shot.map { FileManager.default.fileExists(atPath: $0) ? "✓" : "✗ gone" } ?? "n/a")")
                func more(_ k: Int) {                   // three more snapshots, 1.1 s apart (names are per-second)
                    guard k > 0 else {
                        let left = (try? FileManager.default.contentsOfDirectory(atPath: t.folder.path))?.filter { $0.hasPrefix("session-") }.count ?? -1
                        say("after 4 snapshots, kept: \(left) \(left == 2 ? "✓ (newest + one spare)" : "✗")")
                        // Tools ▸ Quit All & Restart, scoped to TextEdit, restart stubbed
                        var restarted = false
                        t.restartMac = { restarted = true }
                        t.excluded = [edit]                     // a "keep open" tick must NOT spare it from Quit All
                        let n0 = t.sessions.count
                        t.quitAll(restart: true, only: [edit], confirm: false)
                        say("quit-all: in session = \(t.focused) (must be false), saved as past session: \(t.sessions.count == n0 + 1 && t.sessions.first?["kind"] as? String == "quit all" ? "✓" : "✗")")
                        later(6) {
                            let gone = !t.ws.runningApplications.contains { $0.bundleIdentifier == edit }
                            say("quit-all: TextEdit quit despite keep-open tick: \(gone ? "✓" : "✗")  restart requested after: \(restarted ? "✓" : "✗")")
                            t.open(t.sessions[0])
                            later(4) {
                                say("quit-all: reopened from Past sessions: \(t.ws.runningApplications.contains { $0.bundleIdentifier == edit } ? "✓" : "✗")")
                                try? FileManager.default.removeItem(at: t.folder)
                                UserDefaults.standard.removePersistentDomain(forName: suite)
                                exit(0)
                            }
                        }
                        return
                    }
                    later(1.1) { t.snapshot { _ in t.pruneSnapshots(); more(k - 1) } }
                }
                more(3)
            }
        }
        }
    }
    app.run()
}
let focus = Focus()

// Global hotkeys via Carbon: the only route that needs no Accessibility permission.
var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
    var hk = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
    DispatchQueue.main.async {
        switch hk.id {
        case 1: focus.toggle()
        case 2: focus.showMenu()
        default: break
        }
    }
    return noErr
}, 1, &spec, nil, nil)
_ = hotkey(1, kVK_ANSI_F, cmdKey | shiftKey)                    // ⌘⇧F: start a session / bring it all back
_ = hotkey(2, kVK_ANSI_E, cmdKey | shiftKey)                    // ⌘⇧E: open the menu
app.run()
