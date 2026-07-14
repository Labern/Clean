import Foundation

// ── gestures ─────────────────────────────────────────────────────────────

enum Gesture: String, CaseIterable, Codable, Identifiable {
    // single hand
    case one, two, three, four, palm, fist, thumbsUp, rock, callMe, okSign
    // both hands
    case twoPalms, twoFists, twoThumbsUp, palmAndFist

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .one: return "☝️"
        case .two: return "✌️"
        case .three: return "🤟"
        case .four: return "🖖"
        case .palm: return "🖐"
        case .fist: return "✊"
        case .thumbsUp: return "👍"
        case .rock: return "🤘"
        case .callMe: return "🤙"
        case .okSign: return "👌"
        case .twoPalms: return "🖐🖐"
        case .twoFists: return "✊✊"
        case .twoThumbsUp: return "👍👍"
        case .palmAndFist: return "🖐✊"
        }
    }

    var title: String {
        switch self {
        case .one: return "One finger"
        case .two: return "Two fingers"
        case .three: return "Three fingers"
        case .four: return "Four fingers"
        case .palm: return "Open palm"
        case .fist: return "Fist"
        case .thumbsUp: return "Thumbs up"
        case .rock: return "Rock sign"
        case .callMe: return "Call me"
        case .okSign: return "OK sign"
        case .twoPalms: return "Both palms"
        case .twoFists: return "Both fists"
        case .twoThumbsUp: return "Both thumbs up"
        case .palmAndFist: return "Palm + fist"
        }
    }

    var hint: String {
        switch self {
        case .one: return "index up, others folded"
        case .two: return "index + middle up"
        case .three: return "index + middle + ring up"
        case .four: return "four fingers up, thumb tucked"
        case .palm: return "all five spread"
        case .fist: return "closed fist, hand upright"
        case .thumbsUp: return "fist with thumb on top"
        case .rock: return "index + pinky up"
        case .callMe: return "thumb + pinky out (shaka)"
        case .okSign: return "thumb–index circle, rest up"
        case .twoPalms: return "open palm on both hands"
        case .twoFists: return "fist on both hands"
        case .twoThumbsUp: return "thumbs up on both hands"
        case .palmAndFist: return "one palm, one fist"
        }
    }

    var isTwoHanded: Bool {
        switch self {
        case .twoPalms, .twoFists, .twoThumbsUp, .palmAndFist: return true
        default: return false
        }
    }
}

// ── actions ──────────────────────────────────────────────────────────────

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case none, app, url, shell, deck
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Nothing"
        case .app: return "Open app"
        case .url: return "Open URL"
        case .shell: return "Shell command"
        case .deck: return "GestureDeck window"
        }
    }
    /// kinds that need a value typed/picked before they can run
    var needsValue: Bool { self == .app || self == .url || self == .shell }
}

struct GestureAction: Codable, Equatable {
    var kind: ActionKind = .none
    var value: String = ""
    var enabled: Bool = true
    var repeats: Bool = false   // hold the pose → keyboard-style auto-repeat

    init(kind: ActionKind = .none, value: String = "", enabled: Bool = true, repeats: Bool = false) {
        self.kind = kind; self.value = value; self.enabled = enabled; self.repeats = repeats
    }

    // tolerate configs written before newer fields existed — a missing key
    // must never invalidate the whole saved actions dictionary
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decode(ActionKind.self, forKey: .kind)) ?? .none
        value = (try? c.decode(String.self, forKey: .value)) ?? ""
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        repeats = (try? c.decode(Bool.self, forKey: .repeats)) ?? false
    }

    enum CodingKeys: String, CodingKey { case kind, value, enabled, repeats }

    var summary: String {
        switch kind {
        case .none: return "nothing"
        case .app: return value.isEmpty ? "app?" : value
        case .url: return value.isEmpty ? "url?" : value
        case .shell: return value.isEmpty ? "cmd?" : "$ " + value
        case .deck: return "gesture window"
        }
    }
}

// ── persisted configuration ──────────────────────────────────────────────

struct Config: Codable {
    // bump when defaultActions change so existing configs pick them up
    static let currentDefaultsVersion = 3

    var enabled = true
    var soundOn = true
    var soundName = "Pop"
    var holdSeconds = 0.12
    var cooldownSeconds = 0.0   // 0 = no cooldown, fire freely

    var actions: [String: GestureAction] = Config.defaultActions
    var defaultsVersion = Config.currentDefaultsVersion

    static let soundChoices = ["Pop", "Glass", "Tink", "Ping", "Funk", "Purr", "Submarine", "Bottle"]

    static let defaultActions: [String: GestureAction] = [
        Gesture.one.rawValue: GestureAction(kind: .url, value: "https://chatgpt.com"),
        Gesture.two.rawValue: GestureAction(kind: .app, value: "Claude"),
        Gesture.three.rawValue: GestureAction(kind: .app, value: "Spotify"),
        Gesture.four.rawValue: GestureAction(kind: .app, value: "Obsidian"),
        Gesture.palm.rawValue: GestureAction(kind: .url, value: "https://labern.github.io/Clean/gesture/"),
        Gesture.fist.rawValue: GestureAction(kind: .shell,
            value: "osascript -e 'tell application \"Spotify\" to playpause'"),
    ]

    enum CodingKeys: String, CodingKey {
        case enabled, soundOn, soundName, holdSeconds, cooldownSeconds, actions, defaultsVersion
    }

    init() {}

    // tolerate configs written by older/newer versions
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        soundOn = (try? c.decode(Bool.self, forKey: .soundOn)) ?? true
        soundName = (try? c.decode(String.self, forKey: .soundName)) ?? "Pop"
        holdSeconds = (try? c.decode(Double.self, forKey: .holdSeconds)) ?? 0.12
        cooldownSeconds = (try? c.decode(Double.self, forKey: .cooldownSeconds)) ?? 0.0
        actions = (try? c.decode([String: GestureAction].self, forKey: .actions)) ?? Config.defaultActions
        defaultsVersion = (try? c.decode(Int.self, forKey: .defaultsVersion)) ?? 1
    }

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GestureDeck", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: fileURL),
              var cfg = try? JSONDecoder().decode(Config.self, from: data) else { return Config() }
        // migrate old configs in place — the user should never have to
        // delete anything to pick up new default mappings or new gestures
        if cfg.defaultsVersion < currentDefaultsVersion {
            for (key, action) in defaultActions { cfg.actions[key] = action }
            if cfg.defaultsVersion < 3 {
                // v3: instant response — only ever speed up, never undo a
                // faster setting the user already chose
                cfg.holdSeconds = min(cfg.holdSeconds, 0.12)
                cfg.cooldownSeconds = 0.0
            }
            cfg.defaultsVersion = currentDefaultsVersion
            cfg.save()
        }
        for (key, action) in defaultActions where cfg.actions[key] == nil {
            cfg.actions[key] = action
        }
        return cfg
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) {
            try? data.write(to: Config.fileURL, options: .atomic)
        }
    }
}
