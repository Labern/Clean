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
import UniformTypeIdentifiers

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
/// Mode shortcuts are a modifier + a digit (0–9), the digit chosen per mode by the user. The modifier is shared.
let modeModifierChoices: [KeyChoice] = [
    KeyChoice(label: "⌘", mods: cmdKey, clash: "while set, apps don't get it: browsers use ⌘1–9 for tabs"),
    KeyChoice(label: "⌃", mods: controlKey, clash: "Mission Control uses ⌃1–9 for Spaces if you turned that on"),
    KeyChoice(label: "⌃⌥", mods: controlKey | optionKey, clash: "free, except while VoiceOver is on"),
    KeyChoice(label: "⌃⌥⌘", mods: controlKey | optionKey | cmdKey, clash: "free — three keys, nothing else uses it"),
]
extension NSEvent.ModifierFlags {
    init(carbon m: Int) {
        var f: NSEvent.ModifierFlags = []
        if m & cmdKey != 0 { f.insert(.command) }; if m & shiftKey != 0 { f.insert(.shift) }
        if m & optionKey != 0 { f.insert(.option) }; if m & controlKey != 0 { f.insert(.control) }
        self = f
    }
}
let digitKeys = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
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
    var switcherPlateOrHover = NSColor.labelColor.withAlphaComponent(0.16)   // selected cell in the icon picker
    var hazard = NSColor.systemRed                                  // red only for the destructive action
    var menuBackground = hexColor("1F1F21")!                       // the menu: opaque off-black, always dark (as on the product page)
    var menuEdge = NSColor(white: 1, alpha: 0.12)
    var hover = NSColor.labelColor.withAlphaComponent(0.08)
    var text = NSColor.labelColor
    var faint = NSColor.secondaryLabelColor
    /// Every grey heading in the menu and its submenus: one size, one weight, one colour. Change these three to
    /// restyle them all at once.
    var headingSize: CGFloat = 11
    var headingWeight: NSFont.Weight = .semibold
    var heading = NSColor.tertiaryLabelColor
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
    /// Evangelion: each pair is (ring, dot) in the character's or Eva's own colours, lifted a touch so they read on
    /// a dark menu bar. Unit-01's armour purple and lime; Unit-02 red and Asuka's orange; Unit-00 blue and Rei's red
    /// eyes; Shinji's plugsuit blue and white; Misato's purple hair and red jacket; Kaworu's grey hair and red eyes;
    /// Pen Pen's slate-blue feathers and yellow beak.
    var evaPresets: [(String, String, String)] = [("UNIT 01", "7851A9", "8FD14F"), ("Asuka", "E3262F", "F28C28"),
                                                 ("Rei", "5B8DEF", "E8343C"), ("Shinji", "3E6FD6", "F1F3F6"),
                                                 ("Misato", "8A6CC0", "D7263D"), ("Kaworu", "D8D8DE", "D3203B"),
                                                 ("Pen Pen", "6F86B8", "F6C445")]
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

/// How long the app icons stay on screen in the session pop-up, before they're swept into the menu bar icon (start)
/// or drop into the pill (end). NORMAL IS THE ORIGINAL TIMING AND THE PERMANENT DEFAULT — recorded 2026-11-13:
///   start: icons hold 0.24 s after bursting out, then are swept away · end: icons hold 0.02 s after arriving, then drop.
///   Unchanged at every speed: pop-in 0.16 s, hit stop 0.10 s, burst 0.16 s, flight 0.34 s (+35 ms per icon), zip 0.22 s.
/// Slow and Fast only change the two holds. Never change Normal's values or make anything else the default.
enum AnimSpeed: Int, CaseIterable {
    case slow = -1, normal = 0, fast = 1
    var hold: (start: Double, end: Double) {
        switch self {
        case .normal: return (0.24, 0.02)                      // the original — do not change
        case .slow: return (1.2, 0.9)
        case .fast: return (0.08, 0.0)
        }
    }
    var name: String { ["Slow", "Normal", "Fast"][rawValue + 1] }
    var clockAngle: CGFloat { [150, 90, 30][rawValue + 1] }    // 10, 12 and 2 o'clock, in degrees from 3 o'clock
}

/// The speed control: a small clock face. The hand points straight up for Normal, back to 10 for Slow, on to 2 for
/// Fast — the clock wound slower or faster. Click a position (or its word) to set it; the menu stays open.
final class SpeedDial: NSView {
    var speed: AnimSpeed, pick: (AnimSpeed) -> Void, hover: AnimSpeed?
    let radius: CGFloat = 34
    var centre: NSPoint { NSPoint(x: bounds.midX, y: 22 + radius) }
    init(_ speed: AnimSpeed, pick: @escaping (AnimSpeed) -> Void) {
        self.speed = speed; self.pick = pick
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 2 * 34 + 52))
        autoresizingMask = [.width]
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { nil }
    func point(_ s: AnimSpeed, _ r: CGFloat) -> NSPoint {
        let a = s.clockAngle * .pi / 180; return NSPoint(x: centre.x + cos(a) * r, y: centre.y + sin(a) * r)
    }
    func hit(_ e: NSEvent) -> AnimSpeed? {
        let p = convert(e.locationInWindow, from: nil)
        return AnimSpeed.allCases.min { hypot(point($0, radius + 10).x - p.x, point($0, radius + 10).y - p.y) < hypot(point($1, radius + 10).x - p.x, point($1, radius + 10).y - p.y) }
            .flatMap { hypot(point($0, radius + 10).x - p.x, point($0, radius + 10).y - p.y) < 34 ? $0 : nil }
    }
    override func mouseMoved(with e: NSEvent) { let h = hit(e); if h != hover { hover = h; needsDisplay = true } }
    override func mouseExited(with e: NSEvent) { hover = nil; needsDisplay = true }
    override func mouseDown(with e: NSEvent) {}
    override func mouseUp(with e: NSEvent) { if let h = hit(e) { speed = h; pick(h); needsDisplay = true } }
    override func draw(_ r: NSRect) {
        let face = NSBezierPath(ovalIn: NSRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
        theme.hover.setFill(); face.fill()
        theme.dropped.setStroke(); face.lineWidth = 1; face.stroke()
        for s in AnimSpeed.allCases {                               // a tick at 10, 12 and 2
            let tick = NSBezierPath(); tick.move(to: point(s, radius - 7)); tick.line(to: point(s, radius - 2))
            tick.lineWidth = s == speed ? 2.4 : 1.4; tick.lineCapStyle = .round
            (s == speed ? theme.text : theme.faint).setStroke(); tick.stroke()
            let word = s.name as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: s == speed ? .semibold : .regular),
                                                        .foregroundColor: s == speed || s == hover ? theme.text : theme.faint]
            let size = word.size(withAttributes: attrs), at = point(s, radius + 14)
            let x = s == .slow ? at.x - size.width : s == .fast ? at.x : at.x - size.width / 2
            word.draw(at: NSPoint(x: x, y: s == .normal ? at.y - 2 : at.y - size.height / 2), withAttributes: attrs)
        }
        let hand = NSBezierPath(); hand.move(to: centre); hand.line(to: point(speed, radius - 10))
        hand.lineWidth = 2.4; hand.lineCapStyle = .round; theme.text.setStroke(); hand.stroke()
        theme.text.setFill(); NSBezierPath(ovalIn: NSRect(x: centre.x - 3, y: centre.y - 3, width: 6, height: 6)).fill()
    }
}

/// The menu bar mark: a viewfinder ring with a centre dot. `t` is linear progress, 0 (at rest: four open
/// brackets, gaps at the compass points, small dot) to 1 (focused: one closed ring, bigger dot). With `hunt`
/// the ring first pulls in and comes back out — a lens finding focus — then the gaps close in place and the
/// dot swells. Each phase has its own eased slice of the timeline. Template image: follows light / dark bars.
/// Menu bar icon designs (Settings ▸ Appearance ▸ Icon). Lens is the original and the default. Each one is drawn at
/// rest (t = 0) and focused (t = 1) and animates between them; the user's two colours apply to all of them —
/// `ring` = the frame / the many, `dot` = the one thing kept. No colours = white, like every menu bar icon.
enum IconStyle: String, CaseIterable {
    case lens, lessMore, narrowing, framed, gathered, switcher, fewer
    // Picked from the Icon Lab: minimal, Japanese, Mac windows, and ones that carry information
    case fullStop, aperture, reticle, zoom
    case ichi, enso, hinomaru, tomoe, stone
    case windows, spotlight, counter, door
    var name: String { ["Lens", "Less, more", "Narrowing", "Framed", "Gathered", "Switcher", "Fewer",
                        "Full stop", "Aperture", "Reticle", "Zoom",
                        "Ichi", "Ensō", "Hinomaru", "Tomoe", "Stone",
                        "Windows", "Spotlight", "Counter", "Door"][IconStyle.allCases.firstIndex(of: self)!] }
    var isCollection: Bool { IconStyle.allCases.firstIndex(of: self)! >= IconStyle.allCases.firstIndex(of: .fullStop)! }
}
var iconStyle: IconStyle = .lens                                  // set from Settings; read by every glyph() below

/// The ORIGINAL lens (thin ring, 1.6 pt) — kept exactly, because the app logo is drawn from it and he likes the logo.
func classicLens(_ t: CGFloat, hunt: Bool = false, ring ringColor: NSColor? = nil, dot dotColor: NSColor? = nil) -> NSImage {
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

func glyph(_ t: CGFloat, hunt: Bool = false, ring ringColor: NSColor? = nil, dot dotColor: NSColor? = nil, style: IconStyle? = nil) -> NSImage {
    let style = style ?? iconStyle
    if style != .lens { return styledGlyph(style, t, ring: ringColor, dot: dotColor) }
    func phase(_ a: CGFloat, _ b: CGFloat) -> CGFloat {          // 0…1 across [a, b], smoothstep-eased
        let x = min(max((t - a) / (b - a), 0), 1); return x * x * (3 - 2 * x)
    }
    // The menu bar lens — chunky, like the logo's mark. OFF: four thick brackets round a solid dot.
    // ON: the brackets close, then the disc floods solid with the dot knocked out — outline vs solid, obvious at a glance.
    let pull = hunt ? sin(.pi * phase(0, 0.55)) * 1.6 : 0
    let close = hunt ? phase(0.30, 0.70) : t                     // gaps close
    let flood = hunt ? phase(0.65, 0.95) : t                     // then the fill comes in
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
        let c = NSPoint(x: r.midX, y: r.midY), stroke: CGFloat = 2.6, radius = 7.6 - stroke / 2 - pull
        let gap = 30 * (1 - close)                                    // degrees; 0 = a closed ring
        let ring = NSBezierPath(); ring.lineWidth = stroke; ring.lineCapStyle = .butt
        if gap < 0.5 { ring.appendOval(in: NSRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)) }
        else { for k in 0..<4 {                                       // arcs centred on 45°, 135°… so gaps sit on the axes
            let mid = 45 + 90 * CGFloat(k)
            ring.move(to: NSPoint(x: c.x + radius * cos((mid - 45 + gap / 2) * .pi / 180), y: c.y + radius * sin((mid - 45 + gap / 2) * .pi / 180)))
            ring.appendArc(withCenter: c, radius: radius, startAngle: mid - 45 + gap / 2, endAngle: mid + 45 - gap / 2)
        } }
        (ringColor ?? .black).setStroke(); ring.stroke()
        if flood > 0 {                                                // the disc fills in
            (ringColor ?? .black).withAlphaComponent(flood).setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)).fill()
        }
        let dot = 2.3 + 0.5 * flood - (hunt ? pull * 0.3 : 0)
        let dotRect = NSRect(x: c.x - dot, y: c.y - dot, width: dot * 2, height: dot * 2)
        let knock = dotColor == nil || dotColor == ringColor          // dot same as the disc: knock it out so it shows
        if flood > 0.01 && knock {                                    // a see-through dot in the solid disc
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSColor.black.withAlphaComponent(flood).setFill(); NSBezierPath(ovalIn: dotRect).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            if flood < 1 { (NSColor.black.withAlphaComponent(1 - flood)).setFill(); NSBezierPath(ovalIn: dotRect).fill() }
        } else {
            (dotColor ?? ringColor ?? .black).setFill(); NSBezierPath(ovalIn: dotRect).fill()
        }
        return true
    }
    img.isTemplate = ringColor == nil && dotColor == nil
    return img
}
func glyph(focused: Bool) -> NSImage { glyph(focused ? 1 : 0) }

/// The five newer designs. Same 18 pt canvas and weights as the lens, so they sit in the menu bar the same way.
func styledGlyph(_ style: IconStyle, _ t0: CGFloat, ring ringColor: NSColor?, dot dotColor: NSColor?) -> NSImage {
    if style.isCollection { return collectionGlyph(style, t0, ring: ringColor, dot: dotColor) }
    let t = min(max(t0, 0), 1), e = t * t * (3 - 2 * t)                 // smoothstep
    let prim = ringColor ?? .black, sec = dotColor ?? ringColor ?? .black
    func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * e }
    func bar(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: NSColor) {
        guard w > 0.2 else { return }
        c.setFill(); NSBezierPath(roundedRect: NSRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h), xRadius: h / 2, yRadius: h / 2).fill()
    }
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
        switch style {
        case .lessMore:                                              // the long, crowded bar gives way to the short one
            bar(9, lerp(12.1, 9), lerp(14, 0), 3.4, prim.withAlphaComponent(0.4 * (1 - e)))
            bar(9, lerp(6.3, 9), lerp(6, 7.5), lerp(3.4, 4.2), sec)
        case .narrowing:                                             // three shortening bars collapse into one
            bar(9, lerp(13.1, 9), lerp(14, 3.6), 2.6, prim.withAlphaComponent(0.35 * (1 - e)))
            bar(9, lerp(9, 9), lerp(8.6, 3.6), 2.6, prim.withAlphaComponent(0.65 * (1 - e)))
            bar(9, lerp(4.9, 9), lerp(3.6, 8), lerp(2.6, 3.6), sec)
        case .framed:                                                // the brackets close in on the one that matters
            let k = lerp(5.2, 4.4), side = lerp(4, 4.6)                 // brackets stop just clear of the square
            sec.setFill(); NSBezierPath(roundedRect: NSRect(x: 9 - side / 2, y: 9 - side / 2, width: side, height: side), xRadius: 1, yRadius: 1).fill()
            let b = NSBezierPath(); let arm: CGFloat = 2
            for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)] as [(CGFloat, CGFloat)] {
                let x = 9 + sx * k, y = 9 + sy * k
                b.move(to: NSPoint(x: x, y: y - sy * arm)); b.line(to: NSPoint(x: x, y: y)); b.line(to: NSPoint(x: x - sx * arm, y: y))
            }
            b.lineWidth = 1.5; b.lineCapStyle = .round; b.lineJoinStyle = .round; prim.setStroke(); b.stroke()
        case .gathered:                                              // the corner apps are pulled in and vanish
            for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)] as [(CGFloat, CGFloat)] {
                let d = lerp(6.6, 2.5), sz = lerp(2.4, 0.8)
                prim.withAlphaComponent(0.4 * (1 - e)).setFill()
                NSBezierPath(roundedRect: NSRect(x: 9 + sx * d - sz / 2, y: 9 + sy * d - sz / 2, width: sz, height: sz), xRadius: 0.6, yRadius: 0.6).fill()
            }
            let ring = NSBezierPath(ovalIn: NSRect(x: 9 - 4.6, y: 9 - 4.6, width: 9.2, height: 9.2)); ring.lineWidth = 1.5
            prim.setStroke(); ring.stroke()
            let sq = lerp(3, 3.8)
            sec.setFill(); NSBezierPath(roundedRect: NSRect(x: 9 - sq / 2, y: 9 - sq / 2, width: sq, height: sq), xRadius: 0.9, yRadius: 0.9).fill()
        case .switcher:                                              // the ⌘⇥ bar shrinks down to the lens
            let w = lerp(15.2, 9.6), h = lerp(8, 9.6)                   // the bar becomes a ring the size of the lens
            let pill = NSBezierPath(roundedRect: NSRect(x: 9 - w / 2, y: 9 - h / 2, width: w, height: h), xRadius: h / 2, yRadius: h / 2)
            pill.lineWidth = 1.2; prim.withAlphaComponent(0.5 + 0.5 * e).setStroke(); pill.stroke()
            let dot = lerp(0.9, 2.2)
            sec.setFill(); NSBezierPath(ovalIn: NSRect(x: 9 - dot, y: 9 - dot, width: dot * 2, height: dot * 2)).fill()
        case .fewer:                                                 // a wide row of apps narrows to the two you keep
            let n = 5, size = lerp(2.6, 3.6), gapW: CGFloat = 0.8
            for i in 0..<n {
                let kept = i == 1 || i == 3                              // the pair that stays
                let restX = 9 + (CGFloat(i) - 2) * (2.6 + gapW)
                let focusX = 9 + (i == 1 ? -1 : 1) * (3.6 + 1.2) / 2
                let x = kept ? lerp(restX, focusX) : restX, a = kept ? 1 : 0.4 * (1 - e)
                let h = kept ? lerp(2.6, 3.6) : 2.6, w = kept ? size : 2.6
                guard a > 0.01 else { continue }
                (kept ? sec : prim.withAlphaComponent(a)).setFill()
                NSBezierPath(roundedRect: NSRect(x: x - w / 2, y: 9 - h / 2, width: w, height: h), xRadius: 0.8, yRadius: 0.8).fill()
            }
        default: break
        }
        return true
    }
    img.isTemplate = ringColor == nil && dotColor == nil
    return img
}

/// The icon collection from the Icon Lab: drawn on a flipped (y-down) 18-pt canvas, numbers taken straight from the
/// Lab so the app and the Lab match. Every design: out of session at t = 0, in session at t = 1, smoothstep between.
var openAppCount = 0                                              // Counter shows this; kept current by Focus
func collectionGlyph(_ style: IconStyle, _ t0: CGFloat, ring ringColor: NSColor?, dot dotColor: NSColor?) -> NSImage {
    let t = min(max(t0, 0), 1), e = t * t * (3 - 2 * t)
    let A = ringColor ?? .black, B = dotColor ?? ringColor ?? .black
    let twoColours = dotColor != nil && dotColor != ringColor
    func L(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * e }
    func P(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
        guard let ctx = NSGraphicsContext.current else { return false }
        func fill(_ p: NSBezierPath, _ c: NSColor, _ a: CGFloat = 1) {
            guard a > 0.01 else { return }; c.withAlphaComponent(c.alphaComponent * min(a, 1)).setFill(); p.fill()
        }
        func stroke(_ p: NSBezierPath, _ c: NSColor, _ w: CGFloat, _ a: CGFloat = 1) {
            guard a > 0.01 else { return }; p.lineWidth = w; c.withAlphaComponent(c.alphaComponent * min(a, 1)).setStroke(); p.stroke()
        }
        func knock(_ p: NSBezierPath, _ a: CGFloat = 1) {             // punch a see-through hole
            guard a > 0.01 else { return }
            ctx.compositingOperation = .destinationOut; NSColor.black.withAlphaComponent(min(a, 1)).setFill(); p.fill()
            ctx.compositingOperation = .sourceOver
        }
        func pill(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSBezierPath? {
            guard w > 0.15, h > 0.15 else { return nil }; let r = min(w, h) / 2
            return NSBezierPath(roundedRect: NSRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h), xRadius: r, yRadius: r)
        }
        func bar(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: NSColor, _ a: CGFloat = 1) { if let p = pill(cx, cy, w, h) { fill(p, c, a) } }
        func oval(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> NSBezierPath { NSBezierPath(ovalIn: NSRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)) }
        func dot(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ c: NSColor, _ a: CGFloat = 1) { if r > 0.05 { fill(oval(cx, cy, r, r), c, a) } }
        func ring(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ w: CGFloat, _ c: NSColor, _ a: CGFloat = 1) { stroke(oval(cx, cy, r, r), c, w, a) }
        func line(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ c: NSColor, _ w: CGFloat, _ a: CGFloat = 1) {
            let p = NSBezierPath(); p.move(to: P(x0, y0)); p.line(to: P(x1, y1)); p.lineCapStyle = .round; stroke(p, c, w, a)
        }
        func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r) }
        func brush(_ x0: CGFloat, _ x1: CGFloat, _ y: CGFloat, _ h: CGFloat, _ c: NSColor, _ a: CGFloat) {
            guard a > 0.01, x1 - x0 > 0.3 else { return }
            let m = x0 + (x1 - x0) * 0.5, p = NSBezierPath()
            p.move(to: P(x0, y - h * 0.42))
            p.curve(to: P(x1, y - h * 0.12), controlPoint1: P(m, y - h * 0.62), controlPoint2: P(x1 - 1.3, y - h * 0.56))
            p.curve(to: P(x1 - 1.6, y + h * 0.4), controlPoint1: P(x1 + 0.25, y + h * 0.34), controlPoint2: P(x1 - 0.8, y + h * 0.58))
            p.curve(to: P(x0, y + h * 0.42), controlPoint1: P(m, y + h * 0.28), controlPoint2: P(x0 + 0.6, y + h * 0.56))
            p.curve(to: P(x0, y - h * 0.42), controlPoint1: P(x0 - 0.47, y + h * 0.14), controlPoint2: P(x0 - 0.47, y - h * 0.14))
            p.close(); fill(p, c, a)
        }

        switch style {
        // — Minimal —
        case .fullStop:
            dot(L(3.4, 9), 9, L(1.7, 1), A, 0.55 * (1 - e)); dot(L(14.6, 9), 9, L(1.7, 1), A, 0.55 * (1 - e)); dot(9, 9, L(1.7, 3.4), B)
        case .aperture:
            fill(oval(9, 9, 7.8, 7.8), A)
            let hr = L(5.6, 1.9), rot = L(0, 60), hex = NSBezierPath()
            for k in 0..<6 { let a = (rot + 60 * CGFloat(k)) * .pi / 180; let p = P(9 + hr * cos(a), 9 + hr * sin(a)); k == 0 ? hex.move(to: p) : hex.line(to: p) }
            hex.close(); knock(hex)
            if twoColours { dot(9, 9, L(0, 1.3), B) }
        case .reticle:
            let r = L(7.9, 5)
            for (dx, dy) in [(0, -1), (1, 0), (0, 1), (-1, 0)] as [(CGFloat, CGFloat)] { line(9 + dx * r, 9 + dy * r, 9 + dx * (r - 2.4), 9 + dy * (r - 2.4), A, 2) }
            dot(9, 9, L(1.4, 2.5), B)
        case .zoom:
            for (w, a) in [(15, 0.35), (10.2, 0.6)] as [(CGFloat, CGFloat)] { let W = L(w, w + 5); stroke(rrect(9 - W / 2, 9 - W / 2, W, W, 1.6), A, 1.5, a * (1 - e)) }
            let w = L(5.4, 8), sq = rrect(9 - w / 2, 9 - w / 2, w, w, L(1, 1.8)); fill(sq, B, e); stroke(sq, B, 1.5)
        // — Japanese —
        case .ichi:
            brush(L(4.6, 6), L(13.4, 12), L(3.8, 9.4), L(2, 1.2), A, 0.5 * (1 - e))
            brush(L(5.4, 6), L(12.6, 12), L(8.6, 9.4), L(1.8, 1.2), A, 0.7 * (1 - e))
            brush(2, 16, L(14, 9.4), L(2.4, 3.2), B, 1)
        case .enso:
            let r: CGFloat = 6.3, gap = L(0.24, 0), p = NSBezierPath()
            if gap < 0.003 { p.appendOval(in: NSRect(x: 9 - r, y: 9 - r, width: r * 2, height: r * 2)) }
            else { p.appendArc(withCenter: P(9, 9), radius: r, startAngle: -62, endAngle: -62 + 360 * (1 - gap), clockwise: false) }
            p.lineCapStyle = .round; stroke(p, A, 2.4)
            let q = NSBezierPath(); q.appendArc(withCenter: P(9, 9), radius: r - 0.7, startAngle: -62, endAngle: -62 + 360 * 0.55 * (1 - gap * 0.6), clockwise: false)
            q.lineCapStyle = .round; stroke(q, A, 0.8, 0.45)
            dot(9, 9, L(0, 1.9), B)
        case .hinomaru:
            ring(9, 9, 6, 1.5, A, 1 - e)
            NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: NSRect(x: 0, y: L(15.5, 1.5), width: 18, height: 18)).addClip()
            dot(9, 9, L(6, 6.6), B); NSGraphicsContext.restoreGraphicsState()
        case .tomoe:
            let rot = e * 300
            for i in 0..<3 {
                let a = (rot + 120 * CGFloat(i)) * .pi / 180, R = L(4.5, 0), main = i == 0
                let x = 9 + R * cos(a), y = 9 + R * sin(a), tx = 9 + R * cos(a - 1.15) * 1.05, ty = 9 + R * sin(a - 1.15) * 1.05
                let q = P(9 + R * 1.3 * cos(a - 0.6), 9 + R * 1.3 * sin(a - 0.6))
                let tail = NSBezierPath(); tail.move(to: P(x, y))
                tail.curve(to: P(tx, ty), controlPoint1: P(x + (q.x - x) * 2 / 3, y + (q.y - y) * 2 / 3), controlPoint2: P(tx + (q.x - tx) * 2 / 3, ty + (q.y - ty) * 2 / 3))
                tail.lineCapStyle = .round
                if L(1.3, 0) > 0.05 { stroke(tail, main ? B : A, L(1.3, 0), main ? 1 : 1 - e) }
                dot(x, y, L(2.1, main ? 4.2 : 1), main ? B : A, main ? 1 : 1 - e)
            }
        case .stone:
            fill(oval(9, L(4.3, 9.6), 2.6, 1.7), A, 0.5 * (1 - e)); fill(oval(9, L(8.3, 9.6), 3.9, 2.1), A, 0.75 * (1 - e))
            fill(oval(9, L(13, 9.6), L(5.4, 4.4), L(2.7, 2.6)), B)
            stroke(oval(9, 9.6, L(5, 7.4), L(3, 4.6)), A, 0.8, 0.6 * e)
        // — Mac and wildcards —
        case .windows:
            for (x, y, a) in [(1.6, 2.4, 0.3), (3.6, 4.6, 0.55)] as [(CGFloat, CGFloat, CGFloat)] { fill(rrect(L(x, x - 3), L(y, y - 3), 10.4, 7.6, 1.4), A, a * (1 - e)) }
            let w = L(10.4, 14.4), h = L(7.6, 10.6), x = L(5.8, 9 - w / 2), y = L(7.4, 9 - h / 2)
            fill(rrect(x, y, w, h, 1.6), B)
            for i in 0..<3 { knock(oval(x + 1.4 + CGFloat(i) * 1.25, y + 1.3, 0.45, 0.45), 0.6) }
        case .spotlight:
            let cone = NSBezierPath(); cone.move(to: P(7.6, 0)); cone.line(to: P(10.4, 0)); cone.line(to: P(13, 13.6)); cone.line(to: P(5, 13.6)); cone.close()
            fill(cone, B, 0.28 * e)
            for i in -2...2 {
                let k = i == 0, hh = k ? L(2.6, 3.4) : 2.6
                fill(rrect(9 + CGFloat(i) * 3.4 - 1.3, k ? L(11.2, 10.6) : 11.2, 2.6, hh, 0.7), k ? B : A, k ? L(0.6, 1) : L(0.6, 0.15))
            }
            line(1, 15.4, 17, 15.4, A, 0.8, 0.5)
        case .counter:
            let box = rrect(1.8, 1.8, 14.4, 14.4, 4); stroke(box, A, 1.5, 1 - e); fill(box, B, e)
            let n = min(openAppCount, 99), s = "\(n)" as NSString
            let font = NSFont.systemFont(ofSize: s.length > 1 ? 9 : 11, weight: .heavy)
            let size = s.size(withAttributes: [.font: font])
            let r = NSRect(x: 9 - size.width / 2, y: 9 - size.height / 2 + 0.2, width: size.width, height: size.height)
            s.draw(in: r, withAttributes: [.font: font, .foregroundColor: A.withAlphaComponent(1 - e)])
            if e > 0.01 {                                         // in session the number is cut out of the solid tile
                ctx.cgContext.setBlendMode(.destinationOut)
                s.draw(in: r, withAttributes: [.font: font, .foregroundColor: NSColor.black.withAlphaComponent(e)])
                ctx.cgContext.setBlendMode(.normal)
            }
        case .door:
            stroke(rrect(4.3, 1.8, 9.4, 14.4, 1), A, 1.5)
            let w = L(4.2, 9.4), leaf = NSBezierPath()
            leaf.move(to: P(4.3, 1.8)); leaf.line(to: P(4.3 + w, L(3.4, 1.8))); leaf.line(to: P(4.3 + w, L(14.6, 16.2))); leaf.line(to: P(4.3, 16.2)); leaf.close()
            fill(leaf, B, L(0.55, 1)); knock(oval(L(7.2, 11.4), 9, 0.85, 0.85), 0.8 * e)
        default: break
        }
        return true
    }
    img.isTemplate = ringColor == nil && dotColor == nil
    return img
}

/// The icon picker in Settings ▸ Appearance: every design side by side, in the user's colours; click to choose.
final class IconGrid: NSView {
    var selected: IconStyle, hover: IconStyle?, ring: NSColor?, dot: NSColor?, pick: (IconStyle) -> Void
    static let cols = 5, cellH: CGFloat = 56
    init(_ selected: IconStyle, ring: NSColor?, dot: NSColor?, pick: @escaping (IconStyle) -> Void) {
        self.selected = selected; self.ring = ring; self.dot = dot; self.pick = pick
        let rows = (IconStyle.allCases.count + Self.cols - 1) / Self.cols
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: CGFloat(rows) * Self.cellH + 12))
        autoresizingMask = [.width]
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { nil }
    func cell(_ i: Int) -> NSRect {
        let w = (bounds.width - 24) / CGFloat(Self.cols), row = i / Self.cols, col = i % Self.cols
        return NSRect(x: 12 + CGFloat(col) * w, y: bounds.height - 6 - CGFloat(row + 1) * Self.cellH, width: w, height: Self.cellH)
    }
    func hit(_ e: NSEvent) -> IconStyle? {
        let p = convert(e.locationInWindow, from: nil)
        return IconStyle.allCases.indices.first { cell($0).contains(p) }.map { IconStyle.allCases[$0] }
    }
    // Hovering a design plays it: out of session → in session (with the hit stop) → back, on a loop, so you see
    // exactly what it will do in the menu bar before choosing it.
    var anim: Timer?, animStart = Date()
    func setHover(_ h: IconStyle?) {
        guard h != hover else { return }
        hover = h; anim?.invalidate(); anim = nil; needsDisplay = true
        guard h != nil else { return }
        animStart = Date()
        let tm = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self, let hv = self.hover, let i = IconStyle.allCases.firstIndex(of: hv) else { return }
            self.setNeedsDisplay(self.cell(i))
        }
        RunLoop.main.add(tm, forMode: .common)                    // menus track in their own run loop mode
        anim = tm
    }
    /// One loop: rest 0.45 s · in 0.45 s · hit stop · hold 0.8 s · out 0.45 s · rest. Returns (t, scale).
    func hoverPhase() -> (CGFloat, CGFloat) {
        let p = CGFloat(Date().timeIntervalSince(animStart).truncatingRemainder(dividingBy: 2.7))
        switch p {
        case ..<0.45: return (0, 1)
        case ..<0.9:  return ((p - 0.45) / 0.45, 1)
        case ..<1.0:  return (1, 1 + 0.12 * sin((p - 0.9) / 0.1 * .pi))
        case ..<1.8:  return (1, 1)
        case ..<2.25: return (1 - (p - 1.8) / 0.45, 1)
        default:      return (0, 1)
        }
    }
    override func viewDidMoveToWindow() { if window == nil { anim?.invalidate(); anim = nil; hover = nil } }
    override func mouseMoved(with e: NSEvent) { setHover(hit(e)) }
    override func mouseExited(with e: NSEvent) { setHover(nil) }
    override func mouseDown(with e: NSEvent) {}
    override func mouseUp(with e: NSEvent) { if let h = hit(e) { selected = h; pick(h); needsDisplay = true } }
    override func draw(_ r: NSRect) {
        for (i, st) in IconStyle.allCases.enumerated() {
            let c = cell(i)
            if st == selected || st == hover {
                (st == selected ? theme.switcherPlateOrHover : theme.hover).setFill()
                NSBezierPath(roundedRect: c.insetBy(dx: 4, dy: 3), xRadius: 8, yRadius: 8).fill()
            }
            // At rest, as it sits in the menu bar; white when no colours are chosen (the menu is always dark).
            let (t, k) = st == hover ? hoverPhase() : (0, 1)
            let g = glyph(t, ring: ring ?? .white, dot: dot ?? ring ?? .white, style: st), side = 26 * k
            g.draw(in: NSRect(x: c.midX - side / 2, y: c.maxY - 20 - side / 2, width: side, height: side))
            let name = st.name as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: st == selected ? .semibold : .regular),
                                                        .foregroundColor: st == selected ? theme.text : theme.faint]
            name.draw(at: NSPoint(x: c.midX - name.size(withAttributes: attrs).width / 2, y: c.minY + 4), withAttributes: attrs)
        }
    }
}

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
    /// What a click adds the app to or takes it out of ("your session", "this mode"); nil = no hover popup.
    let target: String?
    var inert = false                                           // shown, not clickable: no hover, no click
    var on: Bool
    init(_ name: String, _ icon: NSImage, detail: String = "", on: Bool, onMark: String = "checkmark.circle.fill",
         target: String? = nil, flip: @escaping () -> Bool) {
        self.name = name; self.icon = icon; self.detail = detail; self.on = on; self.onMark = onMark; self.target = target; self.flip = flip
        super.init(height: 26)
    }
    required init?(coder: NSCoder) { nil }
    /// After a steady hover, a small popup says exactly what a click will do.
    static let tipDelay: TimeInterval = 2.5
    var tipTimer: Timer?
    var tipText: String? { target.map { on ? "Click to remove \(name) from \($0)." : "Click to add \(name) to \($0)." } }
    override func mouseEntered(with e: NSEvent) {
        super.mouseEntered(with: e)
        tipTimer?.invalidate()
        guard target != nil else { return }
        let t = Timer(timeInterval: Self.tipDelay, repeats: false) { [weak self] _ in self?.showTip() }
        RunLoop.main.add(t, forMode: .common); tipTimer = t           // menus track in their own run loop mode
    }
    override func mouseExited(with e: NSEvent) { super.mouseExited(with: e); tipTimer?.invalidate(); RowTip.shared.hide() }
    override func viewDidMoveToWindow() { if window == nil { tipTimer?.invalidate(); RowTip.shared.hide() } }
    func showTip() {
        guard hover, let text = tipText, let w = window else { return }
        let r = w.convertToScreen(convert(bounds, to: nil))
        RowTip.shared.show(text, under: r)
    }
    override func mouseUp(with e: NSEvent) { guard !inert else { return }; on = flip(); needsDisplay = true; tipTimer?.invalidate(); RowTip.shared.hide() }
    override func draw(_ r: NSRect) {
        if hover && !inert { theme.hover.setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 5, yRadius: 5).fill() }
        icon.draw(in: NSRect(x: 14, y: 5, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: on ? 1 : 0.55)
        (name as NSString).draw(at: NSPoint(x: 38, y: 4.5), withAttributes: [.font: NSFont.menuFont(ofSize: 13), .foregroundColor: on ? theme.text : theme.faint])
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: theme.faint]
        let d = detail as NSString
        d.draw(at: NSPoint(x: bounds.width - 42 - d.size(withAttributes: small).width, y: 6), withAttributes: small)
        // Hovering says what a click will do: × takes it out, + puts it in.
        let mark = hover && target != nil ? (on ? symbol("xmark.circle.fill", [theme.onAccent, theme.accent]) : symbol("plus.circle", [theme.text]))
                         : on ? symbol(onMark, [theme.onAccent, theme.accent]) : symbol("circle", [theme.dropped])
        mark?.draw(in: NSRect(x: bounds.width - 32, y: 5, width: 16, height: 16))
    }
}

/// A name typed straight into the menu: no popup. Return saves (and closes the menu); Escape closes it unchanged.
final class InlineNameField: NSView {
    let field = NSTextField(), commit: (String) -> Void
    init(_ value: String, placeholder: String, symbolName: String, enabled: Bool = true, commit: @escaping (String) -> Void) {
        self.commit = commit
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 34))
        autoresizingMask = [.width]
        let icon = NSImageView(image: symbol(symbolName, [theme.faint]) ?? NSImage())
        icon.frame = NSRect(x: 14, y: 9, width: 16, height: 16); addSubview(icon)
        field.stringValue = value; field.placeholderString = placeholder
        field.font = .menuFont(ofSize: 13); field.isBordered = true; field.bezelStyle = .roundedBezel
        field.focusRingType = .exterior; field.isEnabled = enabled
        field.frame = NSRect(x: 36, y: 5, width: menuWidth - 50, height: 24); field.autoresizingMask = [.width]
        field.target = self; field.action = #selector(done)
        (field.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = false     // only Return saves
        addSubview(field)
    }
    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    @objc func done() {
        let v = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        commit(v); enclosingMenuItem?.menu?.cancelTracking()
    }
}

/// A heading in the menu, drawn by Focus so its size and colour come from the theme (macOS's own section headers
/// are a fixed small grey).
final class Heading: NSView {
    let text: String
    static var attrs: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: theme.headingSize, weight: theme.headingWeight), .foregroundColor: theme.heading]
    }
    init(_ text: String) {
        self.text = text
        let w = ceil((text as NSString).size(withAttributes: Self.attrs).width) + 28
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: theme.headingSize + 13))
        autoresizingMask = [.width]
    }
    required init?(coder: NSCoder) { nil }
    override func draw(_ r: NSRect) { (text as NSString).draw(at: NSPoint(x: 14, y: 4), withAttributes: Self.attrs) }
}
func headingItem(_ t: String) -> NSMenuItem {
    if #available(macOS 14, *) { return .sectionHeader(title: t) }             // macOS's own heading, exactly as before
    let i = NSMenuItem(title: t, action: nil, keyEquivalent: ""); i.isEnabled = false; return i
}

/// The column titles over the app list: App over the names, Usage over the memory, and the Focus mark (as it
/// looks in a session) exactly over the ticks — ticked means in the session.
final class ColumnHeader: NSView {
    var onUsage: (() -> Void)?                                  // clicking "Usage" cycles how the list is ordered
    override func mouseDown(with e: NSEvent) {}
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func mouseUp(with e: NSEvent) { if convert(e.locationInWindow, from: nil).x > bounds.width - 110 { onUsage?() } }
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: theme.headingSize + 11)); autoresizingMask = [.width]
        toolTip = "Ticked apps are in the session. Click an app to put it in or take it out."
    }
    required init?(coder: NSCoder) { nil }
    override func draw(_ r: NSRect) {
        let a = Heading.attrs
        ("Apps in Session" as NSString).draw(at: NSPoint(x: 14, y: 4), withAttributes: a)
        let u = "Usage" as NSString
        u.draw(at: NSPoint(x: bounds.width - 42 - u.size(withAttributes: a).width, y: 4), withAttributes: a)   // over the memory
    }
}

/// One mode: click to start it (or move the session to it; the live one ends). Right-click or ⌃-click to edit it.
/// Its shortcut sits in the same column as the apps' memory; the live mode is ticked.
final class ModeRow: HoverView {
    let name: String, icon: NSImage, key: String, live: Bool, enabled: Bool, start: () -> Void, edit: () -> NSMenu
    init(_ name: String, _ icon: NSImage, key: String, live: Bool, enabled: Bool, start: @escaping () -> Void, edit: @escaping () -> NSMenu) {
        self.name = name; self.icon = icon; self.key = key; self.live = live; self.enabled = enabled; self.start = start; self.edit = edit
        super.init(height: 26)
        toolTip = "Click to start. Right-click to edit."
    }
    required init?(coder: NSCoder) { nil }
    override func mouseUp(with e: NSEvent) {
        if e.modifierFlags.contains(.control) || e.type == .rightMouseUp { return showEdit() }
        guard enabled else { return }
        enclosingMenuItem?.menu?.cancelTracking(); DispatchQueue.main.async(execute: start)
    }
    // Right-click (either half of it, whichever the menu delivers), a two-finger click, or ⌃-click.
    override func rightMouseDown(with e: NSEvent) { NSLog("Focus: mode row right mouse down"); showEdit() }
    override func rightMouseUp(with e: NSEvent) { NSLog("Focus: mode row right mouse up"); showEdit() }
    override func otherMouseDown(with e: NSEvent) { showEdit() }
    override func menu(for e: NSEvent) -> NSMenu? { NSLog("Focus: mode row asked for its menu"); showEdit(); return nil }
    var shown = false
    /// The open menu is closed first, then the mode's edit menu opens where the pointer is: a menu opened from
    /// inside another menu's row doesn't reliably appear.
    func showEdit() {
        guard !shown else { return }; shown = true
        let menu = edit(), at = NSEvent.mouseLocation
        enclosingMenuItem?.menu?.cancelTracking()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NSLog("Focus: opening a mode's edit menu")
            NSApp.activate(ignoringOtherApps: true)
            menu.popUp(positioning: nil, at: at, in: nil)
        }
    }
    override func draw(_ r: NSRect) {
        if hover { theme.hover.setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 5, yRadius: 5).fill() }
        icon.draw(in: NSRect(x: 14, y: 5, width: icon.size.width, height: 16), from: .zero, operation: .sourceOver, fraction: enabled ? 1 : 0.5)
        (name as NSString).draw(at: NSPoint(x: 58, y: 4.5),            // one fixed place: clear of three icons, whatever the mode holds
                                withAttributes: [.font: NSFont.menuFont(ofSize: 13), .foregroundColor: enabled ? theme.text : theme.faint])
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 13), .foregroundColor: theme.faint]
        let k = key as NSString
        k.draw(at: NSPoint(x: bounds.width - 42 - k.size(withAttributes: small).width, y: 4.5), withAttributes: small)
        let mark = live ? symbol(hover ? "stop.circle.fill" : "checkmark.circle.fill", [theme.onAccent, theme.accent])
                        : hover && enabled ? symbol("play.circle", [theme.text]) : nil
        mark?.draw(in: NSRect(x: bounds.width - 32, y: 5, width: 16, height: 16))
    }
}

/// The first row of the menu: a plain "Quit" at the top right, so leaving Focus is never hidden in Settings.
final class QuitRow: NSView {
    let action: () -> Void
    var hover = false { didSet { needsDisplay = true } }
    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 38)); autoresizingMask = [.width]
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { nil }
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 13)]
    var spot: NSRect { let w = ("Quit" as NSString).size(withAttributes: attrs).width; return NSRect(x: bounds.width - w - 26, y: 9, width: w + 16, height: 20) }
    override func mouseMoved(with e: NSEvent) { hover = spot.contains(convert(e.locationInWindow, from: nil)) }
    override func mouseExited(with e: NSEvent) { hover = false }
    override func mouseDown(with e: NSEvent) {}
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func mouseUp(with e: NSEvent) {
        guard spot.contains(convert(e.locationInWindow, from: nil)) else { return }
        enclosingMenuItem?.menu?.cancelTracking(); DispatchQueue.main.async(execute: action)
    }
    override func draw(_ r: NSRect) {
        if hover { theme.hover.setFill(); NSBezierPath(roundedRect: spot, xRadius: 5, yRadius: 5).fill() }
        var a = attrs; a[.foregroundColor] = hover ? theme.text : theme.faint
        ("Quit" as NSString).draw(at: NSPoint(x: spot.minX + 8, y: 11), withAttributes: a)
        ("Focus" as NSString).draw(at: NSPoint(x: 14, y: 6), withAttributes: [.font: NSFont.systemFont(ofSize: 21, weight: .bold), .foregroundColor: theme.text])   // the app's name, big, top left
    }
}

/// The last line of the menu: a help link on the left, the maker's mark (★★★★★ × PARADOX™) small at the right.
final class Maker: NSView {
    static let text = "★★★★★ × PARADOX™"
    static let help = "Help / Suggest Improvement"
    /// Where the help link goes. For now a new email; later the website's own help form replaces it.
    /// One help address for every PARADOX app; the subject starts with the app's name and the person writes the rest.
    static let helpURL = URL(string: "mailto:help@paradoxica.co.uk?subject=Focus%3A%20")!
    var open: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var hover = false { didSet { needsDisplay = true } }
    let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: theme.faint]
    var spot: NSRect { NSRect(x: 8, y: 2, width: (Self.help as NSString).size(withAttributes: small).width + 28, height: 16) }
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 20)); autoresizingMask = [.width]
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { nil }
    override func mouseMoved(with e: NSEvent) { hover = spot.contains(convert(e.locationInWindow, from: nil)) }
    override func mouseExited(with e: NSEvent) { hover = false }
    override func mouseDown(with e: NSEvent) {}
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func mouseUp(with e: NSEvent) {
        guard spot.contains(convert(e.locationInWindow, from: nil)) else { return }
        enclosingMenuItem?.menu?.cancelTracking(); open(Self.helpURL)
    }
    override func draw(_ r: NSRect) {
        var a = small; if hover { a[.foregroundColor] = theme.text }
        symbol("questionmark.circle", [hover ? theme.text : theme.faint])?.draw(in: NSRect(x: 14, y: 5, width: 11, height: 11))
        (Self.help as NSString).draw(at: NSPoint(x: 29, y: 5), withAttributes: a)
        let t = Self.text as NSString, w = t.size(withAttributes: small).width
        t.draw(at: NSPoint(x: bounds.width - w - 14, y: 5), withAttributes: small)      // small, bottom right
    }
}

/// Verbose headings: a short paragraph under a heading saying what the section does. Wraps to the menu's width.
final class Explain: NSView {
    let text: String
    static let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: theme.faint]
    init(_ text: String) {
        self.text = text
        let h = (text as NSString).boundingRect(with: NSSize(width: menuWidth - 28, height: 400), options: [.usesLineFragmentOrigin], attributes: Self.attrs).height
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: ceil(h) + 8)); autoresizingMask = [.width]
    }
    required init?(coder: NSCoder) { nil }
    override func draw(_ r: NSRect) {
        (text as NSString).draw(with: NSRect(x: 14, y: 4, width: bounds.width - 28, height: bounds.height - 6), options: [.usesLineFragmentOrigin], attributes: Self.attrs)
    }
}

/// The hover popup for app rows: one line, dark, just under the row it explains.
final class RowTip {
    static let shared = RowTip()
    var panel: NSPanel?
    func show(_ text: String, under row: NSRect) {
        hide()
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let size = (text as NSString).size(withAttributes: [.font: font])
        let w = ceil(size.width) + 22, h: CGFloat = 26
        let p = NSPanel(contentRect: NSRect(x: row.minX + 38, y: row.minY - h - 4, width: w, height: h),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.ignoresMouseEvents = true
        p.level = .popUpMenu + 1; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let v = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h)); v.wantsLayer = true
        v.layer?.backgroundColor = theme.hudBg.cgColor; v.layer?.cornerRadius = 7
        v.layer?.borderColor = theme.hudEdge.cgColor; v.layer?.borderWidth = 1
        let l = NSTextField(labelWithString: text); l.font = font; l.textColor = theme.hudInk
        l.frame = NSRect(x: 11, y: (h - ceil(size.height)) / 2, width: ceil(size.width) + 2, height: ceil(size.height))
        v.addSubview(l); p.contentView = v; p.orderFrontRegardless(); panel = p
    }
    func hide() { panel?.orderOut(nil); panel = nil }
}

/// The big button at the bottom: the one action, its key, and a live caption of what it will do.
final class BigButton: HoverView {
    let title: () -> String, caption: () -> String, action: () -> Void
    var down = false { didSet { needsDisplay = true } }
    init(title: @escaping () -> String, caption: @escaping () -> String, action: @escaping () -> Void) {
        self.title = title; self.caption = caption; self.action = action
        super.init(height: 121)
    }
    required init?(coder: NSCoder) { nil }
    override func mouseDown(with e: NSEvent) { down = true }
    override func mouseUp(with e: NSEvent) {
        down = false
        enclosingMenuItem?.menu?.cancelTracking()
        DispatchQueue.main.async(execute: action)
    }
    override func draw(_ r: NSRect) {
        let pill = NSRect(x: 12, y: bounds.height - 56, width: bounds.width - 24, height: 48)
        (down ? theme.accent.withAlphaComponent(0.7) : hover ? theme.accent.withAlphaComponent(0.88) : theme.accent).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 11, yRadius: 11).fill()
        let big: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: theme.onAccent]
        (title() as NSString).draw(at: NSPoint(x: pill.minX + 14, y: pill.midY - 9), withAttributes: big)
        let key: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: theme.onAccent.withAlphaComponent(0.6)]
        let k = sessionKey as NSString
        k.draw(at: NSPoint(x: pill.maxX - 14 - k.size(withAttributes: key).width, y: pill.midY - 8.5), withAttributes: key)
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: theme.faint]
        let c = caption() as NSString
        let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineBreakMode = .byWordWrapping
        var wrapped = small; wrapped[.paragraphStyle] = para
        c.draw(with: NSRect(x: 18, y: 6, width: bounds.width - 36, height: pill.minY - 15),
               options: [.usesLineFragmentOrigin], attributes: wrapped)     // plain English, wraps to two lines
    }
}

/// The live session, named at the top of the menu: what you're doing (the mode or the name you gave it), in bold,
/// and a quiet line under it — kind, start time, the apps kept open.
final class SessionBanner: NSView {
    let title: String, detail: String
    init(title: String, detail: String) {
        self.title = title; self.detail = detail
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 52))
        autoresizingMask = [.width]
    }
    required init?(coder: NSCoder) { nil }
    override func draw(_ r: NSRect) {
        let big: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: theme.text]
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: theme.faint]
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
        var b = big; b[.paragraphStyle] = para; var sm = small; sm[.paragraphStyle] = para
        (title as NSString).draw(with: NSRect(x: 14, y: 22, width: bounds.width - 28, height: 22), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: b)
        (detail as NSString).draw(with: NSRect(x: 14, y: 6, width: bounds.width - 28, height: 15), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: sm)
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

    /// `incoming`: apps coming back during a switch between modes — they fly out of the menu bar icon on the right
    /// while the leaving `icons` are pulled into it on the left. Empty for an ordinary start or end (unchanged).
    /// Off-screen filmstrip for checking the show without a screen: frames at `filmstrip` seconds, written to `film`.
    var filmstrip: [Double]? = nil, film: String? = nil
    func play(start: Bool, icons: [NSImage], incoming: [NSImage] = [], target: NSPoint, label: String, hold: (start: Double, end: Double) = AnimSpeed.normal.hold) {
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
        let word = CATextLayer(); word.contentsScale = s
        word.frame = CGRect(x: 50, y: 12, width: size.width - 62, height: 20)
        // The name writes itself in, letter by letter left to right, a spark at each new letter; on End it deletes
        // itself right to left. `p` = how far through the word (0…1); each letter fades over a short window.
        let wordFont = NSFont.systemFont(ofSize: 15, weight: .semibold), chars = Array(label)
        let edges: [CGFloat] = (0...chars.count).map { k in (String(chars.prefix(k)) as NSString).size(withAttributes: [.font: wordFont]).width }
        func spell(_ p: CGFloat) {
            let a = NSMutableAttributedString()
            for (k, c) in chars.enumerated() {
                let soft = 1.6 / CGFloat(max(chars.count, 1))                        // each letter fades in over this much of p
                let alpha = min(max((p - CGFloat(k) / CGFloat(max(chars.count, 1))) / soft, 0), 1)
                a.append(NSAttributedString(string: String(c), attributes: [.font: wordFont, .foregroundColor: theme.hudInk.withAlphaComponent(alpha)]))
            }
            word.string = a
        }
        var sparks: [CAShapeLayer] = []
        func spark(at k: Int) {                                     // a small four-point star where letter k appears / goes
            let x = 50 + (edges[min(k + 1, chars.count)] + edges[k]) / 2, sz: CGFloat = 7.5
            let path = CGMutablePath(), q = sz * 0.28
            path.addLines(between: [CGPoint(x: 0, y: sz), CGPoint(x: q, y: q), CGPoint(x: sz, y: 0), CGPoint(x: q, y: -q),
                                    CGPoint(x: 0, y: -sz), CGPoint(x: -q, y: -q), CGPoint(x: -sz, y: 0), CGPoint(x: -q, y: q)]); path.closeSubpath()
            let l = CAShapeLayer(); l.path = path; l.fillColor = theme.hudInk.cgColor; l.position = CGPoint(x: x, y: 24)
            l.shadowColor = theme.hudInk.cgColor; l.shadowOpacity = 1; l.shadowRadius = 4; l.shadowOffset = .zero   // a soft glow
            l.contentsScale = s; l.setValue(clock, forKey: "born"); pill.addSublayer(l); sparks.append(l)
        }
        func tickSparks() {
            for l in sparks {
                let age = CGFloat(clock.timeIntervalSince(l.value(forKey: "born") as? Date ?? clock) / 0.38)
                l.opacity = Float(max(0, 1 - age * age)); let k = age < 0.25 ? 0.3 + 3.2 * age : 1.1 - 0.5 * (age - 0.25)   // flare, then fade
                l.transform = CATransform3DConcat(CATransform3DMakeScale(k, k, 1), CATransform3DMakeRotation(age * 1.6, 0, 0, 1))
            }
        }
        var sparked = start ? -1 : chars.count                      // the last letter that has had its spark
        spell(start ? 0 : 1)
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
        let switching = start && !incoming.isEmpty
        // An ordinary start or end: one arc above the pill. A switch: leaving apps on the left half, arriving on the right.
        func arc(_ count: Int, from a0: CGFloat, to a1: CGFloat) -> [CGPoint] {
            (0..<count).map { i in
                let a = count == 1 ? (a0 + a1) / 2 * .pi : .pi * (a0 + (a1 - a0) * CGFloat(i) / CGFloat(count - 1))
                return CGPoint(x: home.x + cos(a) * 150, y: home.y + 26 + sin(a) * 92)
            }
        }
        let fan = switching ? arc(n, from: 0.86, to: 0.56) : (n == 1 ? arc(1, from: 0.5, to: 0.5) : arc(n, from: 0.78, to: 0.22))
        let arriving = Array(incoming.prefix(9)), m = arriving.count
        let inTiles: [CALayer] = arriving.map { img in
            let l = CALayer(); l.bounds = CGRect(x: 0, y: 0, width: 44, height: 44); l.contentsScale = s
            l.contents = img.cgImage(forProposedRect: nil, context: nil, hints: nil); l.opacity = 0
            root.addSublayer(l); return l
        }
        let inFan = arc(m, from: 0.44, to: 0.14)
        func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
        func setMark(_ t: CGFloat) { mark.contents = painted(glyph(t), theme.hudInk, NSSize(width: 24, height: 24)) }

        // Timeline (seconds). `stop` is the hit stop: nothing moves but the flash.
        let popIn = 0.16, stop = 0.10, stagger = 0.035, fly = 0.34
        let impact = start ? popIn : popIn + Double(max(n - 1, 0)) * stagger + fly + hold.end + 0.20   // Normal: + 0.02 + 0.20 = the original + 0.22
        let after = impact + stop
        let flyDone = start ? after + hold.start + Double(max(n - 1, 0)) * stagger + fly : impact     // Normal: hold 0.24 = the original 0.16 + 0.08
        let landed = after + hold.start + Double(max(incoming.prefix(9).count - 1, 0)) * stagger + fly * 1.5
        let zipAt = (start ? max(flyDone, incoming.isEmpty ? 0 : landed) : after + 0.06), zipLen = 0.22, end = zipAt + zipLen + 0.05
        setMark(start ? 0 : 1)

        var clock = Date()                                          // the sparks age by this (real time, or the filmstrip's)
        let step: (Double) -> Void = { now in
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
            // the name: written in after the pop (start), deleted before the impact (end)
            let wp: CGFloat = start ? CGFloat((now - popIn * 0.6) / 0.42) : 1 - CGFloat((now - popIn - 0.12) / max(impact - popIn - 0.2, 0.25))
            let clamped = min(max(wp, 0), 1); spell(clamped)
            let at = Int((clamped * CGFloat(chars.count)).rounded(.down))
            if start { while sparked < min(at, chars.count - 1) { sparked += 1; spark(at: sparked) } }
            else { while sparked > at && sparked > 0 { sparked -= 1; spark(at: sparked) } }
            tickSparks()
            // arriving apps (a switch): out of the menu bar icon to the right, then down into the pill
            for (i, l) in inTiles.enumerated() {
                let d = Double(i) * stagger
                let out = CGFloat((now - after - d) / fly), drop = CGFloat((now - after - hold.start - d - fly * 0.5) / fly)
                if out <= 0 { l.opacity = 0; continue }
                if drop <= 0 {
                    let k = easeOut(out)
                    l.position = lerp(tgt, inFan[i], k); l.opacity = Float(ease(out * 3))
                    l.transform = CATransform3DMakeScale(0.2 + 0.8 * k, 0.2 + 0.8 * k, 1)
                } else {
                    let k = easeIn(drop)
                    l.position = lerp(inFan[i], home, k); l.opacity = Float(1 - k)
                    l.transform = CATransform3DMakeScale(1 - 0.6 * k, 1 - 0.6 * k, 1)
                }
            }
            // icons
            for (i, l) in tiles.enumerated() {
                let d = Double(i) * stagger
                if start {
                    let burst = CGFloat((now - after - d * 0.5) / 0.16), suck = CGFloat((now - after - hold.start - d) / fly)
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
                    let out = CGFloat((now - popIn - d) / fly), drop = CGFloat((now - popIn - Double(max(n - 1, 0)) * stagger - fly - hold.end) / 0.12)
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
        }
        if let frames = filmstrip, let film {                       // render, don't show
            let fw = 760, fh = 300, rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: fw, pixelsHigh: fh * frames.count, bitsPerSample: 8,
                                                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
            ctx.setFillColor(NSColor(white: 0.42, alpha: 1).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: fw, height: fh * frames.count))
            let base = Date()
            for (k, f) in frames.enumerated() {
                // replay from 0 so sparks are born at the right moments
                var tt = 0.0; while tt < f { clock = base.addingTimeInterval(tt); step(tt); tt += 1.0 / 120 }
                clock = base.addingTimeInterval(f); step(f)
                ctx.saveGState()
                ctx.translateBy(x: CGFloat(fw) / 2 - home.x, y: CGFloat(fh * (frames.count - 1 - k)) + 20 - home.y + 40)
                root.render(in: ctx); ctx.restoreGState()
                ctx.setFillColor(NSColor.white.cgColor)
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                (String(format: "%.2fs", f) as NSString).draw(at: NSPoint(x: 8, y: fh * (frames.count - k) - 20), withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 12)])
                NSGraphicsContext.restoreGraphicsState()
            }
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: film))
            return
        }
        w.orderFrontRegardless(); win = w
        let began = Date()
        let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] tm in
            let now = Date().timeIntervalSince(began); clock = Date()
            step(now)
            if now > end { tm.invalidate(); self?.win?.orderOut(nil); self?.win = nil }
        }
        RunLoop.main.add(t, forMode: .common); timer = t
    }
}

typealias Session = [String: Any]                              // "date": Date, "apps": [["path": String, "hidden": Bool]]

final class Focus: NSObject, NSMenuDelegate {
    let ws = NSWorkspace.shared, store: UserDefaults
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)   // room for the session's name
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
    var modeMods: Int { get { store.object(forKey: "modeMods") as? Int ?? modeModifierChoices[0].mods } set { store.set(newValue, forKey: "modeMods"); applyShortcuts() } }
    var takenModeKeys: Set<Int> = []                            // digits macOS refused (another app holds them)
    var keyRefs: [EventHotKeyRef?] = []
    var sessionKeyTaken = false, menuKeyTaken = false
    func label(_ mods: Int) -> String { modifierChoices.first { $0.mods == mods }?.label ?? "⌘⇧" }
    func label(forMode d: Int) -> String { (modeModifierChoices.first { $0.mods == modeMods }?.label ?? "⌘") + String(d) }
    /// (Re)registers both shortcuts. Takes effect at once; reports a combination another app already holds.
    func applyShortcuts() {
        keyRefs.forEach { if let k = $0 { UnregisterEventHotKey(k) } }
        let s = hotkey(1, kVK_ANSI_F, sessionMods), m = hotkey(2, kVK_ANSI_E, menuMods)
        keyRefs = [s, m]; sessionKeyTaken = s == nil; menuKeyTaken = m == nil
        takenModeKeys = []
        for md in modes { if let d = md["key"] as? Int, digitKeys.indices.contains(d) {   // only the keys the user set
            let r = hotkey(UInt32(100 + d), digitKeys[d], modeMods); keyRefs.append(r); if r == nil { takenModeKeys.insert(d) }
        } }
        sessionKey = label(sessionMods) + "F"
        button?.needsDisplay = true
    }
    func releaseShortcuts() { keyRefs.forEach { if let k = $0 { UnregisterEventHotKey(k) } }; keyRefs = [] }
    @objc func pickSessionKey(_ s: NSMenuItem) { sessionMods = s.tag }
    @objc func pickMenuKey(_ s: NSMenuItem) { menuMods = s.tag }
    @objc func pickModeMods(_ s: NSMenuItem) { modeMods = s.tag }
    let when: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; f.doesRelativeDateFormatting = true; return f
    }()

    var sessions: [Session] {                                   // newest first, last 12 kept
        get { store.array(forKey: "sessions") as? [Session] ?? [] }
        set { store.set(Array(newValue.prefix(12)), forKey: "sessions"); updateTitle() }
    }
    /// In a session the menu bar reads: icon, then the mode's or session's name. Settings can make it icon only.
    var showNameInMenuBar: Bool { get { store.object(forKey: "showNameInMenuBar") as? Bool ?? true } set { store.set(newValue, forKey: "showNameInMenuBar"); updateTitle() } }
    /// What the live session is called: its own name, else the mode whose apps it mostly kept (at least half of
    /// the mode's apps), else "Focus". nil out of a session.
    var displayName: String? {
        guard focused, let live = sessions.first else { return nil }
        if let n = sessionName { return n }
        let kept = Set(self.kept(live))
        let best = modes.compactMap { m -> (String, Double)? in
            let apps = Set(m["apps"] as? [String] ?? []); guard !apps.isEmpty, let name = m["name"] as? String else { return nil }
            return (name, Double(apps.intersection(kept).count) / Double(apps.count))
        }.max { $0.1 < $1.1 }
        return best.flatMap { $0.1 >= 0.5 ? $0.0 : nil } ?? "Focus"
    }
    func updateTitle() {
        guard let b = item.button else { return }
        let t = showNameInMenuBar ? (displayName.map { " " + Focus.nameStyles[menuBarNameStyle]($0) } ?? "") : ""
        if store != .standard { if b.title != t { b.title = t; b.imagePosition = t.isEmpty ? .imageOnly : .imageLeft }; return }   // tests: at once
        guard t != titleTarget else { return }
        titleTarget = t
        guard titleTimer == nil else { return }                 // already writing: it will head for the new target
        let tm = Timer(timeInterval: 0.05, repeats: true) { [weak self] tm in self?.writeTitle(tm) }
        RunLoop.main.add(tm, forMode: .common); titleTimer = tm
    }
    /// The menu bar name is written one letter at a time (the icon slides left as it grows), then sparkles and pops.
    /// Ending a session deletes it the same way, from the right.
    var titleTarget = "", titleTimer: Timer?
    func writeTitle(_ tm: Timer) {
        guard let b = item.button else { tm.invalidate(); titleTimer = nil; return }
        let now = b.title.replacingOccurrences(of: " ✦", with: ""), goal = titleTarget
        if now == goal {
            tm.invalidate(); titleTimer = nil
            b.title = goal; b.imagePosition = goal.isEmpty ? .imageOnly : .imageLeft
            guard !goal.isEmpty else { return }
            b.title = goal + " ✦"                               // the sparkle
            b.wantsLayer = true
            if let l = b.layer {                                 // the pop
                let pop = CAKeyframeAnimation(keyPath: "transform.scale")
                pop.values = [1, 1.14, 0.97, 1]; pop.keyTimes = [0, 0.35, 0.7, 1]; pop.duration = 0.32
                l.anchorPoint = CGPoint(x: 0.5, y: 0.5); l.position = CGPoint(x: b.bounds.midX, y: b.bounds.midY)
                l.add(pop, forKey: "pop")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self, self.titleTimer == nil, let b = self.item.button, b.title == goal + " ✦" else { return }
                b.title = self.titleTarget
            }
            return
        }
        // one letter towards the goal: delete from the right until what's shown is the start of it, then add
        let next = goal.hasPrefix(now) ? String(goal.prefix(now.count + 1)) : String(now.dropLast())
        b.title = next; b.imagePosition = next.isEmpty ? .imageOnly : .imageLeft
    }
    @objc func toggleNameInMenuBar() { showNameInMenuBar.toggle() }
    /// How much the menu's headings say: 0 Minimalist (the name only), 1 Normal (name — a few words), 2 Verbose
    /// (Normal, plus a sentence under each explaining the section).
    var headingStyle: Int { get { min(max(store.object(forKey: "headingStyle") as? Int ?? 1, 0), 2) } set { store.set(newValue, forKey: "headingStyle") } }
    @objc func pickHeadingStyle(_ s: NSMenuItem) { headingStyle = s.tag }
    /// How the name reads beside the icon: "AI", "AI session" or "AI (in session)".
    static let nameStyles: [(String) -> String] = [{ $0 }, { $0 + " session" }, { $0 + " (in session)" }]
    var menuBarNameStyle: Int {
        get { min(max(store.object(forKey: "menuBarNameStyle") as? Int ?? 1, 0), Focus.nameStyles.count - 1) }
        set { store.set(newValue, forKey: "menuBarNameStyle"); store.set(true, forKey: "showNameInMenuBar"); updateTitle() }
    }
    @objc func pickNameStyle(_ s: NSMenuItem) { if s.tag < 0 { showNameInMenuBar = false } else { menuBarNameStyle = s.tag } }
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
    func drawIcon(_ t: CGFloat, hunt: Bool = false) { item.button?.image = glyph(t, hunt: hunt, ring: ringColor, dot: dotColor); updateTitle() }
    func redrawIcon() { drawIcon(focused ? 1 : 0) }
    /// Apps you can see in the Dock right now (Focus and macOS's own apps aside): Counter's number.
    func countApps() {
        let n = ws.runningApplications.filter { $0.activationPolicy == .regular && !system($0) }.count
        guard n != openAppCount else { return }
        openAppCount = n
        if iconStyle == .counter && pill.timer?.isValid != true { redrawIcon() }   // never mid-animation
    }
    func setIcon(_ img: NSImage) { redrawIcon() }
    /// Colour schemes the user saved: [name, ring hex, dot hex] (dot "" = same as ring).
    var customSchemes: [[String]] {
        get { (store.array(forKey: "customSchemes") as? [[String]] ?? []).filter { $0.count == 3 && !$0[0].isEmpty } }
        set { store.set(newValue, forKey: "customSchemes") }
    }
    func addScheme(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !n.isEmpty, !iconColor.isEmpty else { return }
        customSchemes = customSchemes.filter { $0[0] != n } + [[n, iconColor, iconColor2]]   // same name: replaced
    }
    @objc func saveScheme() {
        let a = NSAlert(); a.messageText = "Save these colours as a scheme"; a.informativeText = "Give it a name. It will appear under Your Schemes."
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24)); f.placeholderString = "Name"; a.accessoryView = f
        a.addButton(withTitle: "Save"); a.addButton(withTitle: "Cancel"); a.window.initialFirstResponder = f
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { addScheme(f.stringValue) }
    }
    @objc func deleteScheme(_ s: NSMenuItem) { var c = customSchemes; if c.indices.contains(s.tag) { c.remove(at: s.tag); customSchemes = c } }
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
    /// Settings ▸ Appearance ▸ Icon. Missing = Lens, the original.
    var iconStyleSetting: IconStyle {
        get { IconStyle(rawValue: store.string(forKey: "iconStyle") ?? "") ?? .lens }
        set { store.set(newValue.rawValue, forKey: "iconStyle"); if store == .standard { iconStyle = newValue }; redrawIcon() }
    }
    /// Settings ▸ Appearance ▸ Animation Speed. Missing = Normal, the permanent default.
    var animSpeed: AnimSpeed {
        get { AnimSpeed(rawValue: store.integer(forKey: "animSpeed")) ?? .normal }
        set { store.set(newValue.rawValue, forKey: "animSpeed") }
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
    /// Apps that are HIDDEN in a session instead of quit: they come back exactly as they were — the same chat, page,
    /// scroll — because they never closed. They keep their memory. For apps that don't restore themselves after a quit.
    var hideOnly: [String] {
        get { store.stringArray(forKey: "hideOnly") ?? [] }
        set { store.set(newValue, forKey: "hideOnly") }
    }
    /// Careful (one app at a time, each saving before the next) or fast (everything at once). Careful unless chosen.
    var fastSwitching: Bool {
        get { store.bool(forKey: "fastSwitching") }
        set { store.set(newValue, forKey: "fastSwitching") }
    }
    @objc func switchingCareful() { fastSwitching = false }
    @objc func switchingFast() { fastSwitching = true }
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
        migrateModes()                                          // older modes get their permanent ids
        if store == .standard { iconStyle = iconStyleSetting }     // the real Focus draws the user's chosen design everywhere
        if store == .standard {                                 // Counter shows how many apps are open: keep it current
            for n in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                ws.notificationCenter.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in self?.countApps() }
            }
            countApps()
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
        pill.play(start: true, icons: out.compactMap { $0.bundleURL.map { ws.icon(forFile: $0.path) } }, target: iconPoint, label: name ?? "Focus", hold: animSpeed.hold)
        // What defines a session is what you KEEP (Unreal + Claude = game design); the parked list is just what to bring back.
        let parkedIDs = Set(out.compactMap(\.bundleIdentifier))
        let keptNow = ws.runningApplications.filter { $0.activationPolicy == .regular && !system($0) && !parkedIDs.contains($0.bundleIdentifier ?? "") && !neverClose.contains($0.bundleIdentifier ?? "") }
        let keptIDs = keep.map { Array($0) } ?? keptNow.compactMap(\.bundleIdentifier)
        var record: Session = ["date": Date(), "kept": keptIDs, "apps": out.compactMap { a in a.bundleURL.map { ["path": $0.path, "id": a.bundleIdentifier ?? "", "hidden": a.isHidden, "pid": Int(a.processIdentifier)] as [String: Any] } }]
        // Started mid-restore: the apps that restore hadn't reached join this session, so End brings them back too.
        let have = Set(out.compactMap { $0.bundleURL?.path })
        let unreached = pendingRestore.filter { e in (e["path"] as? String).map { p in !have.contains(p) && !ws.runningApplications.contains { $0.bundleURL?.path == p } } ?? false }
        if !unreached.isEmpty { record["apps"] = (record["apps"] as? [[String: Any]] ?? []) + unreached }
        pendingRestore = []
        if let name { record["mode"] = name; record["name"] = name }
        if let mid = mode?["id"] as? String { record["modeID"] = mid }
        sessions.insert(record, at: 0)
        focused = true
        let go = { [self] in
            guard generation == gen, focused else { return }     // ended (or restarted) before the snapshot finished
            if !quit { out.forEach { $0.hide() }; return }
            let hide = Set(hideOnly)                              // these stay exactly as they are: hidden, never quit
            out.filter { hide.contains($0.bundleIdentifier ?? "") }.forEach { $0.hide() }
            let toQuit = out.filter { !hide.contains($0.bundleIdentifier ?? "") }
            if fastSwitching { return quitAllAtOnce(toQuit) }
            queue = toQuit.sorted { memory($0) > memory($1) }; total = queue.count   // biggest first: memory comes back soonest
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

    // MARK: editing a live session — no ending, no procedure

    /// The live session's parked entries (what End Session will reopen).
    var parkedEntries: [[String: Any]] { focused ? (sessions.first?["apps"] as? [[String: Any]] ?? []) : [] }
    func isParked(_ id: String) -> Bool { parkedEntries.contains { ($0["id"] as? String) == id || ($0["path"] as? String).flatMap { Bundle(path: $0)?.bundleIdentifier } == id } }
    /// Takes an open app out of the session now: saved and quit (or hidden, if it's hide-only) like the rest,
    /// and added to the session so End Session brings it back.
    func parkNow(_ id: String) {
        guard focused, !sessions.isEmpty, let a = ws.runningApplications.first(where: { $0.bundleIdentifier == id && !$0.isTerminated }), !protected(a) else { return }
        if !isParked(id), let url = a.bundleURL {
            var s0 = sessions[0]
            s0["apps"] = (s0["apps"] as? [[String: Any]] ?? []) + [["path": url.path, "id": id, "hidden": a.isHidden, "pid": Int(a.processIdentifier)]]
            s0["kept"] = (s0["kept"] as? [String] ?? []).filter { $0 != id }
            sessions[0] = s0
        }
        excluded = excluded.filter { $0 != id }; modeKeep?.remove(id)
        if hideOnly.contains(id) { a.hide(); return }
        if queue.isEmpty { queue = [a]; total = 1; quitNext() } else if !queue.contains(a) { queue.append(a); total += 1 }
    }
    /// Brings a parked app back into the session now: reopened (or un-hidden) and no longer parked.
    func bringBack(_ id: String) {
        guard focused, !sessions.isEmpty else { return }
        let entry = parkedEntries.first { ($0["id"] as? String) == id || ($0["path"] as? String).flatMap { Bundle(path: $0)?.bundleIdentifier } == id }
        var s0 = sessions[0]
        s0["apps"] = parkedEntries.filter { e in !((isEntry(e, id))) }
        s0["kept"] = (s0["kept"] as? [String] ?? []).filter { $0 != id } + [id]
        sessions[0] = s0
        if !excluded.contains(id) { excluded.append(id) }; modeKeep?.insert(id)
        queue.removeAll { $0.bundleIdentifier == id }; waiting.removeAll { $0.bundleIdentifier == id }
        if let a = ws.runningApplications.first(where: { $0.bundleIdentifier == id && !$0.isTerminated }) {
            a.unhide(); a.activate(options: [.activateAllWindows])
        } else if let e = entry ?? path(id).map({ ["path": $0, "id": id] as [String: Any] }) {
            relaunch(ArraySlice([e.merging(["hidden": false]) { $1 }]), generation)
        }
        if waiting.isEmpty, status?.hasPrefix("Waiting") == true { status = nil }
    }
    func isEntry(_ e: [String: Any], _ id: String) -> Bool {
        (e["id"] as? String) == id || (e["path"] as? String).flatMap { Bundle(path: $0)?.bundleIdentifier } == id
    }
    @objc func showPrompt(_ s: NSMenuItem) {
        guard let id = s.representedObject as? String, let a = ws.runningApplications.first(where: { $0.bundleIdentifier == id }) else { return }
        a.unhide(); a.activate(options: [.activateAllWindows])
    }
    @objc func keepStuck(_ s: NSMenuItem) { if let id = s.representedObject as? String { bringBack(id) } }
    @objc func forceStuck(_ s: NSMenuItem) {
        guard let id = s.representedObject as? String, let a = ws.runningApplications.first(where: { $0.bundleIdentifier == id }) else { return }
        let alert = NSAlert(); alert.alertStyle = .critical
        alert.messageText = "Force quit \(a.localizedName ?? "this app")?"
        alert.informativeText = "Anything it hasn't saved will be lost. End Session still reopens it."
        alert.addButton(withTitle: "Force Quit"); alert.addButton(withTitle: "Cancel"); alert.buttons[0].hasDestructiveAction = true
        guard run(alert) == .alertFirstButtonReturn else { return }
        a.forceTerminate(); waiting.removeAll { $0 == a }
        if waiting.isEmpty, status?.hasPrefix("Waiting") == true { status = nil }
    }

    /// Fast switching: every app is asked to quit at the same moment (still the normal way — never forced), then
    /// the usual waiting list for any that don't go within `patience`.
    func quitAllAtOnce(_ apps: [NSRunningApplication]) {
        queue = apps; total = apps.count
        status = "Quitting \(self.apps(apps.count)) at once"
        apps.forEach { $0.terminate() }
        let started = Date(), gen = generation
        func check() {
            guard gen == generation, focused || clearing else { return }   // ended meanwhile
            let left = queue.filter { !$0.isTerminated }
            if left.isEmpty || Date().timeIntervalSince(started) > patience {
                waiting.append(contentsOf: left); return finishQueue()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: check)
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
                         "apps": out.compactMap { a in a.bundleURL.map { ["path": $0.path, "id": a.bundleIdentifier ?? "", "hidden": a.isHidden, "pid": Int(a.processIdentifier)] as [String: Any] } }], at: 0)
        pill.play(start: true, icons: out.compactMap { $0.bundleURL.map { ws.icon(forFile: $0.path) } }, target: iconPoint, label: "Clear", hold: animSpeed.hold)
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
                         "apps": out.compactMap { a in a.bundleURL.map { ["path": $0.path, "id": a.bundleIdentifier ?? "", "hidden": a.isHidden, "pid": Int(a.processIdentifier)] as [String: Any] } }], at: 0)
        pill.play(start: true, icons: out.compactMap { $0.bundleURL.map { ws.icon(forFile: $0.path) } }, target: iconPoint, label: "Clear", hold: animSpeed.hold)
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
                  target: iconPoint, label: "Back", hold: animSpeed.hold)
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
            if let a = ws.runningApplications.first(where: matches([e])) {
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
        let gap = fastSwitching ? 0 : (launched ? 0.7 : 0.05)     // fast: everything opens at once
        DispatchQueue.main.asyncAfter(deadline: .now() + gap) { self.relaunch(rest.dropFirst(), gen) }
    }

    /// Is this running app one of a session's entries? By bundle id — paths have several spellings (/var vs
    /// /private/var, moved or translocated apps) — falling back to the path for sessions saved before ids were kept.
    func matches(_ entries: [[String: Any]]) -> (NSRunningApplication) -> Bool {
        let ids = Set(entries.compactMap { $0["id"] as? String }.filter { !$0.isEmpty })
        let paths = Set(entries.compactMap { $0["path"] as? String }.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path })
        return { a in
            if let id = a.bundleIdentifier, ids.contains(id) { return true }
            return a.bundleURL.map { paths.contains($0.resolvingSymlinksInPath().path) } ?? false
        }
    }
    /// Session apps still open after their turn: usually a save prompt waiting for you.
    func stragglers() -> [NSRunningApplication] {
        guard focused, !hideMode else { return [] }
        let waiting = Set(queue.map(\.processIdentifier)), inSession = matches(sessions.first?["apps"] as? [[String: Any]] ?? [])
        return ws.runningApplications.filter { inSession($0) && !$0.isHidden && !protected($0) && !waiting.contains($0.processIdentifier) }
    }
    /// Session apps running under a different process than the one Focus quit: something reopened them
    /// (a login item, a helper, an updater). Different from a save prompt, and worth a different line.
    func reopened() -> [NSRunningApplication] {
        guard focused, !hideMode else { return [] }
        let entries = sessions.first?["apps"] as? [[String: Any]] ?? []
        let quitPids = Set(entries.compactMap { $0["pid"] as? Int }), inSession = matches(entries)
        guard !quitPids.isEmpty else { return [] }
        let waiting = Set(queue.map(\.processIdentifier))
        // Hidden or not: a relaunched app is using memory either way.
        return ws.runningApplications.filter {
            inSession($0) && !protected($0) && !waiting.contains($0.processIdentifier) && !quitPids.contains(Int($0.processIdentifier))
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
        set { store.set(newValue, forKey: "modes"); if store == .standard && !keyRefs.isEmpty { applyShortcuts() } }
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
    // MARK: modes — the plumbing (a drag-and-drop UI will call these; nothing here depends on how they're called)

    static let appDragType = NSPasteboard.PasteboardType("com.labern.focus.app")   // our own drags carry a bundle id
    /// Every mode has a permanent id, so a rename, reorder or delete can never hit the wrong one. Older modes get one.
    func migrateModes() {
        guard modes.contains(where: { ($0["id"] as? String ?? "").isEmpty }) else { return }
        modes = modes.map { var m = $0; if (m["id"] as? String ?? "").isEmpty { m["id"] = UUID().uuidString }; return m }
    }
    func modeIndex(_ id: String) -> Int? { modes.firstIndex { $0["id"] as? String == id } }
    func mode(_ id: String) -> [String: Any]? { modeIndex(id).map { modes[$0] } }
    /// A bundle id from an app on disk — what a drag from Finder or the Dock hands over.
    func appID(at url: URL) -> String? { url.pathExtension == "app" ? Bundle(url: url)?.bundleIdentifier : nil }
    /// The apps on a drag-and-drop pasteboard: our own drags (bundle ids) or .app files dragged in.
    func draggedApps(_ pb: NSPasteboard) -> [String] {
        let ours = (pb.pasteboardItems ?? []).compactMap { $0.string(forType: Focus.appDragType) }
        let files = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []).compactMap(appID)
        return ours + files
    }
    @discardableResult
    func createMode(_ name: String, apps ids: [String]) -> String {
        let id = UUID().uuidString
        var seen = Set<String>()
        let used = Set(modes.compactMap { $0["key"] as? Int })
        let digit = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0].first { !used.contains($0) }     // ⌘1, ⌘2 … ⌘0; past ten, none
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var m: [String: Any] = ["id": id, "name": n.isEmpty ? "Mode \(digit.map(String.init) ?? String(modes.count + 1))" : n,
                                "apps": ids.filter { path($0) != nil && seen.insert($0).inserted }]
        if let digit { m["key"] = digit }
        modes.append(m)
        return id
    }
    /// The number the next new mode will get (nil once all ten are taken).
    var nextModeKey: Int? { let used = Set(modes.compactMap { $0["key"] as? Int }); return [1, 2, 3, 4, 5, 6, 7, 8, 9, 0].first { !used.contains($0) } }
    @objc func createDraftMode() { guard !draftApps.isEmpty else { return }; createMode("", apps: draftApps); draftApps = [] }
    func renameMode(_ id: String, to name: String) { if let i = modeIndex(id), !name.isEmpty { modes[i]["name"] = name } }
    func removeMode(_ id: String) { if let i = modeIndex(id) { modes.remove(at: i) } }
    /// Suggested modes: a starting point for anyone, built only from apps this Mac actually has. Each lists
    /// candidates by kind; the first installed ones are used. "browser" = whatever the default browser is.
    static let suggestions: [(name: String, groups: [[String]])] = [
        ("Game Design", [["com.epicgames.UnrealEditor", "com.epicgames.UnrealEditor5", "com.unity3d.unityhub", "org.godotengine.godot", "org.blenderfoundation.blender"],
                         ["com.anthropic.claudefordesktop", "com.openai.chat"]]),
        ("Web Only", [["browser"]]),
        ("Writing", [["com.ulyssesapp.mac", "pro.writer.mac", "com.literatureandlatte.scrivener3", "com.microsoft.Word", "com.apple.iWork.Pages", "md.obsidian", "net.shinyfrog.bear"],
                     ["browser"]]),
        ("Coding", [["com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed"],
                    ["com.mitchellh.ghostty", "com.googlecode.iterm2", "com.apple.Terminal"], ["browser"]]),
        ("Design", [["com.figma.Desktop", "com.bohemiancoding.sketch3", "com.pixelmatorteam.pixelmator.x", "com.seriflabs.affinitydesigner2"], ["browser"]]),
        ("Calls", [["us.zoom.xos", "com.microsoft.teams2", "com.apple.FaceTime"], ["com.apple.Notes"]]),
    ]
    var defaultBrowser: String? {
        URL(string: "https://example.com").flatMap { ws.urlForApplication(toOpen: $0) }.flatMap { Bundle(url: $0)?.bundleIdentifier }
    }
    /// When an app was last used: now if it's running, else what macOS's index recorded (nil = never / unknown).
    func lastUsed(_ id: String) -> Date? {
        if ws.runningApplications.contains(where: { $0.bundleIdentifier == id && !$0.isTerminated }) { return Date() }
        guard let p = path(id), let item = MDItemCreate(nil, p as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
    /// A few suggestions this Mac can use, each built from the apps of that kind the user actually uses (running or
    /// most recently used, never a fixed favourite), minus any already saved as a mode. Most relevant first.
    func suggestedModes(limit: Int = 3) -> [(name: String, apps: [String])] {
        let have = Set(modes.compactMap { ($0["name"] as? String)?.lowercased() })
        let browser = defaultBrowser
        func resolve(_ g: [String]) -> [String] { g.compactMap { $0 == "browser" ? browser : $0 }.filter { path($0) != nil } }
        func best(_ g: [String]) -> (String, Date)? {
            resolve(g).map { ($0, lastUsed($0) ?? .distantPast) }.max { $0.1 < $1.1 }
        }
        let scored: [(String, [String], Date)] = Focus.suggestions.compactMap { sg in
            guard !have.contains(sg.name.lowercased()), let core = best(sg.groups.first ?? []) else { return nil }   // its main kind must be installed
            let apps = sg.groups.compactMap { best($0)?.0 }
            return (sg.name, apps, core.1)
        }
        return scored.sorted { $0.2 > $1.2 }.prefix(limit).map { ($0.0, $0.1) }
    }
    /// Gives a mode a digit (nil = none). A digit belongs to one mode: taking it moves it.
    func setModeKey(_ id: String, _ digit: Int?) {
        var all = modes
        for i in all.indices {
            if all[i]["id"] as? String == id { if let digit { all[i]["key"] = digit } else { all[i].removeValue(forKey: "key") } }
            else if let digit, all[i]["key"] as? Int == digit { all[i].removeValue(forKey: "key") }
        }
        modes = all
    }
    @objc func pickModeKey(_ s: NSMenuItem) {
        guard let id = s.representedObject as? String else { return }
        setModeKey(id, s.tag < 0 ? nil : s.tag)
    }
    func modeForKey(_ d: Int) -> [String: Any]? { modes.first { $0["key"] as? Int == d } }
    /// A mode's key: start it; press again to end it; in another session, switch straight to it.
    func modeKey(_ d: Int) {
        NSLog("Focus: mode key %d pressed (mode: %@)", d, (modeForKey(d)?["name"] as? String) ?? "none")
        guard !clearing, let m = modeForKey(d), let id = m["id"] as? String else { return }
        startOrSwitch(id)
    }
    /// Switch from the live session to a mode without reopening everything in between: the mode's apps come up
    /// (back from Temporarily Closed, or opened), everything else open is temporarily closed — all in the same
    /// session, so End Session still brings back exactly what was open before the first one started.
    func switchMode(id: String, limit: Set<String>? = nil) {
        guard focused, !sessions.isEmpty, let m = mode(id) else { return }
        let want = m["apps"] as? [String] ?? [], name = m["name"] as? String ?? "Mode"
        let arriving = want.filter { id in isParked(id) || !ws.runningApplications.contains(where: { a in a.bundleIdentifier == id && !a.isTerminated }) }
        for app in want {
            if isParked(app) { bringBack(app) }
            else if !ws.runningApplications.contains(where: { $0.bundleIdentifier == app && !$0.isTerminated }), let url = ws.urlForApplication(withBundleIdentifier: app) {
                let c = NSWorkspace.OpenConfiguration(); c.activates = false; ws.openApplication(at: url, configuration: c)
            }
        }
        let leaving = apps().compactMap(\.bundleIdentifier).filter { !want.contains($0) && !isParked($0) && (limit?.contains($0) ?? true) }
        pill.play(start: true, icons: leaving.compactMap(path).map { ws.icon(forFile: $0) }, incoming: arriving.compactMap(path).map { ws.icon(forFile: $0) },
                  target: iconPoint, label: name, hold: animSpeed.hold)
        for app in leaving { parkNow(app) }
        var s0 = sessions[0]; s0["mode"] = name; s0["name"] = name; s0["modeID"] = id; s0["kept"] = want; sessions[0] = s0
        modeKeep = Set(want)
    }
    @objc func addSuggested(_ s: NSMenuItem) {
        guard let name = s.representedObject as? String, let sg = suggestedModes(limit: 9).first(where: { $0.name == name }) else { return }
        createMode(sg.name, apps: sg.apps)
    }
    /// The mode being built in New Mode, before it's named.
    var draftApps: [String] = []
    @objc func addAppToDraft() {
        let p = NSOpenPanel(); p.directoryURL = URL(fileURLWithPath: "/Applications"); p.allowedContentTypes = [.application]
        p.allowsMultipleSelection = true; p.prompt = "Add to Mode"; p.message = "Choose apps for the new mode"
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK else { return }
        for url in p.urls { if let a = appID(at: url), !draftApps.contains(a) { draftApps.append(a) } }
    }
    /// Add any installed app to a mode, whether or not it's running.
    @objc func addAppToMode(_ s: NSMenuItem) {
        guard let id = s.representedObject as? String else { return }
        let p = NSOpenPanel(); p.directoryURL = URL(fileURLWithPath: "/Applications"); p.allowedContentTypes = [.application]
        p.allowsMultipleSelection = true; p.prompt = "Add to Mode"; p.message = "Choose apps for this mode"
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK else { return }
        for url in p.urls { if let app = appID(at: url) { addApp(app, toMode: id) } }
    }
    /// Adds an installed app to a mode (once), at a position or at the end. False = unknown mode or app, or already in.
    @discardableResult
    func addApp(_ app: String, toMode id: String, at index: Int? = nil) -> Bool {
        guard let i = modeIndex(id), path(app) != nil else { return false }
        var list = modes[i]["apps"] as? [String] ?? []
        guard !list.contains(app) else { return false }
        list.insert(app, at: min(max(index ?? list.count, 0), list.count))
        modes[i]["apps"] = list; return true
    }
    @discardableResult
    func addApps(from pb: NSPasteboard, toMode id: String, at index: Int? = nil) -> Int {
        var n = 0, at = index
        for app in draggedApps(pb) where addApp(app, toMode: id, at: at) { n += 1; at = at.map { $0 + 1 } }
        return n
    }
    func removeApp(_ app: String, fromMode id: String) {
        guard let i = modeIndex(id) else { return }
        modes[i]["apps"] = (modes[i]["apps"] as? [String] ?? []).filter { $0 != app }
    }
    /// Reorders within a mode (what dragging a row up or down will do). Out-of-range moves are ignored.
    func moveApp(inMode id: String, from: Int, to: Int) {
        guard let i = modeIndex(id) else { return }
        var list = modes[i]["apps"] as? [String] ?? []
        guard list.indices.contains(from) else { return }
        let app = list.remove(at: from); list.insert(app, at: min(max(to, 0), list.count))
        modes[i]["apps"] = list
    }
    /// Starts a mode: opens its apps, parks everything else. Refused during a session or a Quit All.
    @discardableResult
    func startMode(id: String) -> Bool {
        guard !focused, !clearing, let m = mode(id) else { return false }
        item.menu?.cancelTracking(); park(quit: !hideMode, mode: m); return true
    }

    @objc func newMode() {
        let ids = excluded.filter { path($0) != nil }
        guard !ids.isEmpty else {
            return tell("Tick the apps for this mode first", "In the Focus menu, tick the apps you want in the mode — say, your writing app and your browser — then choose New Mode again.")
        }
        guard let name = ask("New Mode", "Starting this mode keeps \(names(ids)) open (opening any that aren't running) and temporarily closes everything else.", placeholder: "Game design") else { return }
        createMode(name, apps: ids)
    }
    /// From the menu: start it, switch to it mid-session, or end it if it's the live one — the same as its key.
    @objc func startMode(_ s: NSMenuItem) { if let id = s.representedObject as? String { startOrSwitch(id) } }
    func startOrSwitch(_ id: String) {
        if !focused { startMode(id: id) } else if sessions.first?["modeID"] as? String == id { toggle() } else { switchMode(id: id) }
    }
    @objc func renameMode(_ s: NSMenuItem) {
        guard let id = s.representedObject as? String, let m = mode(id), let name = ask("Rename Mode", "", m["name"] as? String ?? "") else { return }
        renameMode(id, to: name)
    }
    @objc func updateMode(_ s: NSMenuItem) {
        let ids = excluded.filter { path($0) != nil }
        guard let id = s.representedObject as? String, let i = modeIndex(id), !ids.isEmpty else { return }
        modes[i]["apps"] = ids
    }
    @objc func deleteMode(_ s: NSMenuItem) { if let id = s.representedObject as? String { removeMode(id) } }
    @objc func renameSession(_ s: NSMenuItem) {
        guard sessions.indices.contains(s.tag) else { return }
        let current = sessions[s.tag]["name"] as? String ?? ""
        guard let name = ask("Rename Session", "", current, placeholder: "Essay draft") else { return }
        sessions[s.tag]["name"] = name
    }
    /// The apps a session KEPT open (what defines it). Older sessions saved before this was recorded have none.
    func kept(_ s: Session) -> [String] { (s["kept"] as? [String] ?? []).filter { path($0) != nil } }
    func keptNames(_ s: Session) -> String { kept(s).compactMap(path).map(appName).joined(separator: ", ") }
    /// For a title: three names at most, then "+N" ("Kept Unreal, Claude, Chrome +2").
    func keptShort(_ s: Session) -> String {
        let n = kept(s).compactMap(path).map(appName)
        return n.prefix(3).joined(separator: ", ") + (n.count > 3 ? " +\(n.count - 3)" : "")
    }
    @objc func sessionToMode(_ s: NSMenuItem) {
        guard sessions.indices.contains(s.tag), let name = ask("Save as Mode", "Starting this mode keeps \(keptNames(sessions[s.tag])) open and temporarily closes everything else.",
                                                               sessions[s.tag]["name"] as? String ?? "") else { return }
        modeFromSession(s.tag, name: name)
    }
    /// A mode = the apps that session kept open — never the ones it parked.
    @discardableResult
    func modeFromSession(_ n: Int, name: String) -> Bool {
        guard sessions.indices.contains(n) else { return false }
        let ids = kept(sessions[n]); guard !ids.isEmpty else { return false }
        createMode(name, apps: ids); return true
    }
    /// Up to three app icons, overlapped, for a mode's row.
    func stack(_ ids: [String]) -> NSImage {
        let icons = ids.prefix(3).compactMap(path).map { ws.icon(forFile: $0) }
        // always the width of three icons, so every mode's name starts in the same place however many apps it has
        let img = NSImage(size: NSSize(width: 30, height: 16), flipped: false) { _ in
            for (i, ic) in icons.enumerated().reversed() { ic.draw(in: NSRect(x: CGFloat(i) * 7, y: 0, width: 16, height: 16)) }
            return true
        }
        return img
    }

    /// The live session is sessions[0] while focused: opening it = End Session; it can't be deleted mid-session.
    func isLive(_ n: Int) -> Bool { focused && n == 0 }
    /// The live session's name — its mode's, or what you renamed it to. nil when unnamed or not in a session.
    var sessionName: String? { focused ? (sessions.first?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } : nil }
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

    /// How the app list is ordered. Clicking "Usage" cycles: as macOS lists them → most memory first → most used first
    /// (the apps you've kept open in the most sessions).
    var appSort: Int { get { store.integer(forKey: "appSort") % 3 } set { store.set(newValue % 3, forKey: "appSort") } }
    func sorted(_ list: [(String, String)]) -> [(String, String)] {
        switch appSort {
        case 1:
            func size(_ id: String) -> UInt64 { ws.runningApplications.first { $0.bundleIdentifier == id }.map(memory) ?? 0 }
            return list.sorted { size($0.0) > size($1.0) }
        case 2:
            var uses: [String: Int] = [:]
            for s in sessions { for id in kept(s) { uses[id, default: 0] += 1 } }
            return list.sorted { (uses[$0.0] ?? 0, appName($1.1)) > (uses[$1.0] ?? 0, appName($0.1)) }
        default: return list
        }
    }
    func cycleSort() {
        appSort += 1
        guard let m = item.menu else { return }
        RunLoop.main.perform(inModes: [.common, .eventTracking]) { [weak self] in self?.menuNeedsUpdate(m); self.map { $0.darken(m) } }   // redraw the open menu in the new order
    }
    /// The first line of the menu: whether a session is on, how many apps are in it and since when.
    var stateLine: String {
        guard focused, let live = sessions.first else { return "Focus" }
        let n = apps().filter { !isParked($0.bundleIdentifier ?? "") }.count
        let since = (live["date"] as? Date).map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) }
        return "Focus — \(displayName ?? "in session") (\(n) app\(n == 1 ? "" : "s")" + (since.map { ", since \($0)" } ?? "") + ")"
    }
    func menuNeedsUpdate(_ m: NSMenu) {
        // Submenus share this delegate only so they open dark (menuWillOpen). They build themselves; rebuilding one
        // here would fill it with a copy of the whole menu.
        guard m.supermenu == nil, m.identifier?.rawValue != "modeEdit" else { return }
        m.removeAllItems()
        @discardableResult
        func add(_ title: String, _ action: Selector?, image: NSImage? = nil, to menu: NSMenu? = nil) -> NSMenuItem {
            let i = (menu ?? m).addItem(withTitle: title, action: action, keyEquivalent: "")
            i.target = self; i.image = image
            return i
        }
        func header(_ t: String, tip: String? = nil, in menu: NSMenu? = nil) {
            let h = headingItem(t); h.toolTip = tip; (menu ?? m).addItem(h)      // the explanation shows on hover
        }
        /// A section's heading in the chosen style. `name` alone when Minimalist; "name — few words" when Normal;
        /// Verbose adds `more`, a sentence, underneath. `optional` headings vanish altogether when Minimalist.
        func section(_ name: String, _ few: String, _ more: String, optional: Bool = false) {
            let style = headingStyle
            if style == 0 { if !optional { header(name) }; return }
            header(name + " — " + few)
            if style == 2 { let i = NSMenuItem(title: more, action: nil, keyEquivalent: ""); i.view = Explain(more); i.isEnabled = false; m.addItem(i) }
        }
        func view(_ v: NSView, in menu: NSMenu? = nil) { let i = NSMenuItem(); i.view = v; (menu ?? m).addItem(i) }

        mem = memoryByPid()
        let quit = NSMenuItem(title: "Quit", action: nil, keyEquivalent: ""); quit.view = QuitRow { [unowned self] in self.bye() }
        m.addItem(quit)
        if let status, !status.hasPrefix("Waiting") { header(status) }   // the waiting app has its own line below
        if focused, let shot = sessions.first?["shot"] as? String, let img = NSImage(contentsOfFile: shot) {
            header("What you were doing — click to open")
            let w = menuWidth - 28, h = (w * img.size.height / max(img.size.width, 1)).rounded()
            view(Thumb(img, NSSize(width: w, height: h)) { [unowned self] in self.ws.open(URL(fileURLWithPath: shot)) })
            m.addItem(.separator())
        }

        // Keep open — this session's picks.
        var running = apps().compactMap { a in a.bundleIdentifier.flatMap { id in a.bundleURL.map { (id, $0.path) } } }
        running = sorted(running)
        func columns() -> ColumnHeader { let c = ColumnHeader(); c.onUsage = { [unowned self] in self.cycleSort() }; return c }
        if focused {
            // In a session the rows ARE the session: ticked = in it, open. Click to take one out now, or put it back.
            view(columns())
            let stuckIDs = Set(waiting.compactMap(\.bundleIdentifier))
            for (id, p) in running {
                let size = ws.runningApplications.first { $0.bundleIdentifier == id }.map(memory) ?? 0
                let parked = isParked(id)
                let detail = stuckIDs.contains(id) ? "waiting to save" : parked ? "leaving…" : (size > 0 ? gb(size) : "")
                view(AppRow(appName(p), appIcon(p), detail: detail, on: !parked, target: "your session") { [unowned self] in
                    if self.isParked(id) { self.bringBack(id); return true } else { self.parkNow(id); return false }
                })
            }
            let parkedAway = parkedEntries.compactMap { e -> (String, String)? in
                guard let p = e["path"] as? String, let id = (e["id"] as? String) ?? Bundle(path: p)?.bundleIdentifier,
                      !running.contains(where: { $0.0 == id }) else { return nil }
                return (id, p)
            }
            if !parkedAway.isEmpty {
                m.addItem(.separator())
                header("Apps Outside Session")
                for (id, p) in parkedAway {
                    view(AppRow(appName(p), appIcon(p), on: false, target: "your session") { [unowned self] in self.bringBack(id); return true })
                }
            }
        } else {
            section("Keep open this session", "click to choose",
                    "Tick the apps you want to keep. Everything else closes when the session starts and comes back when it ends.", optional: true)
            view(columns())
            let idle = excluded.filter { id in !running.contains { $0.0 == id } && !neverClose.contains(id) }.compactMap { id in path(id).map { (id, $0) } }
            for (id, p) in running + idle {
                let size = ws.runningApplications.first { $0.bundleIdentifier == id }.map(memory) ?? 0
                let detail = size > 0 ? gb(size) : ""
                view(AppRow(appName(p), appIcon(p), detail: detail, on: excluded.contains(id), target: "your session") { [unowned self] in self.flip(\.excluded, id) })
            }
        }

        // Critical system processes — never quit or hidden by Focus. Click to take one off; it moves up next time.
        m.addItem(.separator())
        section("Critical System Processes", "never quit", "These apps are never quit or hidden, in any session. Change the list with Add or remove.")
        for id in neverClose {
            guard let p = path(id) else { continue }
            let row = AppRow(appName(p), appIcon(p), on: true, onMark: "lock.circle.fill") { true }   // changed only via Add or remove…
            row.inert = true; view(row)
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
            for a in stuck {                                     // never stuck: show it, keep it, or (asked first) force it
                let row = add("\(a.localizedName ?? "An app") is waiting for you to save", nil, image: symbol("exclamationmark.bubble")), sm = NSMenu()
                sm.autoenablesItems = false
                let id = a.bundleIdentifier ?? ""
                add("Show Its Save Prompt", #selector(showPrompt(_:)), image: symbol("macwindow"), to: sm).representedObject = id
                add("Keep It in the Session", #selector(keepStuck(_:)), image: symbol("checkmark.circle"), to: sm).representedObject = id
                sm.addItem(.separator())
                let force = add("Force Quit — Unsaved Changes Lost…", #selector(forceStuck(_:)), image: symbol("bolt.circle", [theme.hazard]), to: sm)
                force.representedObject = id
                force.attributedTitle = NSAttributedString(string: force.title, attributes: [.foregroundColor: theme.hazard, .font: NSFont.menuFont(ofSize: 0)])
                row.submenu = sm
            }
        }

        m.addItem(.separator())
        if showColourTip {
            add("Make the icon yours — pick its colours…", #selector(colourTip), image: Focus.rainbow)
            m.addItem(.separator())
        }
        // Modes — the user's named sets of apps.
        section("Modes", "frequently used sessions", "A mode is a set of apps you keep open. Click one to start it, or press its number. Right-click to edit it.")
        // The builder for a new mode: pick apps, optionally name it, create. Offered under the modes and in Edit Modes.
        func builderMenu() -> NSMenu {
        let nmm = NSMenu()
        nmm.autoenablesItems = false
        let nextKey = nextModeKey.map { label(forMode: $0) }
        nmm.addItem(headingItem("Its apps — click to add"))
        // open apps first, then apps your sessions kept, then anything already picked
        var seenIDs = Set<String>()
        let pool = (running.map(\.0) + sessions.flatMap { self.kept($0) } + draftApps).filter { seenIDs.insert($0).inserted }
        for id in pool.prefix(14) {
            guard let p = path(id) else { continue }
            let v = NSMenuItem(); v.view = AppRow(appName(p), appIcon(p), on: draftApps.contains(id), target: "this mode") { [unowned self] in
                if let i = self.draftApps.firstIndex(of: id) { self.draftApps.remove(at: i); return false }
                self.draftApps.append(id); return true
            }
            nmm.addItem(v)
        }
        add("Add App…", #selector(addAppToDraft), image: symbol("plus.app"), to: nmm)
        nmm.addItem(.separator())
        // No name needed: it takes the next number. A name is optional (Return creates it too).
        let nameIt = NSMenuItem(); nameIt.view = InlineNameField("", placeholder: "Name (optional)", symbolName: "pencil") { [unowned self] v in
            self.createMode(v, apps: self.draftApps); self.draftApps = []
        }
        nmm.addItem(nameIt)
        let make = add("Create Mode" + (nextKey.map { "  " + $0 } ?? ""), #selector(createDraftMode), image: symbol("checkmark.circle"), to: nmm)
        make.isEnabled = !draftApps.isEmpty
        return nmm
        }
        // Building one mode's edit menu: its name, its apps, its shortcut, delete. Used by right-click and by Edit Modes.
        func editMenu(_ md: [String: Any]) -> NSMenu {
            let ids = md["apps"] as? [String] ?? [], name = md["name"] as? String ?? "Mode", mid = md["id"] as? String ?? ""
                let sm = NSMenu()
                sm.autoenablesItems = false
                let digit = md["key"] as? Int
                let nameRow = NSMenuItem(); nameRow.view = InlineNameField(name, placeholder: "Mode name", symbolName: "pencil") { [unowned self] v in self.renameMode(mid, to: v) }
                sm.addItem(nameRow)
                // Its apps, ticked; apps open right now that aren't in it, unticked. Click to put one in or take it out.
                sm.addItem(headingItem("Keeps open — click to add or remove"))
                let others = running.map(\.0).filter { !ids.contains($0) }
                for id in ids + others {
                    guard let p = path(id) else { continue }
                    let v = NSMenuItem(); v.view = AppRow(appName(p), appIcon(p), on: ids.contains(id), target: "this mode") { [unowned self] in
                        let inIt = (self.mode(mid)?["apps"] as? [String] ?? []).contains(id)
                        if inIt { self.removeApp(id, fromMode: mid) } else { self.addApp(id, toMode: mid) }
                        return !inIt
                    }
                    sm.addItem(v)
                }
                add("Add App…", #selector(addAppToMode(_:)), image: symbol("plus.app"), to: sm).representedObject = mid
                sm.addItem(.separator())
                let kItem = add(digit.map { "Shortcut: " + label(forMode: $0) } ?? "Shortcut: none", nil, image: symbol("keyboard"), to: sm), kMenu = NSMenu()
                let none = add("None", #selector(pickModeKey(_:)), to: kMenu); none.tag = -1; none.representedObject = mid; none.state = digit == nil ? .on : .off
                for d in [1, 2, 3, 4, 5, 6, 7, 8, 9, 0] {
                    let owner = modeForKey(d).flatMap { $0["id"] as? String == mid ? nil : $0["name"] as? String }
                    let i = add(label(forMode: d) + (owner.map { "   (now \($0))" } ?? ""), #selector(pickModeKey(_:)), to: kMenu)
                    i.tag = d; i.representedObject = mid; i.state = digit == d ? .on : .off
                }
                if let digit, takenModeKeys.contains(digit) { add("⚠︎ " + label(forMode: digit) + " is taken by another app — pick another", nil, to: kMenu).isEnabled = false }
                kItem.submenu = kMenu
                let use = add("Use Ticked Apps", #selector(updateMode(_:)), image: symbol("checklist"), to: sm)
                use.representedObject = mid; use.isEnabled = !excluded.isEmpty
                add("Delete", #selector(deleteMode(_:)), image: symbol("trash"), to: sm).representedObject = mid
            sm.identifier = NSUserInterfaceItemIdentifier("modeEdit"); sm.delegate = self
            return sm
        }
        // Each mode is one click: start it (or move the live session to it); the live one is ticked and ends on click.
        for md in modes {
            let ids = md["apps"] as? [String] ?? [], name = md["name"] as? String ?? "Mode", mid = md["id"] as? String ?? ""
            let digit = md["key"] as? Int, live = focused && sessions.first?["modeID"] as? String == mid
            let go = add(name, #selector(startMode(_:)))
            go.representedObject = mid; go.isEnabled = !clearing         // (the row draws its own tick: a state mark here would shift every icon in the menu)
            if let digit { go.keyEquivalent = String(digit); go.keyEquivalentModifierMask = NSEvent.ModifierFlags(carbon: modeMods) }
            go.view = ModeRow(name, stack(ids), key: digit.map { label(forMode: $0) } ?? "", live: live, enabled: !clearing,
                              start: { [unowned self] in self.startOrSwitch(mid) }, edit: { editMenu(md) })
        }
        add("Create New Mode", nil, image: symbol("plus.circle")).submenu = builderMenu()      // under your modes; first when there are none
        let editModes = modes.isEmpty ? nil : add("Edit Modes", nil, image: symbol("slider.horizontal.3")), em = NSMenu()
        add("Add New Mode", nil, image: symbol("plus.circle"), to: em).submenu = builderMenu()
        em.addItem(.separator())
        for md in modes {
            let row = add(md["name"] as? String ?? "Mode", nil, image: stack(md["apps"] as? [String] ?? []), to: em)
            row.submenu = editMenu(md)
        }
        editModes?.submenu = em
        let ideas = suggestedModes()
        if !ideas.isEmpty {
            let sug = add("Suggested Modes", nil, image: symbol("sparkles")), sgm = NSMenu()
            sgm.addItem(headingItem("Click to add — from the apps you use"))
            for idea in ideas {
                let i = add(idea.name, #selector(addSuggested(_:)), image: stack(idea.apps), to: sgm)
                i.representedObject = idea.name; i.toolTip = names(idea.apps)
            }
            sug.submenu = sgm
        }
        m.addItem(.separator())

        if !sessions.isEmpty {
            let past = add("Past sessions", nil, image: symbol("clock.arrow.circlepath")), sub = NSMenu()
            for (n, s) in sessions.enumerated() {
                let list = s["apps"] as? [[String: Any]] ?? []
                let date = (s["date"] as? Date).map { when.string(from: $0) } ?? "?"
                let keptList = keptShort(s)
                let title = (s["name"] as? String).map { "\($0) · \(date)" }
                    ?? (keptList.isEmpty ? "\(date) · \(apps(list.count))" + ((s["kind"] as? String).map { " · " + $0 } ?? "") : "Kept \(keptList) · \(date)")
                let i = add(title + (isLive(n) ? " · now" : ""), nil, to: sub), one = NSMenu()
                one.autoenablesItems = false
                // Hovering a session opens this: its snapshot first, so you see where you were.
                if let shot = s["shot"] as? String, FileManager.default.fileExists(atPath: shot), let img = NSImage(contentsOfFile: shot) {
                    let w = menuWidth - 28, h = (w * img.size.height / max(img.size.width, 1)).rounded()
                    let v = NSMenuItem(); v.view = Thumb(img, NSSize(width: w, height: h)) { [unowned self] in self.ws.open(URL(fileURLWithPath: shot)) }
                    one.addItem(v); one.addItem(.separator())
                }
                if !kept(s).isEmpty {
                    one.addItem(headingItem("Kept open"))
                    for id in kept(s) { if let p = path(id) { add(appName(p), nil, image: appIcon(p), to: one) } }
                    one.addItem(headingItem("Temporarily closed"))
                }
                for p in list.compactMap({ $0["path"] as? String }) { add(appName(p), nil, image: appIcon(p), to: one) }
                one.addItem(.separator())
                add(isLive(n) ? "End Session and Reopen" : "Open all", #selector(reopen), image: symbol("arrow.up.forward.app"), to: one).tag = n
                let rn = NSMenuItem(); rn.view = InlineNameField(s["name"] as? String ?? "", placeholder: "Name this session", symbolName: "pencil") { [unowned self] v in
                    if self.sessions.indices.contains(n) { self.sessions[n]["name"] = v }
                }
                one.addItem(rn)
                let sv = NSMenuItem(); sv.view = InlineNameField("", placeholder: kept(s).isEmpty ? "Save as mode (older sessions can't)" : "Save as mode — name it, press Return",
                                                                symbolName: "square.stack", enabled: !kept(s).isEmpty) { [unowned self] v in self.modeFromSession(n, name: v) }
                one.addItem(sv)          // a mode is the kept apps; older sessions didn't record them
                let del = add("Delete", #selector(forget), image: symbol("trash"), to: one)
                del.tag = n; del.isEnabled = !isLive(n)                 // deleting the live session would lose its restore
                i.submenu = one
            }
            past.submenu = sub
        }
        let tools = add("Tools", nil, image: symbol("wrench.and.screwdriver")), tm = NSMenu()
        tm.autoenablesItems = false
        let busy = focused || clearing
        tm.addItem(headingItem("Analyse performance"))
        add("Open Activity Monitor", #selector(openActivityMonitor), image: symbol("waveform.path.ecg"), to: tm)
        add("Open System Settings", #selector(openSystemSettings), image: symbol("gearshape.2"), to: tm)
        tm.addItem(.separator())
        tm.addItem(headingItem("Quit Unresponsive Apps"))
        add("Quit All Apps…", #selector(quitAllApps), image: symbol("xmark.circle"), to: tm).isEnabled = !busy
        add("Quit All Apps & Restart Mac…", #selector(quitAllRestart), image: symbol("arrow.clockwise.circle"), to: tm).isEnabled = !busy
        let fq = add("Force Quit All Apps…", #selector(forceQuitAllApps), image: symbol("bolt.circle", [theme.hazard]), to: tm)
        fq.isEnabled = !busy
        if !busy { fq.attributedTitle = NSAttributedString(string: fq.title, attributes: [.foregroundColor: theme.hazard, .font: NSFont.menuFont(ofSize: 0)]) }
        tm.addItem(.separator())
        let kept = neverClose.compactMap(path).map(appName)
        add(busy ? "End the session first" : kept.isEmpty ? "Add apps to Critical System Processes to keep them" : "Keeps " + kept.joined(separator: ", "), nil, to: tm).isEnabled = false
        tools.submenu = tm
        let settings = add("Settings", nil, image: symbol("gearshape")), sub = NSMenu()
        let two = { (a: NSColor?, b: NSColor?) -> NSImage in      // a mini icon in two colours, for menu rows
            let g = glyph(0, ring: a ?? .labelColor, dot: b ?? a ?? .labelColor); g.size = NSSize(width: 16, height: 16); return g
        }
        let look = add("Appearance", nil, image: symbol("paintbrush"), to: sub), am = NSMenu()
        am.minimumWidth = menuWidth
        am.addItem(headingItem("Icon"))
        let picker = NSMenuItem(); picker.view = IconGrid(iconStyleSetting, ring: ringColor, dot: dotColor) { [unowned self] st in self.iconStyleSetting = st }
        am.addItem(picker)
        let colour = add("Icon Colour", nil, image: two(ringColor, dotColor), to: am), cm = NSMenu()
        cm.minimumWidth = 300
        func hdr(_ t: String) { cm.addItem(headingItem(t)) }
        hdr("Presets")
        let def = add("White", #selector(pickPreset(_:)), image: swatch(nil), to: cm); def.representedObject = ["", ""]
        def.state = iconColor.isEmpty && iconColor2.isEmpty ? .on : .off
        let acc = hexString(.controlAccentColor)
        let sys = add("System Accent", #selector(pickPreset(_:)), image: two(.controlAccentColor, .controlAccentColor), to: cm)
        sys.representedObject = [acc, ""]; sys.state = iconColor == acc && iconColor2.isEmpty ? .on : .off
        for (name, a, b) in theme.iconPresets {
            let i = add(name, #selector(pickPreset(_:)), image: two(hexColor(a), hexColor(b)), to: cm)
            i.representedObject = [a, a == b ? "" : b]
            i.state = iconColor == a && (iconColor2 == b || (a == b && iconColor2.isEmpty)) ? .on : .off
        }
        hdr("Evangelion")
        for (name, a, b) in theme.evaPresets {
            let i = add(name, #selector(pickPreset(_:)), image: two(hexColor(a), hexColor(b)), to: cm)
            i.representedObject = [a, b]; i.state = iconColor == a && iconColor2 == b ? .on : .off
        }
        hdr("Your Schemes")
        for (k, sc) in customSchemes.enumerated() {
            let i = add(sc[0], #selector(pickPreset(_:)), image: two(hexColor(sc[1]), hexColor(sc[2]) ?? hexColor(sc[1])), to: cm)
            i.representedObject = [sc[1], sc[2]]; i.state = iconColor == sc[1] && iconColor2 == sc[2] ? .on : .off
            let del = add("Delete “\(sc[0])”", #selector(deleteScheme(_:)), image: symbol("trash"), to: cm)   // hold ⌥ to see it
            del.tag = k; del.isAlternate = true; del.keyEquivalentModifierMask = .option
        }
        add("Save Current Colours as Scheme…", #selector(saveScheme), image: symbol("plus.circle"), to: cm).isEnabled = !iconColor.isEmpty
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
        am.addItem(.separator())
        let hs = add("Headings", nil, image: symbol("text.alignleft"), to: am), hsm = NSMenu()
        for (k, n) in ["Minimalist", "Normal", "Verbose"].enumerated() {
            let i = add(n, #selector(pickHeadingStyle(_:)), to: hsm); i.tag = k; i.state = headingStyle == k ? .on : .off
        }
        hs.submenu = hsm
        let nb = add("Menu Bar Name", nil, image: symbol("character.cursor.ibeam"), to: am), nbm = NSMenu()
        let sample = displayName ?? modes.first?["name"] as? String ?? "AI"
        for (k, f) in Focus.nameStyles.enumerated() {
            let i = add(f(sample), #selector(pickNameStyle(_:)), to: nbm); i.tag = k; i.state = showNameInMenuBar && menuBarNameStyle == k ? .on : .off
        }
        let io = add("Icon only", #selector(pickNameStyle(_:)), to: nbm); io.tag = -1; io.state = showNameInMenuBar ? .off : .on
        nb.submenu = nbm
        am.addItem(.separator())
        am.addItem(headingItem("Animation Speed"))
        let dial = NSMenuItem(); dial.view = SpeedDial(animSpeed) { [unowned self] s in self.animSpeed = s }; am.addItem(dial)
        look.submenu = am
        let keys = add("Shortcuts", nil, image: symbol("keyboard"), to: sub), km = NSMenu()
        km.autoenablesItems = false; km.minimumWidth = 300
        km.addItem(headingItem("Start / End Session"))
        for c in modifierChoices {
            let i = add(c.label + "F  ·  " + c.clash, #selector(pickSessionKey(_:)), to: km); i.tag = c.mods; i.state = c.mods == sessionMods ? .on : .off
        }
        if sessionKeyTaken { add("⚠︎ " + label(sessionMods) + "F is taken by another app — pick another", nil, to: km).isEnabled = false }
        km.addItem(.separator())
        km.addItem(headingItem("Open This Menu"))
        for c in modifierChoices {
            let i = add(c.label + "E", #selector(pickMenuKey(_:)), to: km); i.tag = c.mods; i.state = c.mods == menuMods ? .on : .off
        }
        if menuKeyTaken { add("⚠︎ " + label(menuMods) + "E is taken by another app — pick another", nil, to: km).isEnabled = false }
        km.addItem(.separator())
        km.addItem(headingItem("Modes — this plus a number you give each mode"))
        for c in modeModifierChoices {
            let i = add(c.label + "1  ·  " + c.clash, #selector(pickModeMods(_:)), to: km); i.tag = c.mods; i.state = c.mods == modeMods ? .on : .off
        }
        keys.submenu = km
        let behave = add("Behaviour", nil, image: symbol("switch.2"), to: sub), bm = NSMenu()
        bm.autoenablesItems = false
        let sw = add("App Open/Close Speed", nil, image: symbol("arrow.left.arrow.right"), to: bm), swm = NSMenu()
        swm.autoenablesItems = false
        add("Safety first (closes all apps carefully, slower)", #selector(switchingCareful), to: swm).state = fastSwitching ? .off : .on
        add("Speed first (opens/closes apps immediately)", #selector(switchingFast), to: swm).state = fastSwitching ? .on : .off
        sw.submenu = swm
        let ho = add("Hide Instead of Quit", nil, image: symbol("eye.slash"), to: bm), hom = NSMenu()
        hom.minimumWidth = menuWidth
        hom.addItem(headingItem("Ticked apps are hidden, not quit — back exactly as they were"))
        let dockApps = ws.runningApplications.filter { $0.activationPolicy == .regular && !system($0) }.compactMap(\.bundleIdentifier)
        var listed = Set<String>()
        for id in hideOnly + dockApps where listed.insert(id).inserted {
            guard let p = path(id) else { continue }
            view(AppRow(appName(p), appIcon(p), on: hideOnly.contains(id), onMark: "eye.slash.circle.fill") { [unowned self] in self.flip(\.hideOnly, id) }, in: hom)
        }
        hom.addItem(.separator())
        add("Hide every app", #selector(hiding), to: hom).state = hideMode ? .on : .off
        ho.submenu = hom
        if CGPreflightScreenCaptureAccess() {
            add("Take a snapshot when a session starts", #selector(snaps), to: bm).state = snapshots ? .on : .off
        } else {
            add("Allow snapshots… (asks for Screen Recording once)", #selector(snaps), image: symbol("camera"), to: bm)
        }
        behave.submenu = bm
        sub.addItem(.separator())
        // On or off is shown by the icon itself, so these two line up with the icons above (a tick mark would sit in its own column).
        let onOff = { (on: Bool) in on ? symbol("checkmark.circle.fill") : symbol("circle") }
        add("Reopen windows as they were", #selector(windows), image: onOff(keepWindows), to: sub)
        add("Open at login", #selector(login), image: onOff(SMAppService.mainApp.status == .enabled), to: sub)
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
        let mark = NSMenuItem(title: Maker.text, action: nil, keyEquivalent: ""); mark.view = Maker(); m.addItem(mark)   // the last line of the menu
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
        let mark = painted(classicLens(0), markColor ?? theme.hudInk, NSSize(width: 512, height: 512))!   // the app logo: the original lens, unchanged
        NSGraphicsContext.current!.cgContext.draw(mark, in: tile.insetBy(dx: 120 * u, dy: 120 * u))
        NSGraphicsContext.restoreGraphicsState()
        return rep
}

/// `Focus --render-banner FILE`: the top and bottom of the menu during a named session, drawn off-screen.
if let i = CommandLine.arguments.firstIndex(of: "--render-banner"), CommandLine.arguments.count > i + 1 {
    let banner = SessionBanner(title: "Game design", detail: "Mode · started 21:48 · keeps Unreal Editor, Claude")
    let button = BigButton(title: { "End Game design" }, caption: { "Ending the session will reopen 6 apps exactly as they were." }, action: {})
    let w = Int(menuWidth), h = Int(banner.frame.height + button.frame.height + 20)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w * 2, pixelsHigh: h * 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: w, height: h)
    NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        theme.menuBackground.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.saveGState(); ctx.translateBy(x: 0, y: CGFloat(h) - banner.frame.height); banner.draw(banner.bounds); ctx.restoreGState()
        ctx.saveGState(); ctx.translateBy(x: 0, y: 4); button.draw(button.bounds); ctx.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
    }
    try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    exit(0)
}

/// `Focus --render-rows FILE`: the menu's headings, column titles, app rows and mode rows drawn off-screen, stacked
/// as they sit in the menu — for checking sizes and alignment without opening the menu.
if let i = CommandLine.arguments.firstIndex(of: "--render-rows"), CommandLine.arguments.count > i + 1 {
    let ws = NSWorkspace.shared
    func ic(_ id: String) -> NSImage { let im = ws.urlForApplication(withBundleIdentifier: id).map { ws.icon(forFile: $0.path) } ?? NSImage(); im.size = NSSize(width: 16, height: 16); return im }
    let stackIcon = NSImage(size: NSSize(width: 23, height: 16), flipped: false) { _ in
        ic("com.apple.Terminal").draw(in: NSRect(x: 7, y: 0, width: 16, height: 16)); ic("com.apple.Safari").draw(in: NSRect(x: 0, y: 0, width: 16, height: 16)); return true }
    let hovered = ModeRow("Mode 2", stackIcon, key: "⌘2", live: false, enabled: true, start: {}, edit: { NSMenu() }); hovered.hover = true
    let rows: [NSView] = [
        QuitRow {}, ColumnHeader(),
        AppRow("Safari", ic("com.apple.Safari"), detail: "2.4 GB", on: true) { true },
        AppRow("Notes", ic("com.apple.Notes"), detail: "310 MB", on: false) { true },
        Heading("Modes — frequently used sessions"),
        ModeRow("AI", stackIcon, key: "⌘1", live: true, enabled: true, start: {}, edit: { NSMenu() }), hovered,
        BigButton(title: { "Start New Session" }, caption: { "Starting a new session will save and quit 6 apps, freeing about 10.7 GB of RAM." }, action: {}), Maker(),
    ]
    let w = Int(menuWidth), h = Int(rows.reduce(0) { $0 + $1.frame.height }) + 12
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w * 2, pixelsHigh: h * 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: w, height: h)
    NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        theme.menuBackground.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        let ctx = NSGraphicsContext.current!.cgContext
        var y = CGFloat(h) - 6
        for v in rows {
            v.frame.size.width = menuWidth; y -= v.frame.height
            ctx.saveGState(); ctx.translateBy(x: 0, y: y); v.draw(v.bounds); ctx.restoreGState()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    exit(0)
}

/// `Focus --render-icons FILE`: every icon design drawn off-screen to a PNG (rows: white, then purple/green; columns:
/// at rest, mid-animation, focused) — for checking designs without touching the screen.
if let i = CommandLine.arguments.firstIndex(of: "--render-icons"), CommandLine.arguments.count > i + 1 {
    let cell: CGFloat = 64, styles = IconStyle.allCases, phases: [CGFloat] = [0, 0.5, 1]
    let palettes: [(NSColor?, NSColor?)] = [(nil, nil), (hexColor("A78BFA"), hexColor("5FD7AF"))]
    let w = Int(cell) * phases.count * palettes.count + 40, h = Int(cell) * styles.count + 20
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    theme.menuBackground.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
    for (row, st) in styles.enumerated() {
        for (pi, pal) in palettes.enumerated() {
            for (ci, ph) in phases.enumerated() {
                let x = CGFloat(pi * phases.count + ci) * cell + CGFloat(pi) * 40 + 10, y = CGFloat(h) - CGFloat(row + 1) * cell - 10
                glyph(ph, ring: pal.0 ?? .white, dot: pal.1 ?? pal.0 ?? .white, style: st).draw(in: NSRect(x: x + 14, y: y + 14, width: 36, height: 36))
            }
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    // Second file: the template lens tinted as the menu bar would, light and dark.
    let tw = Int(cell) * 3, trep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: tw, pixelsHigh: Int(cell) * 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: trep)
    for (k, pair) in [(NSColor(white: 0.93, alpha: 1), NSColor.black), (NSColor(white: 0.1, alpha: 1), NSColor.white)].enumerated() {
        pair.0.setFill(); NSRect(x: 0, y: CGFloat(k) * cell, width: CGFloat(tw), height: cell).fill()
        for (ci, ph) in phases.enumerated() {
            painted(glyph(ph, style: .lens), pair.1, NSSize(width: 36, height: 36)).map { cg in
                NSGraphicsContext.current?.cgContext.draw(cg, in: CGRect(x: CGFloat(ci) * cell + 14, y: CGFloat(k) * cell + 14, width: 36, height: 36))
            }
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    try? trep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1] + ".template.png"))
    exit(0)
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
/// `Focus --render-pill FILE start|end|switch`: the session show drawn off-screen as a filmstrip, to check it by eye.
if let i = CommandLine.arguments.firstIndex(of: "--render-pill"), CommandLine.arguments.count > i + 2 {
    let kind = CommandLine.arguments[i + 2], ws = NSWorkspace.shared
    let ic = { (ids: [String]) in ids.compactMap { ws.urlForApplication(withBundleIdentifier: $0) }.map { ws.icon(forFile: $0.path) } }
    let out = ic(["com.apple.iWork.Keynote", "com.apple.systempreferences", "com.apple.Preview"]), inn = ic(["com.apple.Terminal", "com.apple.TextEdit"])
    let p = SessionPill(); p.film = CommandLine.arguments[i + 1]
    p.filmstrip = kind == "end" ? [0.1, 0.25, 0.45, 0.65, 0.85, 1.0] : [0.12, 0.3, 0.42, 0.55, 0.75, 0.95, 1.15, 1.35]
    let s = (NSScreen.main ?? NSScreen.screens[0]).frame, tgt = NSPoint(x: s.midX + 260, y: 300)
    p.play(start: kind != "end", icons: out, incoming: kind == "switch" ? inn : [], target: tgt, label: kind == "start" ? "Programming" : "AI")
    exit(0)
}
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
    steps.append(("24. animation speed: Normal is the default and keeps the original timing; Slow/Fast change only the holds", { done in
        let d = UserDefaults(suiteName: suite)!
        d.removeObject(forKey: "animSpeed")
        let normalDefault = t.animSpeed == .normal && t.animSpeed.hold == (0.24, 0.02)
        t.animSpeed = .slow; let slow = t.animSpeed.hold.start > 0.24
        t.animSpeed = .fast; let fast = t.animSpeed.hold.start < 0.24
        let m = NSMenu(); t.menuNeedsUpdate(m)
        let look = m.items.first { $0.title == "Settings" }?.submenu?.items.first { $0.title == "Appearance" }?.submenu
        let hasColour = look?.items.contains { $0.title == "Icon Colour" } == true
        let hasDial = look?.items.contains { $0.view is SpeedDial } == true
        d.removeObject(forKey: "animSpeed")
        done(normalDefault && slow && fast && hasColour && hasDial,
             "default Normal with hold 0.24 s / 0.02 s: \(normalDefault); slow longer: \(slow); fast shorter: \(fast); Appearance has Icon Colour: \(hasColour) and the dial: \(hasDial)")
    }))
    steps.append(("32. icon picker: hovering a design plays it back and forth (rest → in session with hit stop → back); leaving stops it; 20 designs", { done in
        let g = IconGrid(.lens, ring: nil, dot: nil) { _ in }
        g.setHover(.enso)
        let started = g.anim?.isValid == true
        g.animStart = Date().addingTimeInterval(-0.95); let (tHit, kHit) = g.hoverPhase()      // landing: in session, popping
        g.animStart = Date().addingTimeInterval(-0.2);  let (tRest, _) = g.hoverPhase()        // at rest
        g.animStart = Date().addingTimeInterval(-2.0);  let (tBack, _) = g.hoverPhase()        // on its way back
        let timer = g.anim; g.setHover(nil)
        let stopped = timer?.isValid == false && g.anim == nil
        let count = IconStyle.allCases.count
        done(started && tHit == 1 && kHit > 1 && tRest == 0 && tBack > 0 && tBack < 1 && stopped && count == 20,
             "starts: \(started); landing t=\(tHit) scale=\(kHit); rest t=\(tRest); returning t=\(tBack); stops: \(stopped); designs: \(count)")
    }))
    steps.append(("33. colour schemes: the Evangelion pairs are listed by name; a user can save, pick and delete their own; the originals stay", { done in
        func colourMenu() -> NSMenu? {
            let m = NSMenu(); t.menuNeedsUpdate(m)
            return m.items.first { $0.title == "Settings" }?.submenu?.items.first { $0.title == "Appearance" }?.submenu?.items.first { $0.title == "Icon Colour" }?.submenu
        }
        t.store.removeObject(forKey: "customSchemes")
        let titles = colourMenu()?.items.map(\.title) ?? []
        let eva = ["UNIT 01", "Asuka", "Rei", "Shinji", "Misato", "Kaworu", "Pen Pen"].allSatisfy(titles.contains)
        let originals = ["Purple & Green", "Pink & Teal", "Violet & Gold", "Teal & Pink", "All Purple"].allSatisfy(titles.contains)
        t.iconColor = "123456"; t.iconColor2 = "ABCDEF"; t.addScheme("Night shift")
        let listed = colourMenu()?.items.first { $0.title == "Night shift" }
        t.iconColor = ""; t.iconColor2 = ""
        if let l = listed { t.pickPreset(l) }
        let picked = t.iconColor == "123456" && t.iconColor2 == "ABCDEF"
        let del = colourMenu()?.items.first { $0.title == "Delete “Night shift”" && $0.isAlternate }
        if let x = del { t.deleteScheme(x) }
        let gone = t.customSchemes.isEmpty && colourMenu()?.items.contains { $0.title == "Night shift" } == false
        t.iconColor = ""; t.iconColor2 = ""; t.store.removeObject(forKey: "customSchemes")
        done(eva && originals && listed != nil && picked && del != nil && gone,
             "Evangelion listed: \(eva); originals kept: \(originals); saved scheme listed: \(listed != nil); picking it applies it: \(picked); ⌥ delete: \(del != nil); deleted: \(gone)")
    }))
    steps.append(("34. the menu has no state line; its first row is Quit, at the top right", { done in
        let m = NSMenu(); t.menuNeedsUpdate(m)
        let first = m.items.first?.title ?? ""
        done(m.items.first?.view is QuitRow && !m.items.contains { $0.title.hasPrefix("Focus —") }, "first row is Quit: '\(first)'")
    }))
    steps.append(("35. modes: suggestions use only installed apps (Web Only = the default browser); adding one makes a real mode and it leaves the list; a mode's apps can be added and removed; Temporarily Closed wording", { done in
        t.modes = []
        let ideas = t.suggestedModes()
        let web = t.suggestedModes(limit: 9).first { $0.name == "Web Only" }
        let browser = t.defaultBrowser
        let webOK = browser != nil && web?.apps == [browser!]
        let allInstalled = ideas.allSatisfy { $0.apps.allSatisfy { t.path($0) != nil } && !$0.apps.isEmpty } && ideas.count <= 3
        let it = NSMenuItem(); it.representedObject = "Web Only"; t.addSuggested(it)
        let made = t.modes.first { $0["name"] as? String == "Web Only" }
        let gone = !t.suggestedModes(limit: 9).contains { $0.name == "Web Only" }
        let mid = made?["id"] as? String ?? ""
        let added = t.addApp(edit, toMode: mid); t.removeApp(browser ?? "", fromMode: mid)
        let apps = t.mode(mid)?["apps"] as? [String] ?? []
        let edited = added && apps == [edit]
        let m = NSMenu(); t.menuNeedsUpdate(m)
        let row = m.items.first { $0.title == "Edit Modes" }?.submenu?.items.first { $0.title == "Web Only" }?.submenu
        let rows = row?.items.contains { $0.view is AppRow } == true && row?.items.contains { $0.title == "Add App…" } == true
        let sugMenu = m.items.first { $0.title == "Suggested Modes" }
        t.modes = []
        done(webOK && allInstalled && made != nil && gone && edited && rows && (ideas.count <= 1 || sugMenu != nil),
             "suggestions \(ideas.map { "\($0.name): \(t.names($0.apps))" }); Web Only = default browser: \(webOK); all apps installed: \(allInstalled); added as a mode: \(made != nil), then leaves the list: \(gone); add/remove apps: \(edited); mode menu has app rows + Add App: \(rows)")
    }))
    steps.append(("36. mode shortcuts: each new mode takes the next number; a digit belongs to one mode; the row shows it; the modifier is a Setting; a self-test never takes the keys", { done in
        t.modes = []
        let a = t.createMode("Web", apps: [calc]), b = t.createMode("Games", apps: [edit])
        let noneYet = t.mode(a)?["key"] as? Int == 1 && t.mode(b)?["key"] as? Int == 2     // given in order as they're made
        t.setModeKey(a, 1); t.setModeKey(b, 0)
        let set = t.modeForKey(1)?["id"] as? String == a && t.modeForKey(0)?["id"] as? String == b
        t.setModeKey(b, 1)                                              // take Web's digit
        let moved = t.modeForKey(1)?["id"] as? String == b && t.mode(a)?["key"] == nil
        let m = NSMenu(); t.menuNeedsUpdate(m)
        let row = m.items.first { $0.title == "Games" && $0.submenu == nil }
        let shows = row?.keyEquivalent == "1" && row?.keyEquivalentModifierMask == .command && row?.action != nil
        let picker = m.items.first { $0.title == "Edit Modes" }?.submenu?.items.first { $0.title == "Games" }?.submenu?.items.first { $0.title.hasPrefix("Shortcut: ") }?.submenu
        let pickerOK = picker?.items.contains { $0.title == "None" } == true && picker?.items.filter { $0.state == .on }.count == 1
        let keys = m.items.first { $0.title == "Settings" }?.submenu?.items.first { $0.title == "Shortcuts" }?.submenu
        let modsOK = keys?.items.contains { $0.title.hasPrefix("⌘1") } == true
        let untouched = t.keyRefs.isEmpty                                // the test copy registered nothing global
        t.setModeKey(b, nil); let cleared = t.modeForKey(1) == nil
        t.modes = []
        done(noneYet && set && moved && shows && pickerOK && modsOK && untouched && cleared,
             "numbered 1, 2 as created: \(noneYet); set: \(set); digit moves: \(moved); row shows ⌘1: \(shows); picker: \(pickerOK); modifier in Settings: \(modsOK); test took no keys: \(untouched); None clears: \(cleared)")
    }))
    steps.append(("38. app rows: hovering shows + (will add) or × (will remove); after 2.5 s a popup says exactly what a click does", { done in
        let row = AppRow("Chrome", NSImage(), on: false, target: "your session") { true }
        let addText = row.tipText; row.on = true; let removeText = row.tipText
        let mode = AppRow("Chrome", NSImage(), on: false, target: "this mode") { true }.tipText
        let silent = AppRow("Chrome", NSImage(), on: true, onMark: "eye.slash.circle.fill") { true }.tipText == nil
        RowTip.shared.show("Click to add Chrome to your session.", under: NSRect(x: 100, y: 400, width: 300, height: 26))
        let shown = RowTip.shared.panel?.isVisible == true; RowTip.shared.hide()
        done(addText == "Click to add Chrome to your session." && removeText == "Click to remove Chrome from your session."
             && mode == "Click to add Chrome to this mode." && silent && AppRow.tipDelay >= 2 && AppRow.tipDelay <= 5 && shown,
             "add: '\(addText ?? "-")'; remove: '\(removeText ?? "-")'; mode: '\(mode ?? "-")'; no popup where nothing is added: \(silent); delay \(AppRow.tipDelay) s; popup shows: \(shown)")
    }))
    steps.append(("37. switching modes mid-session: the new mode's apps come back, the old ones close for now, all in one session; End restores", { done in
        for a in running(edit) { a.terminate() }
        waitUntil(8, { running(edit).isEmpty }) { _ in
            launch(calc) {
                t.modes = []
                let w = t.createMode("Writing", apps: [edit]), c = t.createMode("Sums", apps: [calc])
                t.park(quit: true, mode: t.mode(w), limit: [calc])
                waitUntil(12, { !running(edit).isEmpty && running(calc).isEmpty && t.queue.isEmpty }) { started in
                    t.switchMode(id: c, limit: [edit])                         // scoped: only TextEdit may close
                    waitUntil(14, { !running(calc).isEmpty && running(edit).isEmpty && t.queue.isEmpty }) { switched in
                        let one = t.sessions.first?["modeID"] as? String == c && t.sessions.first?["name"] as? String == "Sums"
                        t.toggle()
                        waitUntil(12, { !running(calc).isEmpty && !running(edit).isEmpty }) { back in
                            t.modes = []
                            done(started && switched && one && back,
                                 "Writing started: \(started); switched to Sums (Calculator back, TextEdit closed): \(switched); same session, renamed: \(one); End brings both back: \(back)")
                        }
                    }
                }
            }
        }
    }))
    steps.append(("39. naming is inline (no popups): new mode, rename mode, rename session, save as mode; the menu bar shows the session's name, or only the icon if turned off", { done in
        t.modes = []; t.store.removeObject(forKey: "showNameInMenuBar"); t.store.set(0, forKey: "menuBarNameStyle")
        func menu() -> NSMenu { let m = NSMenu(); t.menuNeedsUpdate(m); return m }
        let builder = menu().items.first { $0.title == "Create New Mode" }?.submenu
        let newField = builder?.items.compactMap { $0.view as? InlineNameField }.first
        t.draftApps = [edit]
        newField?.commit("AI")
        let made = t.modes.first { $0["name"] as? String == "AI" && ($0["apps"] as? [String]) == [edit] }
        let mid = made?["id"] as? String ?? ""
        let sub = menu().items.first { $0.title == "Edit Modes" }?.submenu?.items.first { $0.title == "AI" }?.submenu
        let renameField = sub?.items.first?.view as? InlineNameField
        renameField?.commit("Deep work")
        let renamed = t.mode(mid)?["name"] as? String == "Deep work"
        let noPopups = sub?.items.contains { $0.title.hasPrefix("Rename") } == false && !menu().items.contains { $0.title.hasPrefix("New Mode from") }
        t.sessions = [["date": Date(), "name": "AI", "mode": "AI", "kept": [edit], "apps": [[String: Any]]()]]
        t.store.set(true, forKey: "focused"); t.updateTitle()
        let shows = t.item.button?.title == " AI"
        t.showNameInMenuBar = false; let iconOnly = t.item.button?.title == ""
        t.showNameInMenuBar = true
        let past = menu().items.first { $0.title == "Past sessions" }?.submenu?.items.first?.submenu
        let fields = past?.items.compactMap { $0.view as? InlineNameField } ?? []
        fields.first?.commit("Night run"); let sessRenamed = t.sessions.first?["name"] as? String == "Night run"
        let titleFollows = t.item.button?.title == " Night run"
        t.store.set(false, forKey: "focused"); t.sessions = []; t.updateTitle()
        let cleared = t.item.button?.title == ""
        t.modes = []
        done(newField != nil && made != nil && renamed && noPopups && shows && iconOnly && fields.count == 2 && sessRenamed && titleFollows && cleared,
             "new mode inline: \(made != nil); rename inline: \(renamed); no Rename…/New Mode… popups: \(noPopups); menu bar ' AI': \(shows); icon only when off: \(iconOnly); past session has 2 inline fields: \(fields.count == 2); session rename: \(sessRenamed), menu bar follows: \(titleFollows); clears after: \(cleared)")
    }))
    steps.append(("40. the menu bar always names the session: its name, else the mode it matches, else Focus", { done in
        t.modes = []; t.store.removeObject(forKey: "showNameInMenuBar"); t.store.set(0, forKey: "menuBarNameStyle")
        t.createMode("AI", apps: [edit, calc])
        t.sessions = [["date": Date(), "kept": [edit, "com.apple.Preview"], "apps": [[String: Any]]()]]
        t.store.set(true, forKey: "focused"); t.updateTitle()
        let matched = t.item.button?.title == " AI"
        t.sessions = [["date": Date(), "kept": ["com.apple.Preview"], "apps": [[String: Any]]()]]; t.updateTitle()
        let fallback = t.item.button?.title == " Focus"
        t.sessions[0]["name"] = "Essay"; t.updateTitle(); let own = t.item.button?.title == " Essay"
        t.store.set(false, forKey: "focused"); t.sessions = []; t.updateTitle(); t.modes = []
        done(matched && fallback && own, "matches mode → ' AI': \(matched); no match → ' Focus': \(fallback); own name wins: \(own)")
    }))
    steps.append(("41. organised: Tools headings; Settings ▸ Behaviour; Create New Mode first; unnamed modes are numbered; right-click edit menu; column headings; headings share one size", { done in
        t.modes = []; t.draftApps = [edit]; t.createDraftMode()
        let unnamed = t.modes.first?["name"] as? String == "Mode 1" && t.modes.first?["key"] as? Int == 1 && t.draftApps.isEmpty
        let m = NSMenu(); t.menuNeedsUpdate(m)
        let titles = m.items.map(\.title)
        let tools = m.items.first { $0.title == "Tools" }?.submenu?.items.map(\.title) ?? []
        let toolsOK = tools.firstIndex(of: "Analyse performance") == 0 && tools.firstIndex(of: "Open Activity Monitor") == 1 && (tools.firstIndex(of: "Quit Unresponsive Apps") ?? 0) + 1 == tools.firstIndex(of: "Quit All Apps…")
        let settings = m.items.first { $0.title == "Settings" }?.submenu?.items.map(\.title) ?? []
        let order = settings.firstIndex(of: "Appearance") == 0 && settings.firstIndex(of: "Shortcuts") == 1 && settings.firstIndex(of: "Behaviour") == 2
        let beh = m.items.first { $0.title == "Settings" }?.submenu?.items.first { $0.title == "Behaviour" }?.submenu?.items.map(\.title) ?? []
        let behOK = beh.count == 3 && beh[0] == "App Open/Close Speed" && beh[1] == "Hide Instead of Quit" && beh[2].lowercased().contains("snapshot")
        let moved = !settings.contains("App Open/Close Speed") && !settings.contains("Hide Instead of Quit")
        let hi = titles.firstIndex(of: "Modes — frequently used sessions") ?? -9
        let em = m.items.first { $0.title == "Edit Modes" }?.submenu
        let lock = m.items.compactMap { $0.view as? AppRow }.filter { $0.onMark == "lock.circle.fill" }.allSatisfy(\.inert)
        let createFirst = lock && titles.indices.contains(hi + 2) && titles[hi + 1] == "Mode 1" && titles[hi + 2] == "Create New Mode"
            && em?.items.first?.title == "Add New Mode" && em?.items.first?.submenu != nil
        let row = m.items.first { $0.title == "Mode 1" }?.view as? ModeRow
        let edit1 = row?.edit()
        let before = edit1?.items.count ?? 0; if let e = edit1 { t.menuNeedsUpdate(e) }           // must stay its own menu
        let editOK = row?.key == "⌘1" && before > 3 && edit1?.items.count == before && edit1?.items.first?.view is InlineNameField
        let columns = m.items.contains { $0.view is ColumnHeader }
        t.store.removeObject(forKey: "menuBarNameStyle")
        let styles = t.menuBarNameStyle == 1 && Focus.nameStyles.map { $0("AI") } == ["AI", "AI session", "AI (in session)"]
        let sized = styles && !m.items.contains { $0.view is Heading }                     // headings are macOS's own
        t.modes = []
        let quitTop = m.items.first?.view is QuitRow && m.items.last?.view is Maker && m.items.last?.title == "★★★★★ × PARADOX™"
            && Maker.helpURL.scheme == "mailto" && Maker.help == "Help / Suggest Improvement"
        let aligned = quitTop && t.stack([edit]).size.width == t.stack([edit, calc, "com.apple.Preview"]).size.width
        done(aligned && unnamed && toolsOK && order && behOK && moved && createFirst && editOK && columns && sized,
             "unnamed → Mode 1 on ⌘1: \(unnamed); Tools headings: \(toolsOK); Appearance, Shortcuts, Behaviour: \(order); Behaviour holds the three: \(behOK), moved out of Settings: \(moved); Create New Mode under the modes, Add New Mode in Edit Modes, lock rows inert: \(createFirst); right-click edit menu: \(editOK); column headings: \(columns); standard macOS headings + name styles: \(sized)")
    }))
    steps.append(("42. clicking Usage cycles the app list: as listed → most memory first → most used first → back", { done in
        t.store.removeObject(forKey: "appSort")
        let list = [("a.small", "/Applications/Small.app"), ("b.big", "/Applications/Big.app")]
        let plain = t.sorted(list).map(\.0) == ["a.small", "b.big"]
        t.sessions = [["date": Date(), "kept": [calc], "apps": [[String: Any]]()], ["date": Date(), "kept": [calc, edit], "apps": [[String: Any]]()]]
        t.store.set(2, forKey: "appSort")
        let used = t.sorted([(edit, t.path(edit) ?? ""), (calc, t.path(calc) ?? "")]).map(\.0) == [calc, edit]
        t.store.set(0, forKey: "appSort"); t.sessions = []
        t.appSort += 1; let one = t.appSort == 1; t.appSort += 1; let two = t.appSort == 2; t.appSort += 1; let back = t.appSort == 0
        let m = NSMenu(); t.menuNeedsUpdate(m)
        let wired = (m.items.compactMap { $0.view as? ColumnHeader }.first?.onUsage) != nil
        done(plain && used && one && two && back && wired, "as listed: \(plain); most used first: \(used); cycles 1, 2, 0: \(one && two && back); Usage is clickable: \(wired)")
    }))
    steps.append(("43. Settings ▸ Appearance ▸ Headings: Minimalist (names only), Normal (as now), Verbose (a sentence under each)", { done in
        func titles(_ k: Int) -> [String] { t.headingStyle = k; let m = NSMenu(); t.menuNeedsUpdate(m); return m.items.map(\.title) }
        let mini = titles(0), norm = titles(1), verb = titles(2)
        t.store.removeObject(forKey: "headingStyle")
        let m = NSMenu(); t.menuNeedsUpdate(m)
        let picker = m.items.first { $0.title == "Settings" }?.submenu?.items.first { $0.title == "Appearance" }?.submenu?.items.first { $0.title == "Headings" }?.submenu
        let miniOK = mini.contains("Modes") && mini.contains("Critical System Processes") && !mini.contains { $0.hasPrefix("Keep open this session") }
        let normOK = norm.contains("Modes — frequently used sessions") && norm.contains("Critical System Processes — never quit") && norm.contains("Keep open this session — click to choose")
        let verbOK = verb.contains("Modes — frequently used sessions") && verb.count == norm.count + 3
        let pick = picker?.items.map(\.title) == ["Minimalist", "Normal", "Verbose"] && picker?.items[1].state == .on
        done(miniOK && normOK && verbOK && pick, "minimalist: \(miniOK); normal unchanged: \(normOK); verbose adds three explanations: \(verbOK); picker, Normal ticked: \(pick)")
    }))
    steps.append(("25. a session is defined by what it kept: recorded, titled by it, and Save as Mode uses it (never the parked apps)", { done in
        launch(edit) { launch(calc) {
            guard scope([calc]) else { return done(false, "scope") }   // TextEdit ticked = kept, Calculator parked
            t.park(quit: true)
            waitUntil(10, { t.queue.isEmpty && running(calc).isEmpty }) { _ in
                let rec = t.sessions[0]
                let keptOK = t.kept(rec).contains(edit) && !t.kept(rec).contains(calc)
                let m = NSMenu(); t.menuNeedsUpdate(m)
                let title = m.items.first { $0.title == "Past sessions" }?.submenu?.items.first?.title ?? ""
                let titled = title.hasPrefix("Kept ") && !title.contains("Calculator") && t.keptNames(rec).contains("TextEdit")   // title shows ≤3 names + "+N"
                t.modes = []; t.modeFromSession(0, name: "Test")
                let modeOK = (t.modes.first?["apps"] as? [String])?.contains(edit) == true && (t.modes.first?["apps"] as? [String])?.contains(calc) == false
                t.modes = []
                t.toggle()
                waitUntil(10, { !running(calc).isEmpty }) { back in
                    done(keptOK && titled && modeOK && back, "kept recorded: \(keptOK); title '\(title)'; mode = kept apps: \(modeOK); End restores: \(back)")
                }
            }
        } }
    }))
    steps.append(("26. icon designs: Lens is the default; every design draws at rest and focused, in the user's colours; the picker is in Appearance", { done in
        let d = UserDefaults(suiteName: suite)!
        d.removeObject(forKey: "iconStyle")
        let lensDefault = t.iconStyleSetting == .lens
        func ink(_ img: NSImage) -> Int {                        // how many pixels the design actually paints
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 36, pixelsHigh: 36, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            img.draw(in: NSRect(x: 0, y: 0, width: 36, height: 36)); NSGraphicsContext.restoreGraphicsState()
            var n = 0; for y in 0..<36 { for x in 0..<36 where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 { n += 1 } }; return n
        }
        var blank: [String] = []
        for st in IconStyle.allCases { for tt in [0.0, 1.0] as [CGFloat] where ink(glyph(tt, ring: .red, dot: .green, style: st)) < 12 { blank.append("\(st.name)@\(tt)") } }
        t.iconStyleSetting = .framed; let saved = t.iconStyleSetting == .framed
        let m = NSMenu(); t.menuNeedsUpdate(m)
        let look = m.items.first { $0.title == "Settings" }?.submenu?.items.first { $0.title == "Appearance" }?.submenu
        let picker = look?.items.contains { $0.view is IconGrid } == true
        d.removeObject(forKey: "iconStyle")
        done(lensDefault && blank.isEmpty && saved && picker,
             "Lens default: \(lensDefault); designs that drew nothing: \(blank.isEmpty ? "none" : blank.joined(separator: ", ")); choice saved: \(saved); picker in Appearance: \(picker)")
    }))
    steps.append(("27. modes plumbing: stable ids, add (by id and by dragged .app), dedupe, reorder, remove, rename, delete, migration", { done in
        let d = UserDefaults(suiteName: suite)!
        d.set([["name": "Old", "apps": ["com.apple.TextEdit"]]], forKey: "modes")     // a mode saved before ids existed
        t.migrateModes()
        let migrated = !(t.modes.first?["id"] as? String ?? "").isEmpty && t.modes.first?["name"] as? String == "Old"
        let id = t.createMode("Game design", apps: ["com.apple.TextEdit", "com.apple.TextEdit", "com.nobody.ghost"])
        let created = (t.mode(id)?["apps"] as? [String]) == ["com.apple.TextEdit"]          // deduped, unknown app dropped
        let pb = NSPasteboard(name: NSPasteboard.Name("focus-test-\(UUID().uuidString)")); pb.clearContents()
        pb.writeObjects([URL(fileURLWithPath: "/System/Applications/Calculator.app") as NSURL])
        let dropped = t.addApps(from: pb, toMode: id, at: 0) == 1 && (t.mode(id)?["apps"] as? [String])?.first == "com.apple.calculator"
        let dupe = !t.addApp("com.apple.calculator", toMode: id)
        t.moveApp(inMode: id, from: 0, to: 5)                                   // past the end = to the end
        let moved = (t.mode(id)?["apps"] as? [String]) == ["com.apple.TextEdit", "com.apple.calculator"]
        t.removeApp("com.apple.TextEdit", fromMode: id)
        t.renameMode(id, to: "Design")
        let edited = (t.mode(id)?["apps"] as? [String]) == ["com.apple.calculator"] && t.mode(id)?["name"] as? String == "Design"
        let byIdSurvivesReorder = t.modeIndex(id) == 1
        t.removeMode(id)
        let deleted = t.mode(id) == nil && t.modes.count == 1
        pb.releaseGlobally(); d.removeObject(forKey: "modes")
        done(migrated && created && dropped && dupe && moved && edited && byIdSurvivesReorder && deleted,
             "migration \(migrated) · create+dedupe \(created) · dragged .app \(dropped) · no duplicates \(dupe) · reorder \(moved) · remove+rename \(edited) · found by id \(byIdSurvivesReorder) · delete \(deleted)")
    }))
    steps.append(("28. a live session: no banner and no state line at the top; the button says End Session", { done in
        t.sessions = [["date": Date(), "name": "Game design", "mode": "Game design", "kept": ["com.apple.TextEdit"], "apps": [[String: Any]]()]]
        UserDefaults(suiteName: suite)!.set(true, forKey: "focused")
        let m1 = NSMenu(); t.menuNeedsUpdate(m1)
        let top = m1.items.first?.title ?? ""
        let noBanner = !m1.items.contains { $0.view is SessionBanner } && !top.hasPrefix("Focus")
        let button = (m1.items.compactMap { $0.view as? BigButton }.first?.title() ?? "")
        UserDefaults(suiteName: suite)!.set(false, forKey: "focused"); t.sessions = []
        done(noBanner && button == "End Session", "first line '\(top)', no banner or state line: \(noBanner); button '\(button)'")
    }))
    steps.append(("29. switching and hide-instead-of-quit settings; the Fewer icon", { done in
        let d = UserDefaults(suiteName: suite)!
        d.removeObject(forKey: "fastSwitching"); d.removeObject(forKey: "hideOnly")
        let careful = !t.fastSwitching
        let m = NSMenu(); t.menuNeedsUpdate(m)
        let settings = m.items.first { $0.title == "Settings" }?.submenu
        let behaviour = settings?.items.first { $0.title == "Behaviour" }?.submenu
        let sw = behaviour?.items.first { $0.title == "App Open/Close Speed" }?.submenu
        let carefulTicked = sw?.items.first?.state == .on && sw?.items.last?.state == .off
        let hideMenu = behaviour?.items.first { $0.title == "Hide Instead of Quit" }?.submenu
        let rows = hideMenu?.items.contains { $0.view is AppRow } == true
        let fewer = IconStyle.allCases.contains(.fewer)
        done(careful && carefulTicked && rows && fewer, "careful unless chosen: \(careful); menu ticks Careful: \(carefulTicked); per-app hide rows: \(rows); Fewer icon: \(fewer)")
    }))
    steps.append(("30. fast switching quits and reopens all at once; a hide-only app is hidden (never quit) and comes back as it was", { done in
        launch(edit) { launch(calc) {
            for a in running(edit) { a.unhide() }
            waitUntil(5, { running(edit).first?.isHidden == false }) { _ in   // visible before the session starts
            guard scope([edit, calc]) else { return done(false, "scope") }
            t.fastSwitching = true; t.hideOnly = [edit]
            let pid = running(edit).first?.processIdentifier
            t.park(quit: true)
            waitUntil(12, { running(calc).isEmpty && running(edit).first?.isHidden == true && t.queue.isEmpty }) { parked in
                let samePid = running(edit).first?.processIdentifier == pid     // hidden, not quit: the very same process
                t.toggle()
                waitUntil(10, { !running(calc).isEmpty && running(edit).first?.isHidden == false }) { back in
                    t.fastSwitching = false; t.hideOnly = []
                    done(parked && samePid && back, "Calculator quit + TextEdit hidden: \(parked); TextEdit never quit (same process): \(samePid); both back: \(back)")
                }
            }
            }
        } }
    }))
    steps.append(("31. edit a live session: take an open app out now, bring a parked one back now, End restores the rest", { done in
        launch(edit) { launch(calc) {
            guard scope([calc]) else { return done(false, "scope") }   // TextEdit kept, Calculator parked
            t.park(quit: true)
            waitUntil(10, { t.queue.isEmpty && running(calc).isEmpty }) { _ in
                t.parkNow(edit)                                        // take TextEdit out, mid-session
                waitUntil(10, { running(edit).isEmpty && t.queue.isEmpty }) { out in
                    let recorded = t.isParked(edit) && t.focused
                    t.bringBack(calc)                                  // bring Calculator back, mid-session
                    waitUntil(10, { !running(calc).isEmpty }) { back in
                        let noLongerParked = !t.isParked(calc) && t.focused
                        t.toggle()                                     // End
                        waitUntil(10, { !running(edit).isEmpty }) { restored in
                            done(out && recorded && back && noLongerParked && restored && running(calc).count == 1,
                                 "TextEdit out mid-session: \(out) (recorded \(recorded)); Calculator back mid-session: \(back) (unparked \(noLongerParked)); End brings TextEdit back: \(restored); one Calculator: \(running(calc).count == 1)")
                        }
                    }
                }
            }
        } }
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
        case 100...109: focus.modeKey(Int(hk.id) - 100)
        default: break
        }
    }
    return noErr
}, 1, &spec, nil, nil)
focus.applyShortcuts()                                          // ⌘⇧F / ⌘⇧E by default; Settings ▸ Shortcuts changes them
app.run()
