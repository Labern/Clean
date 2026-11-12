// Focus — park the big apps (Chrome, Obsidian, Keynote…) so their memory goes to the work, then bring them
// back exactly as they were. Quitting is slow and safe: one app at a time, each asked to quit normally (so it
// saves its state, and unsaved work still prompts), waiting for it to finish before the next. Never forced.
// Restoring relaunches them one at a time with their windows (Chrome with its last session).
// Menu bar only. One file, no dependencies, no permissions.
//   ⌘⇧F   start a session (quit everything not kept) · again: bring it all back
//   ⌘⇧E   open the Focus menu: click apps to keep them for this session, then Start New Session
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

/// A global shortcut via Carbon (needs no Accessibility permission). nil = macOS refused it: another app has it.
func hotkey(_ id: UInt32, _ key: Int, _ mods: Int) -> EventHotKeyRef? {
    var ref: EventHotKeyRef?
    let err = RegisterEventHotKey(UInt32(key), UInt32(mods), EventHotKeyID(signature: 0x464F_4355, id: id), GetEventDispatcherTarget(), 0, &ref)
    return err == noErr ? ref : nil
}

/// The shortcut choices offered in Settings ▸ Shortcuts. The first of each is the default. `clash` is honest about
/// what each combination already does elsewhere on a Mac, so people can pick one that suits the apps they use.
struct KeyChoice { let label: String, mods: Int, clash: String }
let modifierChoices: [KeyChoice] = [
    KeyChoice(label: "⌘⇧", mods: cmdKey | shiftKey, clash: "Find in Files in code editors; Recents in Finder"),
    KeyChoice(label: "⌃⌥", mods: controlKey | optionKey, clash: "free, except while VoiceOver is on"),
    KeyChoice(label: "⌃⇧", mods: controlKey | shiftKey, clash: "rarely used on a Mac"),
    KeyChoice(label: "⌃⌥⌘", mods: controlKey | optionKey | cmdKey, clash: "free — three keys, nothing else uses it"),
]
func symbol(_ name: String, _ colors: [NSColor]? = nil) -> NSImage? {
    let i = NSImage(systemSymbolName: name, accessibilityDescription: nil)
    guard let colors else { return i }
    return i?.withSymbolConfiguration(.init(paletteColors: colors))
}

/// Every colour the custom menu views use. One token set: swap it to re-theme the whole menu.
struct Theme {
    // Monochrome, like the drawing on the product page: colour belongs to the icon the user picks, not the menu.
    var accent = NSColor(name: "focusAccent") { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : hexColor("171A20")! }
    var onAccent = NSColor(name: "focusOnAccent") { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white }
    var hazard = NSColor.systemRed                                  // red only for the destructive action
    var menuBackground = hexColor("1F1F21")!                       // the menu: opaque off-black, always dark (as on the product page)
    var menuEdge = NSColor(white: 1, alpha: 0.12)
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
var sessionKey = "⌘⇧F"                                         // what the Start button shows; follows Settings ▸ Shortcuts
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
        super.init(height: 106)
    }
    required init?(coder: NSCoder) { nil }
    override func mouseDown(with e: NSEvent) { down = true }
    override func mouseUp(with e: NSEvent) {
        down = false
        enclosingMenuItem?.menu?.cancelTracking()
        DispatchQueue.main.async(execute: action)
    }
    override func draw(_ r: NSRect) {
        let pill = NSRect(x: 12, y: bounds.height - 46, width: bounds.width - 24, height: 38)
        (down ? theme.accent.withAlphaComponent(0.7) : hover ? theme.accent.withAlphaComponent(0.88) : theme.accent).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 9, yRadius: 9).fill()
        let big: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: theme.onAccent]
        (title() as NSString).draw(at: NSPoint(x: pill.minX + 14, y: pill.midY - 9), withAttributes: big)
        let key: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: theme.onAccent.withAlphaComponent(0.6)]
        let k = sessionKey as NSString
        k.draw(at: NSPoint(x: pill.maxX - 14 - k.size(withAttributes: key).width, y: pill.midY - 8.5), withAttributes: key)
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: theme.faint]
        let c = caption() as NSString
        let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineBreakMode = .byWordWrapping
        var wrapped = small; wrapped[.paragraphStyle] = para
        c.draw(with: NSRect(x: 18, y: 6, width: bounds.width - 36, height: pill.minY - 10),
               options: [.usesLineFragmentOrigin], attributes: wrapped)     // plain English, wraps to two lines
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
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(target) }) ?? NSScreen.main ?? NSScreen.screens.first else { return }   // no display: skip the show
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false; w.ignoresMouseEvents = true
        w.level = .statusBar; w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let root = CALayer(); w.contentView!.wantsLayer = true; w.contentView!.layer = root
        let s = screen.backingScaleFactor, origin = screen.frame.origin
        let tgt = CGPoint(x: target.x - origin.x, y: target.y - origin.y)

        // The pill: mark + one word, bottom centre — where the eye already is when the key goes down.
        let labelWidth = (label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold)]).width
        let pill = CALayer(), size = CGSize(width: max(136, ceil(labelWidth) + 74), height: 44)   // a mode's name fits
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
    var waiting: [NSRunningApplication] = []
    var modeKeep: Set<String>?                                  // while a mode's session is quitting: the mode's apps
    var generation = 0                                          // bumped by every start and end: stale restores / snapshots stop
    var pendingRestore: [[String: Any]] = []                    // apps an in-progress restore hasn't reopened yet
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
        guard let s = (NSScreen.main ?? NSScreen.screens.first)?.frame else { return .zero }   // no display (lid shut): no crash
        return NSPoint(x: s.maxX - 60, y: s.maxY - 12)
    }
    var neverWindow: NSWindow?
    // MARK: shortcuts
    var sessionMods: Int { get { store.object(forKey: "sessionMods") as? Int ?? modifierChoices[0].mods } set { store.set(newValue, forKey: "sessionMods"); applyShortcuts() } }
    var menuMods: Int { get { store.object(forKey: "menuMods") as? Int ?? modifierChoices[0].mods } set { store.set(newValue, forKey: "menuMods"); applyShortcuts() } }
    var keyRefs: [EventHotKeyRef?] = []
    var sessionKeyTaken = false, menuKeyTaken = false
    func label(_ mods: Int) -> String { modifierChoices.first { $0.mods == mods }?.label ?? "⌘⇧" }
    /// (Re)registers both shortcuts. Takes effect at once; reports a combination another app already holds.
    func applyShortcuts() {
        keyRefs.forEach { if let k = $0 { UnregisterEventHotKey(k) } }
        let s = hotkey(1, kVK_ANSI_F, sessionMods), m = hotkey(2, kVK_ANSI_E, menuMods)
        keyRefs = [s, m]; sessionKeyTaken = s == nil; menuKeyTaken = m == nil
        sessionKey = label(sessionMods) + "F"
        button?.needsDisplay = true
    }
    func releaseShortcuts() { keyRefs.forEach { if let k = $0 { UnregisterEventHotKey(k) } }; keyRefs = [] }
    @objc func pickSessionKey(_ s: NSMenuItem) { sessionMods = s.tag }
    @objc func pickMenuKey(_ s: NSMenuItem) { menuMods = s.tag }
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
    /// Customised Logo: the app's own icon (Finder, Launchpad, Settings) in the user's colours. "" = standard.
    var logoBg: String { get { store.string(forKey: "logoBg") ?? "" } set { store.set(newValue, forKey: "logoBg"); applyLogo() } }
    var logoMark: String { get { store.string(forKey: "logoMark") ?? "" } set { store.set(newValue, forKey: "logoMark"); applyLogo() } }
    var logoCustom: Bool { !logoBg.isEmpty || !logoMark.isEmpty }
    func logoImage(_ px: Int) -> NSImage {
        let rep = appIconRep(px, bg: hexColor(logoBg), mark: hexColor(logoMark))
        let img = NSImage(size: NSSize(width: px, height: px)); img.addRepresentation(rep); return img
    }
    /// Sets (or clears) the custom icon on the installed app. Re-applied at launch, since a reinstall replaces it.
    func applyLogo() {
        guard store == .standard else { return }
        NSWorkspace.shared.setIcon(logoCustom ? logoImage(1024) : nil, forFile: Bundle.main.bundlePath, options: [])
    }
    @objc func logoStandard() { store.set("", forKey: "logoBg"); logoMark = "" }
    @objc func logoMatch() {
        store.set(iconColor.isEmpty ? "A78BFA" : iconColor, forKey: "logoBg")
        logoMark = iconColor2.isEmpty ? (iconColor.isEmpty ? "5FD7AF" : "FFFFFF") : iconColor2
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
        if store == .standard && logoCustom { DispatchQueue.main.async { self.applyLogo() } }
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

    /// Starts a session. With a `mode`, the mode's apps are what stays (opened if they aren't running) and
    /// everything else is parked — "keep open" ticks don't apply. `limit` scopes it for the self-tests.
    func park(quit: Bool, mode: [String: Any]? = nil, limit: Set<String>? = nil) {
        let keep: Set<String>? = mode.map { Set($0["apps"] as? [String] ?? []) }
        var out = keep.map { k in apps().filter { !k.contains($0.bundleIdentifier ?? "") } } ?? leaving()
        if let limit { out = out.filter { limit.contains($0.bundleIdentifier ?? "") } }
        if let keep {                                           // the mode's apps come up first, in the background
            for id in keep where !ws.runningApplications.contains(where: { $0.bundleIdentifier == id }) {
                guard let url = ws.urlForApplication(withBundleIdentifier: id) else { continue }
                let c = NSWorkspace.OpenConfiguration(); c.activates = false; ws.openApplication(at: url, configuration: c)
            }
        }
        guard !out.isEmpty else { return }
        generation += 1; let gen = generation
        modeKeep = keep
        let name = mode?["name"] as? String
        // Instant: the pill plays the moment the key goes down. The snapshot is grabbed in the background in the
        // same instant (the pill is still invisible then) and the quitting starts once it's on disk.
        pill.play(start: true, icons: out.compactMap { $0.bundleURL.map { ws.icon(forFile: $0.path) } }, target: iconPoint, label: name ?? "Focus")
        var record: Session = ["date": Date(), "apps": out.compactMap { a in a.bundleURL.map { ["path": $0.path, "hidden": a.isHidden, "pid": Int(a.processIdentifier)] as [String: Any] } }]
        // Started mid-restore: the apps that restore hadn't reached join this session, so End brings them back too.
        let have = Set(out.compactMap { $0.bundleURL?.path })
        let unreached = pendingRestore.filter { e in (e["path"] as? String).map { p in !have.contains(p) && !ws.runningApplications.contains { $0.bundleURL?.path == p } } ?? false }
        if !unreached.isEmpty { record["apps"] = (record["apps"] as? [[String: Any]] ?? []) + unreached }
        pendingRestore = []
        if let name { record["mode"] = name; record["name"] = name }
        sessions.insert(record, at: 0)
        focused = true
        let go = { [self] in
            guard generation == gen, focused else { return }     // ended (or restarted) before the snapshot finished
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
        let kept = modeKeep ?? Set(excluded)                     // a mode decides what stays; otherwise the ticks do
        if protected(a) || (!clearing && kept.contains(a.bundleIdentifier ?? "")) { queue.removeFirst(); return quitNext() }   // marked keep / critical since it began
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
        queue = []; status = nil; modeKeep = nil
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
            if out.isEmpty && !restart { a.addButton(withTitle: "OK"); _ = run(a); return }
            a.addButton(withTitle: restart ? "Quit All & Restart" : "Quit All"); a.addButton(withTitle: "Cancel")
            guard run(a) == .alertFirstButtonReturn else { return }
        }
        guard !out.isEmpty else { if restart { restartMac() }; return }
        sessions.insert(["date": Date(), "kind": "quit all",
                         "apps": out.compactMap { a in a.bundleURL.map { ["path": $0.path, "hidden": a.isHidden, "pid": Int(a.processIdentifier)] as [String: Any] } }], at: 0)
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
        _ = run(a)
    }
    /// Every dialog goes through here: a menu bar app is often refused activation, so it floats in front regardless.
    func run(_ a: NSAlert) -> NSApplication.ModalResponse {
        a.window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        return a.runModal()
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
            guard run(a) == .alertFirstButtonReturn else { return }
        }
        sessions.insert(["date": Date(), "kind": "force quit",
                         "apps": out.compactMap { a in a.bundleURL.map { ["path": $0.path, "hidden": a.isHidden, "pid": Int(a.processIdentifier)] as [String: Any] } }], at: 0)
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
        generation += 1
        queue = []; total = 0; status = nil; modeKeep = nil; waiting = []   // nothing from the ended session lingers
        focused = false
        pill.play(start: false, icons: (s["apps"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }.map { ws.icon(forFile: $0) },
                  target: iconPoint, label: "Back")
        relaunch(ArraySlice(s["apps"] as? [[String: Any]] ?? []), generation)
    }
    /// Past sessions ▸ Open all on an OLD session just opens its apps; the live session (if any) carries on.
    func openApps(_ s: Session) { relaunch(ArraySlice(s["apps"] as? [[String: Any]] ?? []), generation) }

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
    func relaunch(_ rest: ArraySlice<[String: Any]>, _ gen: Int) {
        guard gen == generation else { return }                 // a new session started: stop reopening into it
        guard let e = rest.first else { pendingRestore = []; return }
        pendingRestore = Array(rest.dropFirst())
        var launched = false
        // An app deleted or moved since it was parked (or on an ejected drive) is skipped quietly: asking macOS to
        // open a missing app puts up a "can't be found" dialog.
        if let path = e["path"] as? String, FileManager.default.fileExists(atPath: path) {
            let hidden = e["hidden"] as? Bool ?? false
            if let a = ws.runningApplications.first(where: { $0.bundleURL?.path == path }) {
                if !hidden { a.unhide() }
            } else {
                let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = false; cfg.hides = hidden
                // Tabs back even though Chrome's own setting is "New Tab page" — but nothing plays until you click:
                // a restored YouTube tab must not start blaring (user's rule).
                if Bundle(path: path)?.bundleIdentifier == chrome { cfg.arguments = ["--restore-last-session", "--autoplay-policy=user-gesture-required"] }
                ws.openApplication(at: URL(fileURLWithPath: path), configuration: cfg)
                launched = true
            }
        }
        // Space out real launches; an app that was already open costs no wait.
        DispatchQueue.main.asyncAfter(deadline: .now() + (launched ? 0.7 : 0.05)) { self.relaunch(rest.dropFirst(), gen) }
    }

    /// Session apps still open after their turn: usually a save prompt waiting for you.
    func stragglers() -> [NSRunningApplication] {
        guard focused, !hideMode else { return [] }
        let waiting = Set(queue.map(\.processIdentifier))
        let paths = Set((sessions.first?["apps"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String })
        return ws.runningApplications.filter { paths.contains($0.bundleURL?.path ?? "") && !$0.isHidden && !protected($0) && !waiting.contains($0.processIdentifier) }
    }
    /// Session apps running under a different process than the one Focus quit: something reopened them
    /// (a login item, a helper, an updater). Different from a save prompt, and worth a different line.
    func reopened() -> [NSRunningApplication] {
        guard focused, !hideMode else { return [] }
        let entries = sessions.first?["apps"] as? [[String: Any]] ?? []
        let quitPids = Set(entries.compactMap { $0["pid"] as? Int }), paths = Set(entries.compactMap { $0["path"] as? String })
        guard !quitPids.isEmpty else { return [] }
        let waiting = Set(queue.map(\.processIdentifier))
        // Hidden or not: a relaunched app is using memory either way.
        return ws.runningApplications.filter {
            paths.contains($0.bundleURL?.path ?? "") && !protected($0) && !waiting.contains($0.processIdentifier) && !quitPids.contains(Int($0.processIdentifier))
        }
    }
    @objc func quitAgain() { reopened().forEach { $0.terminate() } }

    func toggle() {
        item.menu?.cancelTracking()
        if clearing { NSSound.beep(); return }                  // Quit All (& Restart) in progress: never start a session inside it
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
    // MARK: modes and named sessions

    /// Modes: named sets of apps ("Writing" = a writing app + a browser). Starting one opens its apps and parks
    /// everything else; End Session restores. Nothing is built in — every mode is the user's own.
    var modes: [[String: Any]] {
        get { store.array(forKey: "modes") as? [[String: Any]] ?? [] }
        set { store.set(newValue, forKey: "modes") }
    }
    /// A one-line text prompt (kept in front: a menu bar app is often refused activation).
    func ask(_ title: String, _ text: String, _ value: String = "", placeholder: String = "") -> String? {
        let a = NSAlert(); a.messageText = title; a.informativeText = text
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = value; field.placeholderString = placeholder; a.accessoryView = field
        a.addButton(withTitle: "Save"); a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = field
        guard run(a) == .alertFirstButtonReturn else { return nil }
        let v = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }
    func names(_ ids: [String]) -> String { ids.compactMap(path).map(appName).joined(separator: ", ") }
    @objc func newMode() {
        let ids = excluded.filter { path($0) != nil }
        guard !ids.isEmpty else {
            return tell("Tick the apps for this mode first", "In the Focus menu, tick the apps you want in the mode — say, your writing app and your browser — then choose New Mode again.")
        }
        guard let name = ask("New Mode", "Starting this mode opens \(names(ids)) and parks everything else.", placeholder: "Writing") else { return }
        modes.append(["name": name, "apps": ids])
    }
    @objc func startMode(_ s: NSMenuItem) {
        guard !focused, !clearing, modes.indices.contains(s.tag) else { return }
        item.menu?.cancelTracking(); park(quit: !hideMode, mode: modes[s.tag])
    }
    @objc func renameMode(_ s: NSMenuItem) {
        guard modes.indices.contains(s.tag), let name = ask("Rename Mode", "", modes[s.tag]["name"] as? String ?? "") else { return }
        modes[s.tag]["name"] = name
    }
    @objc func updateMode(_ s: NSMenuItem) {
        let ids = excluded.filter { path($0) != nil }
        guard modes.indices.contains(s.tag), !ids.isEmpty else { return }
        modes[s.tag]["apps"] = ids
    }
    @objc func deleteMode(_ s: NSMenuItem) { if modes.indices.contains(s.tag) { modes.remove(at: s.tag) } }
    @objc func renameSession(_ s: NSMenuItem) {
        guard sessions.indices.contains(s.tag) else { return }
        let current = sessions[s.tag]["name"] as? String ?? ""
        guard let name = ask("Rename Session", "", current, placeholder: "Essay draft") else { return }
        sessions[s.tag]["name"] = name
    }
    @objc func sessionToMode(_ s: NSMenuItem) {
        guard sessions.indices.contains(s.tag) else { return }
        let ids = (sessions[s.tag]["apps"] as? [[String: Any]] ?? []).compactMap { ($0["path"] as? String).flatMap { Bundle(path: $0)?.bundleIdentifier } }
        guard !ids.isEmpty, let name = ask("Save as Mode", "Starting this mode opens \(names(ids)) and parks everything else.",
                                             sessions[s.tag]["name"] as? String ?? "") else { return }
        modes.append(["name": name, "apps": ids])
    }
    /// Up to three app icons, overlapped, for a mode's row.
    func stack(_ ids: [String]) -> NSImage {
        let icons = ids.prefix(3).compactMap(path).map { ws.icon(forFile: $0) }
        let img = NSImage(size: NSSize(width: 16 + CGFloat(max(icons.count - 1, 0)) * 7, height: 16), flipped: false) { _ in
            for (i, ic) in icons.enumerated().reversed() { ic.draw(in: NSRect(x: CGFloat(i) * 7, y: 0, width: 16, height: 16)) }
            return true
        }
        return img
    }

    /// The live session is sessions[0] while focused: opening it = End Session; it can't be deleted mid-session.
    func isLive(_ n: Int) -> Bool { focused && n == 0 }
    @objc func reopen(_ s: NSMenuItem) {
        guard sessions.indices.contains(s.tag) else { return }
        if isLive(s.tag) { open(sessions[0]) } else { openApps(sessions[s.tag]) }
    }
    @objc func forget(_ s: NSMenuItem) {
        guard sessions.indices.contains(s.tag), !isLive(s.tag) else { return }
        sessions.remove(at: s.tag)
    }
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

    /// macOS gives menus no background colour, only its translucent material. So every Focus menu is forced dark,
    /// and once its window exists an opaque off-black backing is slipped under the items.
    func menuWillOpen(_ m: NSMenu) {
        darken(m)
        DispatchQueue.main.async { self.paintMenuWindows() }
    }
    func darken(_ m: NSMenu) {
        m.appearance = NSAppearance(named: .darkAqua)
        for i in m.items { if let sub = i.submenu { sub.delegate = sub.delegate ?? self; darken(sub) } }
    }
    func paintMenuWindows() {
        for w in NSApp.windows where w.isVisible && NSStringFromClass(type(of: w)).contains("Menu") {
            guard let host = w.contentView, host.subviews.first(where: { $0.identifier?.rawValue == "focusBacking" }) == nil else { continue }
            let back = NSView(frame: host.bounds)
            back.identifier = NSUserInterfaceItemIdentifier("focusBacking")
            back.autoresizingMask = [.width, .height]
            back.wantsLayer = true
            back.layer?.backgroundColor = theme.menuBackground.cgColor
            back.layer?.cornerRadius = 10; back.layer?.cornerCurve = .continuous
            back.layer?.borderColor = theme.menuEdge.cgColor; back.layer?.borderWidth = 1
            host.addSubview(back, positioned: .below, relativeTo: nil)
        }
    }

    func menuNeedsUpdate(_ m: NSMenu) {
        // Submenus share this delegate only so they open dark (menuWillOpen). They build themselves; rebuilding one
        // here would fill it with a copy of the whole menu.
        guard m.supermenu == nil else { return }
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
        let back = reopened()
        if !left.isEmpty || !back.isEmpty {                     // shown only when something is still eating memory
            m.addItem(.separator())
            let stuck = left.filter { a in !back.contains(a) }
            if !back.isEmpty {
                add("Reopened by itself: " + back.compactMap(\.localizedName).joined(separator: ", ") + " — quit again",
                    #selector(quitAgain), image: symbol("arrow.triangle.2.circlepath"))
            }
            if !stuck.isEmpty {
                add("Still open — probably a save prompt: " + stuck.compactMap(\.localizedName).joined(separator: ", "),
                    #selector(look), image: symbol("exclamationmark.bubble"))
            }
        }

        m.addItem(.separator())
        if showColourTip {
            add("Make the icon yours — pick its colours…", #selector(colourTip), image: Focus.rainbow)
            m.addItem(.separator())
        }
        // Modes — the user's named sets of apps.
        header(modes.isEmpty ? "Modes — tick some apps, then save them as one" : "Modes")
        for (n, md) in modes.enumerated() {
            let ids = md["apps"] as? [String] ?? [], name = md["name"] as? String ?? "Mode"
            let row = add(name, nil, image: stack(ids)), sm = NSMenu()
            sm.autoenablesItems = false
            if #available(macOS 14, *) { sm.addItem(.sectionHeader(title: "Opens")) }
            for id in ids { if let p = path(id) { add(appName(p), nil, image: appIcon(p), to: sm) } }
            sm.addItem(.separator())
            let go = add("Start \(name)", #selector(startMode(_:)), image: symbol("play.circle"), to: sm)
            go.tag = n; go.isEnabled = !focused && !clearing
            add("Rename…", #selector(renameMode(_:)), image: symbol("pencil"), to: sm).tag = n
            let use = add("Use Ticked Apps", #selector(updateMode(_:)), image: symbol("checklist"), to: sm)
            use.tag = n; use.isEnabled = !excluded.isEmpty
            add("Delete", #selector(deleteMode(_:)), image: symbol("trash"), to: sm).tag = n
            row.submenu = sm
        }
        add("New Mode from Ticked Apps…", #selector(newMode), image: symbol("plus.circle"))
        m.addItem(.separator())

        if !sessions.isEmpty {
            let past = add("Past sessions", nil, image: symbol("clock.arrow.circlepath")), sub = NSMenu()
            for (n, s) in sessions.enumerated() {
                let list = s["apps"] as? [[String: Any]] ?? []
                let date = (s["date"] as? Date).map { when.string(from: $0) } ?? "?"
                let title = (s["name"] as? String).map { "\($0) · \(date)" } ?? "\(date) · \(apps(list.count))" + ((s["kind"] as? String).map { " · " + $0 } ?? "")
                let i = add(title + (isLive(n) ? " · now" : ""), nil, to: sub), one = NSMenu()
                one.autoenablesItems = false
                // Hovering a session opens this: its snapshot first, so you see where you were.
                if let shot = s["shot"] as? String, FileManager.default.fileExists(atPath: shot), let img = NSImage(contentsOfFile: shot) {
                    let w = menuWidth - 28, h = (w * img.size.height / max(img.size.width, 1)).rounded()
                    let v = NSMenuItem(); v.view = Thumb(img, NSSize(width: w, height: h)) { [unowned self] in self.ws.open(URL(fileURLWithPath: shot)) }
                    one.addItem(v); one.addItem(.separator())
                }
                for p in list.compactMap({ $0["path"] as? String }) { add(appName(p), nil, image: appIcon(p), to: one) }
                one.addItem(.separator())
                add(isLive(n) ? "End Session and Reopen" : "Open all", #selector(reopen), image: symbol("arrow.up.forward.app"), to: one).tag = n
                add("Rename…", #selector(renameSession(_:)), image: symbol("pencil"), to: one).tag = n
                add("Save as Mode…", #selector(sessionToMode(_:)), image: symbol("square.stack"), to: one).tag = n
                let del = add("Delete", #selector(forget), image: symbol("trash"), to: one)
                del.tag = n; del.isEnabled = !isLive(n)                 // deleting the live session would lose its restore
                i.submenu = one
            }
            past.submenu = sub
        }
        let tools = add("Tools", nil, image: symbol("wrench.and.screwdriver")), tm = NSMenu()
        tm.autoenablesItems = false
        let busy = focused || clearing
        add("Quit All Apps…", #selector(quitAllApps), image: symbol("xmark.circle"), to: tm).isEnabled = !busy
        add("Quit All Apps & Restart Mac…", #selector(quitAllRestart), image: symbol("arrow.clockwise.circle"), to: tm).isEnabled = !busy
        let fq = add("Force Quit All Apps…", #selector(forceQuitAllApps), image: symbol("bolt.circle", [theme.hazard]), to: tm)
        fq.isEnabled = !busy
        if !busy { fq.attributedTitle = NSAttributedString(string: fq.title, attributes: [.foregroundColor: theme.hazard, .font: NSFont.menuFont(ofSize: 0)]) }
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
        cm.addItem(.separator())
        let preview = logoImage(64); preview.size = NSSize(width: 28, height: 28)
        hdr("Customised Logo — the app's own icon")
        let lp = add(logoCustom ? "Your logo" : "Standard logo", nil, image: preview, to: cm); lp.isEnabled = false
        add("Standard", #selector(logoStandard), to: cm).state = logoCustom ? .off : .on
        add("Match Menu Bar Colours", #selector(logoMatch), image: two(ringColor, dotColor), to: cm)
        hdr("Logo Background")
        let lb = NSMenuItem(); lb.view = ColorGrid(grid, selected: logoBg) { [unowned self] h in self.logoBg = h }; cm.addItem(lb)
        hdr("Logo Mark")
        let lm = NSMenuItem(); lm.view = ColorGrid(grid, selected: logoMark) { [unowned self] h in self.logoMark = h }; cm.addItem(lm)
        colour.submenu = cm
        let keys = add("Shortcuts", nil, image: symbol("keyboard"), to: sub), km = NSMenu()
        km.autoenablesItems = false; km.minimumWidth = 300
        if #available(macOS 14, *) { km.addItem(.sectionHeader(title: "Start / End Session")) }
        for c in modifierChoices {
            let i = add(c.label + "F  ·  " + c.clash, #selector(pickSessionKey(_:)), to: km); i.tag = c.mods; i.state = c.mods == sessionMods ? .on : .off
        }
        if sessionKeyTaken { add("⚠︎ " + label(sessionMods) + "F is taken by another app — pick another", nil, to: km).isEnabled = false }
        km.addItem(.separator())
        if #available(macOS 14, *) { km.addItem(.sectionHeader(title: "Open This Menu")) }
        for c in modifierChoices {
            let i = add(c.label + "E", #selector(pickMenuKey(_:)), to: km); i.tag = c.mods; i.state = c.mods == menuMods ? .on : .off
        }
        if menuKeyTaken { add("⚠︎ " + label(menuMods) + "E is taken by another app — pick another", nil, to: km).isEnabled = false }
        keys.submenu = km
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
        add(label(menuMods) + "E opens this menu", nil, to: sub).isEnabled = false
        add("Focus " + ((Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"), nil, to: sub).isEnabled = false
        add("Quit Focus", #selector(bye), image: symbol("power"), to: sub)
        settings.submenu = sub

        m.addItem(.separator())
        let b = BigButton(
            title: { [unowned self] in self.focused ? "End Session" : "Start New Session" },
            caption: { [unowned self] in
                if self.focused {
                    let n = self.apps((self.sessions.first?["apps"] as? [Any])?.count ?? 0)
                    return self.queue.isEmpty ? "Ending the session will reopen \(n) exactly as they were."
                        : "Ending the session now stops the quitting and reopens \(n) as they were."
                }
                let out = self.leaving()
                if out.isEmpty { return "Every open app is kept, so there's nothing to \(self.hideMode ? "hide" : "quit")." }
                if self.hideMode { return "Starting a new session will hide \(self.apps(out.count)). Click again to bring them back." }
                let them = out.count == 1 ? "it" : "them"
                return "Starting a new session will save and quit \(self.apps(out.count)), freeing about \(gb(out.reduce(0) { $0 + self.memory($1) })) of RAM. Click again to reopen \(them)."
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

/// The app icon at `px` pixels: the menu bar mark at rest on the macOS icon grid (824-pt tile, 100-pt margin).
/// Standard: near-black gradient tile, white mark. A Customised Logo passes its own tile and mark colours.
func appIconRep(_ px: Int, bg: NSColor?, mark markColor: NSColor?) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let u = CGFloat(px) / 1024                                     // 1024-pt grid: 824-pt tile, 100-pt margin
        let tile = NSRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
        let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * u, yRadius: 185 * u)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.35); shadow.shadowBlurRadius = 20 * u
        shadow.shadowOffset = NSSize(width: 0, height: -8 * u); shadow.set()
        let top = bg.map { $0.blended(withFraction: 0.18, of: .white) ?? $0 } ?? NSColor(white: 0.16, alpha: 1)
        let bottom = bg.map { $0.blended(withFraction: 0.22, of: .black) ?? $0 } ?? NSColor(white: 0.05, alpha: 1)
        NSGradient(starting: top, ending: bottom)!.draw(in: shape, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        theme.hudEdge.setStroke(); shape.lineWidth = max(1, 3 * u); shape.stroke()
        let mark = painted(glyph(0), markColor ?? theme.hudInk, NSSize(width: 512, height: 512))!
        NSGraphicsContext.current!.cgContext.draw(mark, in: tile.insetBy(dx: 120 * u, dy: 120 * u))
        NSGraphicsContext.restoreGraphicsState()
        return rep
}

/// `Focus --make-icon DIR`: writes the app icon set (the menu bar mark at rest, white on the pill's near-black,
/// on the macOS icon grid) so the icon is always drawn by the same glyph() as the menu bar and the pill.
if let i = CommandLine.arguments.firstIndex(of: "--make-icon"), CommandLine.arguments.count > i + 1 {
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (px, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"), (256, "128x128@2x"),
                       (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
        let rep = appIconRep(px, bg: nil, mark: nil)
        try? rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("icon_\(name).png"))
    }
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)                             // no Dock icon, not in Cmd-Tab

// One Focus at a time: a second copy (double launch, login item + manual open…) quits at once.
// One Focus at a time. When copies see each other, the OLDEST survives (launch time, then process number) — a total
// order, so two copies launched at the same instant can't both quit (that left no Focus at all) or both stay.
func olderFocus() -> NSRunningApplication? {
    let me = NSRunningApplication.current, mine = (me.launchDate ?? Date(), me.processIdentifier)
    return NSRunningApplication.runningApplications(withBundleIdentifier: "com.labern.focus")
        .filter { $0 != me && !$0.isTerminated }
        .first { a in let d = a.launchDate ?? .distantPast; return d < mine.0 || (d == mine.0 && a.processIdentifier < mine.1) }
}
let others = olderFocus().map { [$0] } ?? []
if CommandLine.arguments.contains("--pill-demo") {          // watch the start and end shows without a session
    let p = SessionPill(), ws = NSWorkspace.shared
    let icons = ["com.google.Chrome", "md.obsidian", "com.apple.iWork.Keynote", "com.apple.Preview", "com.readdle.SparkDesktop", "com.openai.chat"]
        .compactMap { ws.urlForApplication(withBundleIdentifier: $0) }.map { ws.icon(forFile: $0.path) }
    // `--pill-demo X Y`: the menu bar icon's centre in top-left screen points (as Accessibility reports it).
    let a = CommandLine.arguments, i = a.firstIndex(of: "--pill-demo")!, s = (NSScreen.main ?? NSScreen.screens[0]).frame
    let x = a.count > i + 2 ? Double(a[i + 1]) ?? Double(s.maxX - 560) : Double(s.maxX - 560), y = a.count > i + 2 ? Double(a[i + 2]) ?? 12 : 12
    let target = NSPoint(x: x, y: Double(s.maxY) - y)
    p.play(start: true, icons: icons, target: target, label: "Focus")
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { p.play(start: false, icons: icons, target: target, label: "Back") }
    DispatchQueue.main.asyncAfter(deadline: .now() + 4.4) { exit(0) }
    app.run()
}
let testing = CommandLine.arguments.contains(where: { $0.hasPrefix("--selftest") })
if !others.isEmpty && !testing { print("Focus is already running (pid \(others[0].processIdentifier))"); exit(0) }
if !testing {                                                   // launched too close together to see each other yet
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if olderFocus() != nil { exit(0) } }
}

/// `Focus --selftest`: the real session path, on TextEdit only, with its own settings store. Aborts before
/// touching anything if the session would include any other app.
/// `Focus --selftest-stress`: the stress scenarios, one after another, on Focus's real code paths. Own settings
/// store; only TextEdit, Calculator and stand-in apps are ever touched (each scenario asserts its scope first).
/// `--selftest-crash-a` / `--selftest-crash-b`: start a session then die with SIGKILL; a fresh Focus must restore it.
if CommandLine.arguments.contains(where: { $0.hasPrefix("--selftest-stress") || $0.hasPrefix("--selftest-crash") }) {
    let suite = "com.labern.focus.selftest"
    let crashB = CommandLine.arguments.contains("--selftest-crash-b")
    if !crashB { UserDefaults.standard.removePersistentDomain(forName: suite) }
    let t = Focus(store: UserDefaults(suiteName: suite)!)
    t.snapshots = false
    let ws = NSWorkspace.shared, edit = "com.apple.TextEdit", calc = "com.apple.calculator", slow = "com.labern.focus.slowquit"
    let front = ws.frontmostApplication
    var results: [(String, Bool, String)] = []
    func say(_ s: String) { print("stress:", s); fflush(stdout) }
    func running(_ id: String) -> [NSRunningApplication] { ws.runningApplications.filter { $0.bundleIdentifier == id && !$0.isTerminated } }
    func scope(_ ids: Set<String>) -> Bool {
        t.excluded = t.apps().compactMap(\.bundleIdentifier).filter { !ids.contains($0) }
        return Set(t.leaving().compactMap(\.bundleIdentifier)) == ids
    }
    func waitUntil(_ secs: Double, _ cond: @escaping () -> Bool, _ done: @escaping (Bool) -> Void) {
        let end = Date().addingTimeInterval(secs)
        func poll() { if cond() { return done(true) }; if Date() > end { return done(false) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: poll) }
        poll()
    }
    func launch(_ id: String, _ done: @escaping () -> Void) {
        guard running(id).isEmpty, let url = ws.urlForApplication(withBundleIdentifier: id) else { return done() }
        let c = NSWorkspace.OpenConfiguration(); c.activates = false; c.hides = true
        ws.openApplication(at: url, configuration: c); waitUntil(10, { !running(id).isEmpty }) { _ in done() }
    }
    typealias Step = (String, (@escaping (Bool, String) -> Void) -> Void)
    var steps: [Step] = []

    if CommandLine.arguments.contains("--selftest-crash-a") {
        launch(edit) {
            guard scope([edit]) else { say("ABORT scope"); exit(1) }
            t.park(quit: true)
            waitUntil(10, { running(edit).isEmpty }) { gone in
                say("crash-a: session started, TextEdit quit: \(gone ? "✓" : "✗") — now dying with SIGKILL")
                kill(getpid(), SIGKILL)
            }
        }
        app.run()
    }
    if crashB {
        say("crash-b: fresh Focus sees the session it didn't start: in session = \(t.focused) \(t.focused ? "✓" : "✗")")
        t.toggle()
        waitUntil(10, { !running(edit).isEmpty }) { back in
            say("crash-b: End Session after the crash brings TextEdit back: \(back ? "✓" : "✗"), in session now = \(t.focused)")
            UserDefaults.standard.removePersistentDomain(forName: suite); exit(back && !t.focused ? 0 : 1)
        }
        app.run()
    }

    steps.append(("1. ⌘⇧F twice fast — End while the quit queue is still running", { done in
        launch(edit) { launch(calc) {
            guard scope([edit, calc]) else { return done(false, "scope") }
            t.park(quit: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                t.toggle()                                        // End, mid-queue
                waitUntil(12, { !t.focused && t.queue.isEmpty && !running(edit).isEmpty && !running(calc).isEmpty }) { ok in
                    done(ok, "in session \(t.focused), queue \(t.queue.count), TextEdit \(running(edit).count), Calculator \(running(calc).count)")
                }
            }
        } }
    }))
    steps.append(("3. a parked app was deleted before restore", { done in
        launch(calc) {
            for a in running(calc) { a.terminate() }
            waitUntil(8, { running(calc).isEmpty }) { _ in
                t.sessions = [["date": Date(), "apps": [["path": "/Applications/NoSuchApp-Focus-Test.app", "hidden": false],
                                                       ["path": ws.urlForApplication(withBundleIdentifier: calc)!.path, "hidden": false]]]]
                t.focused = true; t.toggle()
                waitUntil(10, { !running(calc).isEmpty }) { ok in done(ok && !t.focused, "missing app skipped, Calculator back: \(ok)") }
            }
        }
    }))
    steps.append(("4. corrupted / odd saved settings", { done in
        let d = UserDefaults(suiteName: suite)!
        d.set("not-an-array", forKey: "sessions"); d.set([1, 2, 3], forKey: "excluded"); d.set(["com.nobody.ghost"], forKey: "neverClose")
        d.set("ZZZZZZ", forKey: "iconColor"); d.set(true, forKey: "focused")
        let m = NSMenu(); t.menuNeedsUpdate(m)                    // must build without crashing
        t.toggle()                                                // End with no valid session: must not crash
        let ok = m.items.count > 5 && !t.focused
        d.removeObject(forKey: "iconColor"); d.set([String](), forKey: "neverClose"); d.set([[String: Any]](), forKey: "sessions")
        done(ok, "menu built with \(m.items.count) items; session state reset to \(t.focused)")
    }))
    let relaunch = "com.labern.focus.relauncher"
    steps.append(("5. an app that relaunches itself after quitting (login-item helper style)", { done in
        guard !running(relaunch).isEmpty else { return done(true, "skipped — Relauncher stand-in not running") }
        guard scope([relaunch]) else { return done(false, "scope") }
        let firstPid = running(relaunch).first?.processIdentifier
        t.park(quit: true)
        waitUntil(15, { t.queue.isEmpty && running(relaunch).first.map { $0.processIdentifier != firstPid } == true }) { cameBack in
            let label = t.reopened().map { $0.localizedName ?? "?" }
            t.toggle()                                            // End: it's already running, so no duplicate
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                let n = running(relaunch).count
                done(cameBack && label == ["Relauncher"] && n == 1 && !t.focused,
                     "relaunched itself: \(cameBack); listed as 'Reopened by itself': \(label); instances after End: \(n)")
            }
        }
    }))
    steps.append(("6. reopening a parked app mid-session, then End — no duplicate", { done in
        launch(edit) {
            guard scope([edit]) else { return done(false, "scope") }
            t.park(quit: true)
            waitUntil(10, { running(edit).isEmpty && t.queue.isEmpty }) { _ in
                launch(edit) {                                    // the user opens it again during the session
                    t.toggle()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        done(running(edit).count == 1 && !t.focused, "TextEdit instances after End: \(running(edit).count)")
                    }
                }
            }
        }
    }))
    steps.append(("7. Tools ▸ Quit All during a session is refused", { done in
        launch(edit) {
            guard scope([edit]) else { return done(false, "scope") }
            t.park(quit: true)
            waitUntil(10, { t.queue.isEmpty }) { _ in
                launch(calc) {
                    t.quitAll(restart: false, only: [calc], confirm: false)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        let ok = !running(calc).isEmpty && !t.clearing
                        t.toggle()
                        waitUntil(10, { !running(edit).isEmpty }) { _ in done(ok, "Calculator untouched: \(!running(calc).isEmpty)") }
                    }
                }
            }
        }
    }))
    steps.append(("8. hide mode instead of quit", { done in
        launch(edit) {
            guard scope([edit]) else { return done(false, "scope") }
            for a in running(edit) { a.unhide() }
            waitUntil(5, { running(edit).first?.isHidden == false }) { _ in   // visible before the session starts
            t.hideMode = true; t.park(quit: false)
            waitUntil(5, { running(edit).first?.isHidden == true }) { hid in
                t.toggle(); t.hideMode = false
                waitUntil(5, { running(edit).first?.isHidden == false }) { shown in done(hid && shown, "hidden \(hid), unhidden \(shown)") }
            }
            }
        }
    }))
    steps.append(("9. session history is capped at 12", { done in
        t.sessions = []
        for _ in 0..<15 { t.sessions.insert(["date": Date(), "apps": [[String: Any]]()], at: 0) }
        done(t.sessions.count == 12, "\(t.sessions.count) kept of 15")
    }))
    steps.append(("10. an app that's merely slow to quit (12 s) — waiting list, then clears itself", { done in
        guard !running(slow).isEmpty else { return done(false, "SlowQuit stand-in not running") }
        guard scope([slow]) else { return done(false, "scope") }
        t.park(quit: true)
        waitUntil(12, { t.queue.isEmpty && t.waiting.contains { $0.bundleIdentifier == slow } }) { listed in
            waitUntil(20, { running(slow).isEmpty && t.status == nil }) { cleared in
                t.toggle()
                done(listed && cleared, "on waiting list \(listed), status cleared after it quit \(cleared)")
            }
        }
    }))
    steps.append(("17. modes — start opens the mode's apps and parks the rest; End restores; rename shows in the menu", { done in
        for a in running(edit) { a.terminate() }
        waitUntil(8, { running(edit).isEmpty }) { _ in
            launch(calc) {
                t.modes = [["name": "Writing", "apps": [edit]]]
                t.park(quit: true, mode: t.modes[0], limit: [calc])      // scoped: only Calculator may be parked
                waitUntil(12, { !running(edit).isEmpty && running(calc).isEmpty && t.queue.isEmpty }) { started in
                    let named = t.sessions.first?["mode"] as? String == "Writing"
                    t.sessions[0]["name"] = "Essay draft"
                    let m = NSMenu(); t.menuNeedsUpdate(m)
                    let past = m.items.first { $0.title == "Past sessions" }?.submenu?.items.first?.title ?? ""
                    let modeRow = m.items.contains { $0.title == "Writing" }
                    t.toggle()
                    waitUntil(10, { !running(calc).isEmpty }) { back in
                        t.modes = []
                        done(started && named && back && past.hasPrefix("Essay draft") && modeRow,
                             "TextEdit opened + Calculator parked: \(started); recorded as mode: \(named); renamed row: '\(past)'; mode row in menu: \(modeRow); End restored: \(back)")
                    }
                }
            }
        }
    }))
    steps.append(("18. submenus keep their own items when they open (Settings must not become a copy of the menu)", { done in
        let m = NSMenu(); t.menuNeedsUpdate(m)
        var ok = true, notes: [String] = []
        for name in ["Settings", "Tools", "Past sessions"] {
            guard let sub = m.items.first(where: { $0.title == name })?.submenu else { continue }
            let before = sub.items.map(\.title)
            t.menuWillOpen(sub); t.menuNeedsUpdate(sub)          // what macOS does when the submenu opens
            let after = sub.items.map(\.title)
            if before != after || after.contains("Start New Session") { ok = false; notes.append("\(name) changed") }
        }
        done(ok, notes.isEmpty ? "Settings, Tools, Past sessions unchanged on open" : notes.joined(separator: ", "))
    }))
    steps.append(("19. ending a mode early leaves nothing behind (next session uses the ticks, no stale save-prompt note)", { done in
        launch(edit) { launch(calc) {
            t.park(quit: true, mode: ["name": "Test", "apps": [String]()], limit: [edit, calc])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                t.toggle()                                        // End, mid-queue
                let clean = t.modeKeep == nil && t.waiting.isEmpty && t.queue.isEmpty && t.status == nil
                waitUntil(12, { !running(edit).isEmpty && !running(calc).isEmpty }) { back in
                    done(clean && back, "mode list cleared: \(t.modeKeep == nil), waiting cleared: \(t.waiting.isEmpty), apps back: \(back)")
                }
            }
        } }
    }))
    steps.append(("20. ⌘⇧F during Quit All & Restart is ignored; restart only after the clear-out", { done in
        launch(calc) {
            var restarted = false
            t.restartMac = { restarted = true }
            t.quitAll(restart: true, only: [calc], confirm: false)
            t.toggle()                                            // ⌘⇧F mid clear-out
            let ignored = !t.focused
            waitUntil(15, { restarted }) { r in
                t.restartMac = {}
                launch(calc) { done(ignored && r && !t.focused, "⌘⇧F ignored: \(ignored); restart after clear-out: \(r); in session: \(t.focused)") }
            }
        }
    }))
    steps.append(("21. the live session can't be deleted; Open all on an old one doesn't end it", { done in
        launch(calc) {
            t.sessions = [["date": Date(), "apps": [[String: Any]]()]]  // an older session
            guard scope([calc]) else { return done(false, "scope") }
            t.park(quit: true)
            waitUntil(10, { t.queue.isEmpty && running(calc).isEmpty }) { _ in
                let m = NSMenu(); t.menuNeedsUpdate(m)
                let live = m.items.first { $0.title == "Past sessions" }?.submenu?.items.first?.submenu
                let delOff = live?.items.first { $0.title == "Delete" }?.isEnabled == false
                let before = t.sessions.count
                let fake = NSMenuItem(); fake.tag = 0; t.forget(fake)    // try to delete the live one anyway
                fake.tag = 1; t.reopen(fake)                           // Open all on the old one
                let stillLive = t.focused && t.sessions.count == before
                t.toggle()
                waitUntil(10, { !running(calc).isEmpty }) { back in
                    done(delOff && stillLive && back, "Delete disabled on live: \(delOff); live session survives delete + old Open all: \(stillLive); End restores: \(back)")
                }
            }
        }
    }))
    steps.append(("22. a new session started mid-restore doesn't get apps reopened into it", { done in
        launch(edit) { launch(calc) {
            guard scope([edit, calc]) else { return done(false, "scope") }
            t.park(quit: true)
            waitUntil(15, { t.queue.isEmpty && running(edit).isEmpty && running(calc).isEmpty }) { _ in
                t.toggle()                                        // End: restore begins
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    _ = scope([edit, calc])
                    t.park(quit: true, limit: [edit, calc])       // new session, mid-restore
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                        let clean = t.focused && running(edit).isEmpty && running(calc).isEmpty
                        t.toggle()
                        waitUntil(12, { !running(edit).isEmpty && !running(calc).isEmpty }) { back in
                            done(clean && back, "nothing reopened into the new session: \(clean); End restores both: \(back)")
                        }
                    }
                }
            }
        } }
    }))
    steps.append(("23. shortcuts: switching registers the new keys at once; the default is ⌘⇧F / ⌘⇧E", { done in
        let defaultOK = t.label(t.sessionMods) == "⌘⇧" && t.label(t.menuMods) == "⌘⇧"
        t.sessionMods = controlKey | shiftKey                  // ⌃⇧F (the real Focus keeps its own keys)
        let s1 = !t.sessionKeyTaken && sessionKey == "⌃⇧F" && t.keyRefs.count == 2
        let m = NSMenu(); t.menuNeedsUpdate(m)
        let keysMenu = m.items.first { $0.title == "Settings" }?.submenu?.items.first { $0.title == "Shortcuts" }?.submenu
        let ticked = keysMenu?.items.first { $0.state == .on }?.title.hasPrefix("⌃⇧F") == true
        t.releaseShortcuts()
        UserDefaults(suiteName: suite)!.removeObject(forKey: "sessionMods"); sessionKey = "⌘⇧F"
        done(defaultOK && s1 && ticked, "default ⌘⇧F/⌘⇧E: \(defaultOK); ⌃⇧F registered live: \(s1); ticked in the menu: \(ticked)")
    }))
    steps.append(("16. menu speed with every process on the Mac", { done in
        let t0 = Date(); for _ in 0..<5 { t.menuNeedsUpdate(NSMenu()) }
        let ms = Int(Date().timeIntervalSince(t0) * 1000 / 5)
        done(ms < 250, "\(ms) ms per menu open")
    }))

    if let only = CommandLine.arguments.first(where: { $0.hasPrefix("--only=") })?.dropFirst(7) {   // e.g. --only=5,8
        let keep = only.split(separator: ",").map { String($0) + "." }
        steps = steps.filter { st in keep.contains { st.0.hasPrefix($0) } }
    }
    func run(_ i: Int) {
        guard i < steps.count else {
            say("———"); for (n, ok, note) in results { say("\(ok ? "PASS" : "FAIL")  \(n) — \(note)") }
            for id in [calc, slow] { running(id).forEach { $0.terminate() } }
            front?.activate()
            UserDefaults.standard.removePersistentDomain(forName: suite)
            exit(results.allSatisfy { $0.1 } ? 0 : 1)
        }
        let (name, f) = steps[i]
        say("▶ \(name)")
        t.hideMode = false
        f { ok, note in results.append((name, ok, note)); say("  \(ok ? "PASS" : "FAIL") — \(note)"); DispatchQueue.main.asyncAfter(deadline: .now() + 1) { run(i + 1) } }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { run(0) }
    app.run()
}
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
focus.applyShortcuts()                                          // ⌘⇧F / ⌘⇧E by default; Settings ▸ Shortcuts changes them
app.run()
