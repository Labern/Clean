// CommandCentre.swift — ★★★★★ × PARADOX Command Centre
//
// A real place, not a page: you cross a threshold and you are inside the
// company. Five territories — COMMAND (the wall), THE MAKING DESK, THE TABLE,
// THE ARSENAL, THE REVIEW WALL — in one window that fills the screen.
//
// The window's own traffic lights are the only chrome. Nothing here draws a
// fake title bar.
//
// State lives in ~/Library/Application Support/PARADOX Command Centre/state.json
// and is decoded field-by-field with defaults, so a newer build always opens an
// older file without losing a word of it.

import AppKit
import SwiftUI
import Combine

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Tokens
// Every colour in the app comes from one Palette value. Swapping the value on
// the root re-themes the entire room — the Swift equivalent of overriding CSS
// custom properties on a single ancestor.
// ═══════════════════════════════════════════════════════════════════════════

struct Palette {
    var bg1, bg2, bg3, bg4: Color
    var term, titlebar, edge: Color
    var ink, faint, dim: Color
    var teal, teal2, violet, violet2, pink, gold, dark, rule: Color

    static let paradox = Palette(
        bg1: hex(0x0f0c29), bg2: hex(0x302b63), bg3: hex(0x24243e), bg4: hex(0x1a1a2e),
        term: hex(0x0e0b1a), titlebar: hex(0x171331), edge: hex(0x2a2350),
        ink: hex(0xcfcae6), faint: hex(0x8787af), dim: hex(0x6c6c8a),
        teal: hex(0x87d7d7), teal2: hex(0x5fd7af), violet: hex(0xaf87ff), violet2: hex(0xd787ff),
        pink: hex(0xff87ff), gold: hex(0xffd75f), dark: hex(0x5f5f87), rule: hex(0x875fd7))

    // A second token set, proving the swap costs nothing. Not yet reachable
    // from the UI — the point is that it would be one assignment.
    static let ember = Palette(
        bg1: hex(0x1a0d0c), bg2: hex(0x4a1f16), bg3: hex(0x2a1512), bg4: hex(0x170f10),
        term: hex(0x140b09), titlebar: hex(0x241310), edge: hex(0x3a201a),
        ink: hex(0xf0e2d8), faint: hex(0xb08a76), dim: hex(0x8a6552),
        teal: hex(0xf0b27a), teal2: hex(0xe8a13f), violet: hex(0xff8a5f), violet2: hex(0xffb07a),
        pink: hex(0xff6f91), gold: hex(0xffd75f), dark: hex(0x7a4a3a), rule: hex(0xc1663f))

    static func hex(_ v: UInt32) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xff) / 255,
              green: Double((v >> 8) & 0xff) / 255,
              blue: Double(v & 0xff) / 255, opacity: 1)
    }
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette.paradox }
extension EnvironmentValues {
    var p: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .custom("Menlo", size: size).weight(weight)
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Model
// ═══════════════════════════════════════════════════════════════════════════

func uid() -> String { String(UUID().uuidString.prefix(8)) }

struct Item: Codable, Identifiable, Equatable {
    var id: String = uid()
    var text: String = ""
    var done: Bool = false

    init(_ text: String = "", done: Bool = false) { self.text = text; self.done = done }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id   = (try? c.decode(String.self, forKey: .id)) ?? uid()
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        done = (try? c.decode(Bool.self, forKey: .done)) ?? false
    }
}

struct Tool: Codable, Identifiable, Equatable {
    var id: String = uid()
    var text: String = ""
    var on: Bool = false

    init(_ text: String, on: Bool = false) { self.text = text; self.on = on }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id   = (try? c.decode(String.self, forKey: .id)) ?? uid()
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        on   = (try? c.decode(Bool.self, forKey: .on)) ?? false
    }
}

struct PowerLine: Codable, Identifiable, Equatable {
    var id: String = uid()
    var key: String = ""
    var level: Int = 0
    var note: String = ""

    init(_ key: String, _ level: Int = 0, _ note: String = "") {
        self.key = key; self.level = level; self.note = note
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id    = (try? c.decode(String.self, forKey: .id)) ?? uid()
        key   = (try? c.decode(String.self, forKey: .key)) ?? ""
        level = (try? c.decode(Int.self, forKey: .level)) ?? 0
        note  = (try? c.decode(String.self, forKey: .note)) ?? ""
    }
}

struct Card: Codable, Identifiable, Equatable {
    static let kinds = ["NOTE", "SCRIPT", "IMAGE", "OBJECT", "PLAN"]
    var id: String = uid()
    var kind: String = "NOTE"
    var text: String = ""
    var x: Double = 40
    var y: Double = 40

    init(x: Double, y: Double) { self.x = x; self.y = y }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id   = (try? c.decode(String.self, forKey: .id)) ?? uid()
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "NOTE"
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        x    = (try? c.decode(Double.self, forKey: .x)) ?? 40
        y    = (try? c.decode(Double.self, forKey: .y)) ?? 40
    }
}

struct Pin: Codable, Identifiable, Equatable {
    static let kinds = ["WORK", "FRAME", "UI", "PAGE", "DESIGN", "PLAN"]
    var id: String = uid()
    var kind: String = "WORK"
    var text: String = ""
    var verdict: String = "hold"          // hold · rework · notyet

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id      = (try? c.decode(String.self, forKey: .id)) ?? uid()
        kind    = (try? c.decode(String.self, forKey: .kind)) ?? "WORK"
        text    = (try? c.decode(String.self, forKey: .text)) ?? ""
        verdict = (try? c.decode(String.self, forKey: .verdict)) ?? "hold"
    }

    var verdictLabel: String {
        switch verdict {
        case "rework": return "REWORK"
        case "notyet": return "NOT FOR RELEASE YET"
        default:       return "AWAITING JUDGEMENT"
        }
    }
}

struct Session: Codable, Identifiable, Equatable {
    var id: String = uid()
    var day: String = ""
    var seconds: Int = 0
    var focus: String = ""

    init(day: String, seconds: Int, focus: String) {
        self.day = day; self.seconds = seconds; self.focus = focus
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id      = (try? c.decode(String.self, forKey: .id)) ?? uid()
        day     = (try? c.decode(String.self, forKey: .day)) ?? ""
        seconds = (try? c.decode(Int.self, forKey: .seconds)) ?? 0
        focus   = (try? c.decode(String.self, forKey: .focus)) ?? ""
    }
}

struct Campaign: Codable, Equatable {
    var title = "MAKE ★★★★★ × PARADOX A REAL PLACE"
    var statement = "Build the room the company acts from — command wall, making desk, table, arsenal, review wall — then put real work through it."
    var horizon = ""
    var stake = ""

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        var base = Campaign()
        title     = (try? c.decode(String.self, forKey: .title)) ?? base.title
        statement = (try? c.decode(String.self, forKey: .statement)) ?? base.statement
        horizon   = (try? c.decode(String.self, forKey: .horizon)) ?? base.horizon
        stake     = (try? c.decode(String.self, forKey: .stake)) ?? base.stake
        base = Campaign()
    }
}

/// Everything the room holds. Decoding is additive on purpose: every field
/// falls back to its default, so a state file written by any earlier build
/// still opens, and no future field can wipe an existing one.
struct AppState: Codable, Equatable {
    var version = 1
    var campaign = Campaign()
    var now: [Item] = [Item("★★★★★ × PARADOX Command Centre — v1")]
    var next: [Item] = [Item("Fill the command wall with live information")]
    var canon: [Item] = []
    var power: [PowerLine] = [
        PowerLine("MONEY"), PowerLine("IP"), PowerLine("AUDIENCE"),
        PowerLine("TECHNOLOGY", 3, "Claude Code · the whole toolchain"),
        PowerLine("EQUIPMENT", 1), PowerLine("RELATIONSHIPS"),
        PowerLine("DISTRIBUTION", 1, "labern.github.io")
    ]
    var focus = ""
    var runningSince: Date? = nil
    var sessions: [Session] = []
    var tools: [Tool] = [
        Tool("Mac + displays", on: true), Tool("Programming environment", on: true),
        Tool("Audio"), Tool("Camera"), Tool("Drawing / writing materials")
    ]
    var table: [Card] = []
    var study: [Item] = []
    var arsenal: [Item] = []
    var review: [Pin] = []
    var crossings = 0
    var lastCrossing: Date? = nil

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let base = AppState()
        version      = (try? c.decode(Int.self, forKey: .version)) ?? base.version
        campaign     = (try? c.decode(Campaign.self, forKey: .campaign)) ?? base.campaign
        now          = (try? c.decode([Item].self, forKey: .now)) ?? base.now
        next         = (try? c.decode([Item].self, forKey: .next)) ?? base.next
        canon        = (try? c.decode([Item].self, forKey: .canon)) ?? base.canon
        power        = (try? c.decode([PowerLine].self, forKey: .power)) ?? base.power
        focus        = (try? c.decode(String.self, forKey: .focus)) ?? base.focus
        runningSince = try? c.decode(Date.self, forKey: .runningSince)
        sessions     = (try? c.decode([Session].self, forKey: .sessions)) ?? base.sessions
        tools        = (try? c.decode([Tool].self, forKey: .tools)) ?? base.tools
        table        = (try? c.decode([Card].self, forKey: .table)) ?? base.table
        study        = (try? c.decode([Item].self, forKey: .study)) ?? base.study
        arsenal      = (try? c.decode([Item].self, forKey: .arsenal)) ?? base.arsenal
        review       = (try? c.decode([Pin].self, forKey: .review)) ?? base.review
        crossings    = (try? c.decode(Int.self, forKey: .crossings)) ?? base.crossings
        lastCrossing = try? c.decode(Date.self, forKey: .lastCrossing)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Store
// ═══════════════════════════════════════════════════════════════════════════

final class Store: ObservableObject {
    @Published var s = AppState() { didSet { scheduleSave() } }
    @Published var palette = Palette.paradox
    @Published var crossed = false
    @Published var section: Section = .command
    @Published var enteredAt: Date? = nil
    @Published var tick = Date()                       // drives the two clocks

    private var saveWork: DispatchWorkItem?
    private var timer: AnyCancellable?

    static let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PARADOX Command Centre", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("state.json")
    }()

    /// Headless verification seam: `CC_ENTER=3 open -g -a "Command Centre"` opens
    /// already inside the room on territory 3, without activating or coming to
    /// the front — so a build can be screenshotted while someone else is using
    /// the Mac. It deliberately does NOT count as a crossing: the crossing log
    /// records only real ones.
    static var testSection: Section? {
        guard let raw = ProcessInfo.processInfo.environment["CC_ENTER"],
              let n = Int(raw), let s = Section(rawValue: n - 1) else { return nil }
        return s
    }

    init() {
        if let data = try? Data(contentsOf: Store.url),
           let loaded = try? JSONDecoder().decode(AppState.self, from: data) {
            s = loaded
        }
        if let test = Store.testSection {
            crossed = true
            enteredAt = Date()
            section = test
        }
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] d in self?.tick = d }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Atomic write — a crash mid-save can never truncate the file.
    func saveNow() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(s) else { return }
        try? data.write(to: Store.url, options: .atomic)
    }

    // ── the threshold ──────────────────────────────────────────────────────
    func cross() {
        guard !crossed else { return }
        crossed = true
        enteredAt = Date()
        s.crossings += 1
        s.lastCrossing = Date()
    }

    func leave() {
        if s.runningSince != nil { toggleSession() }
        crossed = false
        enteredAt = nil
        saveNow()
    }

    // ── the desk clock ─────────────────────────────────────────────────────
    func toggleSession() {
        if let started = s.runningSince {
            let secs = Int(Date().timeIntervalSince(started))
            if secs > 4 {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                s.sessions.append(Session(day: f.string(from: started), seconds: secs, focus: s.focus))
            }
            s.runningSince = nil
        } else {
            s.runningSince = Date()
        }
        saveNow()
    }

    var runningSeconds: Int {
        guard let started = s.runningSince else { return 0 }
        return max(0, Int(tick.timeIntervalSince(started)))
    }

    var inRoomSeconds: Int {
        guard let entered = enteredAt else { return 0 }
        return max(0, Int(tick.timeIntervalSince(entered)))
    }

    // ── the wall's verdict that feeds the wall ─────────────────────────────
    func sendToCanon(_ pin: Pin) {
        s.canon.append(Item(pin.text.isEmpty ? "(untitled work)" : pin.text))
        s.review.removeAll { $0.id == pin.id }
        saveNow()
    }
}

func hms(_ seconds: Int) -> String {
    let s = max(0, seconds)
    return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
}

enum Section: Int, CaseIterable, Identifiable {
    case command, desk, table, arsenal, review
    var id: Int { rawValue }
    var number: String { String(format: "%02d", rawValue + 1) }
    var label: String {
        switch self {
        case .command: return "COMMAND"
        case .desk:    return "MAKING DESK"
        case .table:   return "THE TABLE"
        case .arsenal: return "ARSENAL"
        case .review:  return "REVIEW WALL"
        }
    }
    var title: String {
        switch self {
        case .command: return "COMMAND"
        case .desk:    return "THE MAKING DESK"
        case .table:   return "THE TABLE"
        case .arsenal: return "THE ARSENAL"
        case .review:  return "THE REVIEW WALL"
        }
    }
    var subtitle: String {
        switch self {
        case .command: return "stand a stranger here for five minutes and they understand the company"
        case .desk:    return "a production surface, not a general-life desk"
        case .table:   return "a screen compresses everything into one glowing rectangle — the table lets you see twenty things at once"
        case .arsenal: return "everything here answers one question: what can ★★★★★ × PARADOX use?"
        case .review:  return "stand back — you are not the person who made this"
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Shared pieces (the CLI card grammar, in AppKit pixels)
// ═══════════════════════════════════════════════════════════════════════════

/// ╭─ TITLE — key ─────╮ … ╰───╯ with the right edge of content left open.
struct Box<Content: View>: View {
    @Environment(\.p) private var p
    var title: String
    var key: String = ""
    var caption: String = ""
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("╭─").foregroundColor(p.rule)
                // fixedSize: the rule yields, never the words in the rule
                Text(title).font(mono(11, .bold)).tracking(1.8).foregroundColor(p.gold)
                    .fixedSize()
                if !key.isEmpty {
                    Text(key).font(mono(10)).tracking(0.6).foregroundColor(p.faint)
                        .lineLimit(1).truncationMode(.tail)
                }
                Rectangle().fill(p.rule.opacity(0.55)).frame(height: 1)
                Text("╮").foregroundColor(p.rule)
            }
            .font(mono(11))

            // The left rule is an overlay on the content, not a sibling in an
            // HStack: as a sibling, a width-only Rectangle takes all the height
            // the scroll view offers and stretches every box to the viewport.
            content
                .padding(.leading, 14).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .overlay(alignment: .leading) {
                    Rectangle().fill(p.rule.opacity(0.55)).frame(width: 1)
                }
                .padding(.leading, 4)

            HStack(spacing: 6) {
                Text("╰").foregroundColor(p.rule)
                Rectangle().fill(p.rule.opacity(0.55)).frame(height: 1)
                Text("╯").foregroundColor(p.rule)
            }
            .font(mono(11))

            if !caption.isEmpty {
                Text(caption).font(mono(10)).foregroundColor(p.faint)
                    .padding(.top, 3).padding(.leading, 18)
            }
        }
    }
}

/// A plain-text field that looks like text until you are in it.
///
/// It takes a point size rather than a Font on purpose: AppKit reports a plain
/// TextField's ideal height slightly short of what Menlo actually draws, so the
/// last line of every list came back shaved in half. Knowing the size lets the
/// field claim the line box it really needs.
struct Field: View {
    @Environment(\.p) private var p
    @Binding var text: String
    var placeholder: String
    var size: CGFloat = 12
    var color: Color? = nil
    var oneLine = false

    var body: some View {
        // The placeholder is drawn by hand. AppKit renders a TextField's own
        // placeholder in the system font at the system size regardless of the
        // .font applied to the field, so at Menlo 11 it overflowed its line box
        // and every empty line in the room came back sliced in half.
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(mono(size))
                    .foregroundColor(p.dim)
                    .allowsHitTesting(false)
            }
            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(mono(size))
                .foregroundColor(color ?? p.ink)
                .lineLimit(oneLine ? 1...1 : 1...6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: ceil(size * 1.5), alignment: .topLeading)
    }
}

struct Meter: View {
    @Environment(\.p) private var p
    @Binding var level: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { i in
                Text(i < level ? "▰" : "▱")
                    .foregroundColor(i < level ? p.teal : p.dark)
                    .onTapGesture { level = (level == i + 1) ? i : i + 1 }
            }
        }
        .font(mono(12))
    }
}

/// One editable line in a list, with its glyph and a delete that appears on hover.
struct Row<Glyph: View>: View {
    @Environment(\.p) private var p
    @ViewBuilder var glyph: Glyph
    @Binding var text: String
    var placeholder: String = "…"
    var struck = false
    var onDelete: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            glyph.font(mono(12))
            Field(text: $text, placeholder: placeholder,
                  color: struck ? p.dim : p.ink)
                .strikethrough(struck, color: p.dim)
            Button(action: onDelete) {
                Text("×").font(mono(12)).foregroundColor(hover ? p.pink : p.dark)
            }
            .buttonStyle(.plain)
            .opacity(hover ? 1 : 0)
        }
        .padding(.vertical, 1)
        .onHover { hover = $0 }
    }
}

/// The "+ …" line at the bottom of every list. Return commits, and the field
/// stays focused so a burst of items goes in without touching the mouse.
struct Adder: View {
    @Environment(\.p) private var p
    var placeholder: String
    var onAdd: (String) -> Void
    @State private var draft = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            if draft.isEmpty {
                Text(placeholder).font(mono(11)).foregroundColor(p.dark)
                    .allowsHitTesting(false)
            }
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .font(mono(11))
                .foregroundColor(p.ink)
                .onSubmit {
                    let v = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !v.isEmpty else { return }
                    onAdd(v)
                    draft = ""
                }
        }
        .frame(minHeight: 17, alignment: .topLeading)
        .padding(.top, 3)
    }
}

struct PaneHeader: View {
    @Environment(\.p) private var p
    var section: Section
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(section.number) ·").font(mono(12)).foregroundColor(p.dark)
            Text(section.title).font(mono(13, .bold)).tracking(3).foregroundColor(p.violet)
            Text(section.subtitle).font(mono(10)).foregroundColor(p.dim)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            if let trailing { trailing }
        }
    }
}

struct PBtn: View {
    @Environment(\.p) private var p
    var label: String
    var tint: Color? = nil
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(label).font(mono(11)).tracking(1.6)
                .foregroundColor(tint ?? p.teal)
                .padding(.horizontal, 14).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill((tint ?? p.teal).opacity(hover ? 0.14 : 0)))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .stroke((tint ?? p.rule).opacity(0.8), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - The threshold
// ═══════════════════════════════════════════════════════════════════════════

struct ThresholdView: View {
    @EnvironmentObject var store: Store
    @Environment(\.p) private var p
    @State private var blink = true

    var body: some View {
        ZStack {
            RadialGradient(colors: [p.bg2.opacity(0.55), Color.black.opacity(0.97)],
                           center: .init(x: 0.5, y: 0.4), startRadius: 20, endRadius: 900)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("★").foregroundColor(p.teal2)
                    Text("★").foregroundColor(p.teal)
                    Text("★").foregroundColor(p.violet)
                    Text("★").foregroundColor(p.violet2)
                    Text("★").foregroundColor(p.pink)
                }
                .font(mono(34))

                Text("P A R A D O X")
                    .font(mono(20, .bold)).tracking(6).foregroundColor(p.violet)
                    .padding(.top, 10)

                VStack(spacing: 5) {
                    Text("Beyond this point you are not at home.")
                    Text("You are inside ★★★★★ × PARADOX.").foregroundColor(p.ink)
                    Text("Phones do not run the room · chores do not enter ·")
                    Text("nobody drifts through. If you are here, you are in the work.")
                }
                .font(mono(11))
                .foregroundColor(p.faint)
                .padding(.top, 26)

                Button(action: { store.cross() }) {
                    HStack(spacing: 6) {
                        Text("CROSS THE THRESHOLD").font(mono(12)).tracking(3.6)
                            .foregroundColor(p.teal)
                        Rectangle().fill(p.teal).frame(width: 8, height: 15)
                            .opacity(blink ? 1 : 0)
                    }
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 30)

                Text(historyLine)
                    .font(mono(10)).foregroundColor(p.dim)
                    .padding(.top, 22)
            }
            .padding(.horizontal, 64).padding(.vertical, 48)
            .background(RoundedRectangle(cornerRadius: 8).fill(p.term.opacity(0.72)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.rule, lineWidth: 1))
        }
        .contentShape(Rectangle())
        .onTapGesture { store.cross() }
        .onAppear {
            withAnimation(.linear(duration: 0.55).repeatForever(autoreverses: true)) { blink = false }
        }
    }

    private var historyLine: String {
        guard store.s.crossings > 0, let last = store.s.lastCrossing else { return "first crossing" }
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return "\(store.s.crossings) crossing\(store.s.crossings == 1 ? "" : "s") · last \(f.string(from: last))"
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - The room
// ═══════════════════════════════════════════════════════════════════════════

let railWidth: CGFloat = 190

struct RoomView: View {
    @EnvironmentObject var store: Store
    @Environment(\.p) private var p

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            Divider().overlay(p.edge)
            HStack(spacing: 0) {
                Rail()
                Rectangle().fill(p.edge).frame(width: 1)
                pane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(p.term)
    }

    @ViewBuilder private var pane: some View {
        switch store.section {
        case .command: CommandPane()
        case .desk:    DeskPane()
        case .table:   TablePane()
        case .arsenal: ArsenalPane()
        case .review:  ReviewPane()
        }
    }
}

struct TopBar: View {
    @EnvironmentObject var store: Store
    @Environment(\.p) private var p

    var body: some View {
        HStack(spacing: 0) {
            // the mark sits in the rail's column
            HStack(spacing: 2) {
                Text("★").foregroundColor(p.teal2)
                Text("★").foregroundColor(p.teal)
                Text("★").foregroundColor(p.violet)
                Text("★").foregroundColor(p.violet2)
                Text("★").foregroundColor(p.pink)
                Text("×").foregroundColor(p.dim).padding(.horizontal, 5)
                Text("PARADOX").font(mono(12, .bold)).tracking(2).foregroundColor(p.violet)
            }
            .font(mono(13))
            .frame(width: railWidth, alignment: .leading)
            .padding(.leading, 16)

            // The campaign line is centred over the PANE — the surface it
            // describes — not over the window. The clock floats at the trailing
            // edge without pulling the title off that axis.
            ZStack {
                HStack(spacing: 10) {
                    Text("CAMPAIGN").font(mono(10)).tracking(2).foregroundColor(p.dim)
                    Text(store.s.campaign.title.isEmpty ? "—" : store.s.campaign.title.uppercased())
                        .font(mono(11)).tracking(1.6).foregroundColor(p.gold)
                        .lineLimit(1).truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 7) {
                    Spacer()
                    Circle().fill(p.pink).frame(width: 6, height: 6)
                    Text("IN THE ROOM \(hms(store.inRoomSeconds))")
                        .font(mono(10)).foregroundColor(p.faint)
                }
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 40)
    }
}

struct Rail: View {
    @EnvironmentObject var store: Store
    @Environment(\.p) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Section.allCases) { s in
                RailButton(section: s)
            }
            Spacer()
            HStack(spacing: 4) {
                Text("CANON").foregroundColor(p.dim)
                Text("\(store.s.canon.count)").foregroundColor(p.gold)
                Text("·").foregroundColor(p.dim)
                Text("NOW").foregroundColor(p.dim)
                Text("\(store.s.now.filter { !$0.done }.count)").foregroundColor(p.teal)
                Text("·").foregroundColor(p.dim)
                Text("WALL").foregroundColor(p.dim)
                Text("\(store.s.review.count)").foregroundColor(p.pink)
            }
            .font(mono(10))
            .padding(.horizontal, 16)

            Button(action: { store.leave() }) {
                Text("⌫  leave the room").font(mono(10)).foregroundColor(p.dim)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 16)
        }
        .padding(.top, 14)
        .frame(width: railWidth, alignment: .leading)
    }
}

struct RailButton: View {
    @EnvironmentObject var store: Store
    @Environment(\.p) private var p
    var section: Section
    @State private var hover = false

    private var active: Bool { store.section == section }

    var body: some View {
        Button(action: { store.section = section }) {
            HStack(spacing: 10) {
                Text(section.number).font(mono(10)).foregroundColor(active ? p.gold : p.dark)
                Text(section.label).font(mono(11.5))
                    .foregroundColor(active ? p.gold : (hover ? p.ink : p.faint))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6).padding(.horizontal, 16)
            .background(active ? p.gold.opacity(0.05) : (hover ? Color.white.opacity(0.03) : .clear))
            .overlay(alignment: .leading) {
                Rectangle().fill(active ? p.gold : .clear).frame(width: 2)
            }
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - 01 COMMAND
// ═══════════════════════════════════════════════════════════════════════════

struct CommandPane: View {
    @EnvironmentObject var store: Store
    @Environment(\.p) private var p

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PaneHeader(section: .command)

                Box(title: "CURRENT CAMPAIGN", key: "what are we actually trying to accomplish") {
                    VStack(alignment: .leading, spacing: 10) {
                        Field(text: $store.s.campaign.title, placeholder: "Name the campaign…",
                              size: 24)
                        HStack(alignment: .top, spacing: 6) {
                            Text("→").font(mono(11)).foregroundColor(p.faint)
                            Field(text: $store.s.campaign.statement,
                                  placeholder: "What does winning it mean?",
                                  size: 11, color: p.teal)
                        }
                        HStack(alignment: .top, spacing: 22) {
                            HStack(spacing: 8) {
                                Text("HORIZON").font(mono(10)).foregroundColor(p.faint)
                                Field(text: $store.s.campaign.horizon, placeholder: "by when",
                                      size: 11, color: p.teal)
                                    .frame(maxWidth: 220)
                            }
                            HStack(spacing: 8) {
                                Text("STAKE").font(mono(10)).foregroundColor(p.faint)
                                Field(text: $store.s.campaign.stake,
                                      placeholder: "what it costs · what it wins",
                                      size: 11, color: p.teal)
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 20) {
                    Box(title: "NOW", key: "in production",
                        caption: "\(store.s.now.filter { !$0.done }.count) live") {
                        listBody(\.now, glyph: "▸", placeholder: "+ what is in production…")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Box(title: "NEXT", key: "what moves next",
                        caption: "\(store.s.next.count) queued") {
                        listBody(\.next, glyph: "→", placeholder: "+ what moves next…")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Box(title: "CANON", key: "finished works",
                        caption: "\(store.s.canon.count) in canon · the room's accumulated history") {
                        VStack(alignment: .leading, spacing: 2) {
                            if store.s.canon.isEmpty {
                                Text("Nothing yet. CANON fills from the REVIEW WALL.")
                                    .font(mono(11)).foregroundColor(p.dim)
                            }
                            ForEach(store.s.canon) { item in
                                Row(glyph: { Text("★").foregroundColor(p.gold) },
                                    text: binding(\.canon, item.id),
                                    onDelete: { store.s.canon.removeAll { $0.id == item.id } })
                            }
                            Adder(placeholder: "+ a finished work…") { store.s.canon.append(Item($0)) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Box(title: "POWER", key: "what the company presently commands",
                    caption: "click a meter to set the level · 0 = we do not have it yet") {
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                        GridItem(.flexible(), alignment: .leading)],
                              alignment: .leading, spacing: 4) {
                        ForEach(store.s.power) { line in
                            HStack(spacing: 10) {
                                Text(line.key).font(mono(10)).tracking(0.8)
                                    .foregroundColor(p.faint)
                                    .frame(width: 110, alignment: .leading)
                                Meter(level: Binding(
                                    get: { line.level },
                                    set: { v in
                                        if let i = store.s.power.firstIndex(where: { $0.id == line.id }) {
                                            store.s.power[i].level = v
                                        }
                                    }))
                                Field(text: Binding(
                                        get: { line.note },
                                        set: { v in
                                            if let i = store.s.power.firstIndex(where: { $0.id == line.id }) {
                                                store.s.power[i].note = v
                                            }
                                        }),
                                      placeholder: "what exactly?", size: 11, color: p.dim,
                                      oneLine: true)       // one power line stays one line
                            }
                            .padding(.trailing, 24)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func listBody(_ path: WritableKeyPath<AppState, [Item]>,
                          glyph: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(store.s[keyPath: path]) { item in
                Row(glyph: {
                        Text(item.done ? "✓" : glyph)
                            .foregroundColor(item.done ? p.teal2 : p.dark)
                            .onTapGesture {
                                if let i = store.s[keyPath: path].firstIndex(where: { $0.id == item.id }) {
                                    store.s[keyPath: path][i].done.toggle()
                                }
                            }
                    },
                    text: binding(path, item.id),
                    struck: item.done,
                    onDelete: { store.s[keyPath: path].removeAll { $0.id == item.id } })
            }
            Adder(placeholder: placeholder) { store.s[keyPath: path].append(Item($0)) }
        }
    }

    private func binding(_ path: WritableKeyPath<AppState, [Item]>, _ id: String) -> Binding<String> {
        Binding(
            get: { store.s[keyPath: path].first(where: { $0.id == id })?.text ?? "" },
            set: { v in
                if let i = store.s[keyPath: path].firstIndex(where: { $0.id == id }) {
                    store.s[keyPath: path][i].text = v
                }
            })
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - 02 THE MAKING DESK
// ═══════════════════════════════════════════════════════════════════════════

struct DeskPane: View {
    @EnvironmentObject var store: Store
    @Environment(\.p) private var p

    private var todaySeconds: Int {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())
        return store.s.sessions.filter { $0.day == today }.reduce(0) { $0 + $1.seconds }
    }
    private var allSeconds: Int { store.s.sessions.reduce(0) { $0 + $1.seconds } }
    private var running: Bool { store.s.runningSince != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PaneHeader(section: .desk)

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 18) {
                        Box(title: "IN PRODUCTION RIGHT NOW", key: "the one thing",
                            caption: "the clock runs on the company's time") {
                            VStack(alignment: .leading, spacing: 14) {
                                Field(text: $store.s.focus,
                                      placeholder: "What are you making, right now?",
                                      size: 22)
                                HStack(spacing: 18) {
                                    Text(hms(store.runningSeconds))
                                        .font(mono(34)).tracking(1)
                                        .foregroundColor(running ? p.pink : p.teal)
                                    PBtn(label: running ? "◼ CLOCK OUT" : "▶ CLOCK IN",
                                         tint: running ? p.pink : p.teal) { store.toggleSession() }
                                    Text("TODAY \(hms(todaySeconds))  ·  ALL TIME \(hms(allSeconds))")
                                        .font(mono(10)).foregroundColor(p.faint)
                                }
                            }
                        }

                        Box(title: "SESSION LOG", key: "what this desk has produced",
                            caption: "\(store.s.sessions.count) sessions logged") {
                            VStack(alignment: .leading, spacing: 2) {
                                if store.s.sessions.isEmpty {
                                    Text("No sessions yet. Clock in.")
                                        .font(mono(11)).foregroundColor(p.dim)
                                }
                                ForEach(store.s.sessions.suffix(9).reversed()) { s in
                                    HStack(spacing: 14) {
                                        Text(s.day).font(mono(10)).foregroundColor(p.dim)
                                        Text(hms(s.seconds)).font(mono(10)).foregroundColor(p.teal)
                                        Text(s.focus.isEmpty ? "—" : s.focus)
                                            .font(mono(10)).foregroundColor(p.ink)
                                            .lineLimit(1).truncationMode(.tail)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 18) {
                        Box(title: "THE MACHINES", key: "what this project requires",
                            caption: "whatever the active project requires — and nothing it doesn't") {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(store.s.tools) { tool in
                                    Row(glyph: {
                                            Text(tool.on ? "✓" : "·")
                                                .foregroundColor(tool.on ? p.teal2 : p.dark)
                                                .onTapGesture {
                                                    if let i = store.s.tools.firstIndex(where: { $0.id == tool.id }) {
                                                        store.s.tools[i].on.toggle()
                                                    }
                                                }
                                        },
                                        text: Binding(
                                            get: { store.s.tools.first(where: { $0.id == tool.id })?.text ?? "" },
                                            set: { v in
                                                if let i = store.s.tools.firstIndex(where: { $0.id == tool.id }) {
                                                    store.s.tools[i].text = v
                                                }
                                            }),
                                        onDelete: { store.s.tools.removeAll { $0.id == tool.id } })
                                }
                                Adder(placeholder: "+ a machine or material…") {
                                    store.s.tools.append(Tool($0))
                                }
                            }
                        }

                        Box(title: "THE RULE OF THE SURFACE") {
                            VStack(alignment: .leading, spacing: 3) {
                                ruleLine("No bills", false)
                                ruleLine("No random mail", false)
                                ruleLine("No personal clutter", false)
                                ruleLine("No unrelated browsing detritus", false)
                                ruleLine("You sit here to make ★★★★★ × PARADOX work", true)
                            }
                        }
                    }
                    .frame(width: 420, alignment: .leading)
                }
            }
            .padding(20)
        }
    }

    private func ruleLine(_ text: String, _ yes: Bool) -> some View {
        HStack(spacing: 8) {
            Text(yes ? "✓" : "×").foregroundColor(yes ? p.teal2 : p.dark)
            Text(text).foregroundColor(yes ? p.ink : p.faint)
        }
        .font(mono(11))
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - 03 THE TABLE
// ═══════════════════════════════════════════════════════════════════════════

struct TablePane: View {
    @EnvironmentObject var store: Store
    @Environment(\.p) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(section: .table, trailing: AnyView(
                PBtn(label: "+ LAY SOMETHING DOWN", tint: p.gold) { lay() }))

            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    // the surface's own grain, so things laid on it read as
                    // laid on something
                    Canvas { ctx, size in
                        let step: CGFloat = 26
                        var y: CGFloat = 6
                        while y < size.height {
                            var x: CGFloat = 6
                            while x < size.width {
                                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                                         with: .color(p.rule.opacity(0.16)))
                                x += step
                            }
                            y += step
                        }
                    }
                    .allowsHitTesting(false)

                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundColor(p.edge)

                    if store.s.table.isEmpty {
                        VStack(spacing: 8) {
                            Text("Nothing on the table.")
                            Text("Screenplays · storyboards · printouts · photographs · maps · scene structures · prototypes.")
                            Text("Lay them down, then drag them anywhere.")
                        }
                        .font(mono(11)).foregroundColor(p.dim)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    ForEach(store.s.table) { card in
                        CardView(card: card, bounds: geo.size)
                    }
                }
            }
        }
        .padding(20)
    }

    private func lay() {
        let n = store.s.table.count
        store.s.table.append(Card(x: 24 + Double(n % 5) * 70, y: 20 + Double(n % 7) * 46))
    }
}

struct CardView: View {
    @EnvironmentObject var store: Store
    @Environment(\.p) private var p
    var card: Card
    var bounds: CGSize
    @State private var drag: CGSize = .zero
    @State private var hover = false

    private var accent: Color {
        switch card.kind {
        case "SCRIPT": return p.gold
        case "IMAGE":  return p.pink
        case "OBJECT": return p.violet
        case "PLAN":   return p.teal2
        default:       return p.teal
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(card.kind).font(mono(9)).tracking(1.4).foregroundColor(p.gold)
                    .onTapGesture { cycleKind() }
                Spacer()
                Button(action: { store.s.table.removeAll { $0.id == card.id } }) {
                    Text("×").font(mono(11)).foregroundColor(hover ? p.pink : p.dark)
                }
                .buttonStyle(.plain)
            }
            // Dragging is grabbed from the header strip, so the text below
            // stays clickable for editing.
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { v in drag = v.translation }
                    .onEnded { v in
                        drag = .zero
                        if let i = store.s.table.firstIndex(where: { $0.id == card.id }) {
                            store.s.table[i].x = min(max(0, card.x + v.translation.width),
                                                     max(0, bounds.width - 250))
                            store.s.table[i].y = min(max(0, card.y + v.translation.height),
                                                     max(0, bounds.height - 60))
                        }
                    })

            Field(text: Binding(
                    get: { store.s.table.first(where: { $0.id == card.id })?.text ?? "" },
                    set: { v in
                        if let i = store.s.table.firstIndex(where: { $0.id == card.id }) {
                            store.s.table[i].text = v
                        }
                    }),
                  placeholder: "…", size: 11)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(width: 236, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 5).fill(p.titlebar.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(p.edge, lineWidth: 1))
        .overlay(alignment: .leading) {
            Rectangle().fill(accent).frame(width: 2)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .shadow(color: .black.opacity(0.45), radius: 9, y: 5)
        .offset(x: card.x + drag.width, y: card.y + drag.height)
        .onHover { hover = $0 }
    }

    private func cycleKind() {
        guard let i = store.s.table.firstIndex(where: { $0.id == card.id }) else { return }
        let kinds = Card.kinds
        let next = (kinds.firstIndex(of: card.kind).map { $0 + 1 } ?? 0) % kinds.count
        store.s.table[i].kind = kinds[next]
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - 04 THE ARSENAL
// ═══════════════════════════════════════════════════════════════════════════

struct ArsenalPane: View {
    @EnvironmentObject var store: Store
    @Environment(\.p) private var p

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PaneHeader(section: .arsenal)

                HStack(alignment: .top, spacing: 20) {
                    Box(title: "CURRENT STUDY", key: "in use now",
                        caption: "abundance without a visible shelf turns into diffusion") {
                        shelf(\.study, otherPath: \.arsenal, glyph: "◆", tint: p.teal,
                              hint: "The visible shelf is empty. Click ◇ in the arsenal to bring something here.",
                              adder: "+ what you are studying now…")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Box(title: "THE ARSENAL", key: "reference · everything the company holds",
                        caption: "\(store.s.arsenal.count) held · \(store.s.study.count) in study · REFERENCE ≠ CURRENT STUDY") {
                        shelf(\.arsenal, otherPath: \.study, glyph: "◇", tint: p.dark,
                              hint: "Film books · screenplays · literature · art books · game material · technical manuals · business material · physical media · past company work.",
                              adder: "+ add to the arsenal…")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func shelf(_ path: WritableKeyPath<AppState, [Item]>,
                       otherPath: WritableKeyPath<AppState, [Item]>,
                       glyph: String, tint: Color, hint: String, adder: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if store.s[keyPath: path].isEmpty {
                Text(hint).font(mono(11)).foregroundColor(p.dim).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(store.s[keyPath: path]) { item in
                Row(glyph: {
                        Text(glyph).foregroundColor(tint)
                            .onTapGesture { move(item, from: path, to: otherPath) }
                    },
                    text: Binding(
                        get: { store.s[keyPath: path].first(where: { $0.id == item.id })?.text ?? "" },
                        set: { v in
                            if let i = store.s[keyPath: path].firstIndex(where: { $0.id == item.id }) {
                                store.s[keyPath: path][i].text = v
                            }
                        }),
                    onDelete: { store.s[keyPath: path].removeAll { $0.id == item.id } })
            }
            Adder(placeholder: adder) { store.s[keyPath: path].append(Item($0)) }
        }
    }

    private func move(_ item: Item, from: WritableKeyPath<AppState, [Item]>,
                      to: WritableKeyPath<AppState, [Item]>) {
        guard let i = store.s[keyPath: from].firstIndex(where: { $0.id == item.id }) else { return }
        let moved = store.s[keyPath: from].remove(at: i)
        store.s[keyPath: to].append(moved)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - 05 THE REVIEW WALL
// ═══════════════════════════════════════════════════════════════════════════

struct ReviewPane: View {
    @EnvironmentObject var store: Store
    @Environment(\.p) private var p

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PaneHeader(section: .review, trailing: AnyView(
                    PBtn(label: "+ PIN UP WORK", tint: p.gold) {
                        store.s.review.insert(Pin(), at: 0)
                    }))

                (Text("The question is not ").foregroundColor(p.faint)
                 + Text("“do I like this”").foregroundColor(p.violet)
                 + Text(". It is ").foregroundColor(p.faint)
                 + Text("“is this good enough to leave the building with ★★★★★ × PARADOX on it?”")
                     .foregroundColor(p.violet))
                    .font(mono(11))

                if store.s.review.isEmpty {
                    Text("Nothing pinned up. Frames · character designs · UI screens · sequences · story beats · book pages · concept art · financial diagrams · launch materials.")
                        .font(mono(11)).foregroundColor(p.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 420), alignment: .top)],
                          alignment: .leading, spacing: 16) {
                    ForEach(store.s.review) { pin in
                        PinView(pin: pin)
                    }
                }
            }
            .padding(20)
        }
    }
}

struct PinView: View {
    @EnvironmentObject var store: Store
    @Environment(\.p) private var p
    var pin: Pin
    @State private var hover = false

    private var verdictColor: Color {
        switch pin.verdict {
        case "rework": return p.pink
        case "notyet": return p.gold
        default:       return p.faint
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(pin.kind).font(mono(9)).tracking(1.2).foregroundColor(p.violet)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(p.edge, lineWidth: 1))
                    .onTapGesture { cycleKind() }
                Text(pin.verdictLabel).font(mono(9)).tracking(1.2).foregroundColor(verdictColor)
                Spacer()
                Button(action: { store.s.review.removeAll { $0.id == pin.id } }) {
                    Text("×").font(mono(11)).foregroundColor(hover ? p.pink : p.dark)
                }
                .buttonStyle(.plain)
            }

            Field(text: Binding(
                    get: { store.s.review.first(where: { $0.id == pin.id })?.text ?? "" },
                    set: { v in
                        if let i = store.s.review.firstIndex(where: { $0.id == pin.id }) {
                            store.s.review[i].text = v
                        }
                    }),
                  placeholder: "what is pinned up here?", size: 12)

            HStack(spacing: 6) {
                verdictButton("HOLD", "hold")
                verdictButton("REWORK", "rework")
                verdictButton("NOT YET", "notyet")
                Button(action: { store.sendToCanon(pin) }) {
                    Text("→ CANON").font(mono(9)).tracking(1.2).foregroundColor(p.gold)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 3)
                            .stroke(p.gold.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.02)))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(p.edge, lineWidth: 1))
        .onHover { hover = $0 }
    }

    private func verdictButton(_ label: String, _ value: String) -> some View {
        let on = pin.verdict == value
        return Button(action: {
            if let i = store.s.review.firstIndex(where: { $0.id == pin.id }) {
                store.s.review[i].verdict = value
            }
        }) {
            Text(label).font(mono(9)).tracking(1.2)
                .foregroundColor(on ? p.ink : p.dim)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 3)
                    .fill(on ? p.violet.opacity(0.16) : .clear))
                .overlay(RoundedRectangle(cornerRadius: 3)
                    .stroke(on ? p.rule : p.edge, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func cycleKind() {
        guard let i = store.s.review.firstIndex(where: { $0.id == pin.id }) else { return }
        let kinds = Pin.kinds
        let next = (kinds.firstIndex(of: pin.kind).map { $0 + 1 } ?? 0) % kinds.count
        store.s.review[i].kind = kinds[next]
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Root
// ═══════════════════════════════════════════════════════════════════════════

struct RootView: View {
    @EnvironmentObject var store: Store
    @State private var shift = false

    var body: some View {
        ZStack {
            // the drifting gradient the whole house style sits on
            LinearGradient(colors: [store.palette.bg1, store.palette.bg2,
                                    store.palette.bg3, store.palette.bg4],
                           startPoint: shift ? .topLeading : .bottomTrailing,
                           endPoint: shift ? .bottomTrailing : .topLeading)
                .ignoresSafeArea()

            if store.crossed {
                RoomView().transition(.opacity)
            } else {
                ThresholdView().transition(.opacity)
            }
        }
        .environment(\.p, store.palette)
        .animation(.easeInOut(duration: 0.45), value: store.crossed)
        .onAppear {
            withAnimation(.easeInOut(duration: 26).repeatForever(autoreverses: true)) {
                shift = true
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - App
// ═══════════════════════════════════════════════════════════════════════════

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var window: NSWindow!

    func applicationDidFinishLaunching(_ note: Notification) {
        let root = RootView().environmentObject(store)

        // The window fills the screen it opens on — the room is the whole
        // surface — but stays an ordinary resizable window with its own
        // traffic lights. No chrome is drawn by the app.
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window = NSWindow(contentRect: frame,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "★★★★★ × PARADOX Command Centre"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.backgroundColor = NSColor(srgbRed: 0.055, green: 0.043, blue: 0.102, alpha: 1)
        window.minSize = NSSize(width: 900, height: 600)
        window.contentView = NSHostingView(rootView: root)
        window.setFrame(frame, display: true)

        NSApp.setActivationPolicy(.regular)
        if Store.testSection == nil {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // Verification run: render, but never take the screen from whoever
            // is actually using the Mac.
            window.orderBack(nil)
        }
        buildMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ note: Notification) { store.saveNow() }

    /// ⌘1–⌘5 walk the territories; ⌘⌫ leaves the room. Command-modified so they
    /// never collide with typing into the walls.
    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About ★★★★★ × PARADOX", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let roomItem = NSMenuItem()
        let roomMenu = NSMenu(title: "Room")
        for s in Section.allCases {
            let it = NSMenuItem(title: "\(s.number)  \(s.label)", action: #selector(goTo(_:)),
                                keyEquivalent: "\(s.rawValue + 1)")
            it.target = self
            it.tag = s.rawValue
            roomMenu.addItem(it)
        }
        roomMenu.addItem(.separator())
        let leave = NSMenuItem(title: "Leave the room", action: #selector(leaveRoom), keyEquivalent: "\u{8}")
        leave.target = self
        roomMenu.addItem(leave)
        roomItem.submenu = roomMenu
        main.addItem(roomItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    @objc private func goTo(_ sender: NSMenuItem) {
        guard let s = Section(rawValue: sender.tag) else { return }
        if !store.crossed { store.cross() }
        store.section = s
    }

    @objc private func leaveRoom() { store.leave() }
}

@main
enum CommandCentre {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Held for the process lifetime: NSApplication's delegate is unowned.
        objc_setAssociatedObject(app, "cc.delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        app.run()
    }
}
