import Foundation

// MARK: - Theme groups (Bubbles tab grouping)

public struct ThemeGroup: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let bubbles: [ThemeBubble]
    public init(id: String, name: String, bubbles: [ThemeBubble]) {
        self.id = id; self.name = name; self.bubbles = bubbles
    }
}

public func groupBubbles(_ bubbles: [ThemeBubble]) -> [ThemeGroup] {
    typealias GroupDef = (id: String, name: String, keywords: [String])
    let defs: [GroupDef] = [
        // Dating dynamics, attachment styles, communication patterns — avoidant,
        // messages, meetings all belong here because they arise in the context of
        // dating/relationship conversations, not work.
        ("people", "People & Relationships", [
            "woman", "women", "girl", "girls", "romance", "romantic", "dating", "date",
            "relationship", "relationships", "love", "sex", "sexual", "attraction", "attract",
            "partner", "girlfriend", "boyfriend", "wife", "husband", "marriage", "marry",
            "family", "friend", "friends", "social", "people", "person", "trust", "flirt",
            "jealous", "couple", "bonding", "intimacy", "affection", "match", "tinder",
            "sarah", "mother", "father", "sister", "brother", "daughter", "son",
            "man", "men", "male", "female", "gender", "connection", "attachment",
            // attachment styles & dating behaviours
            "avoidant", "anxious attach", "secure", "dismissive", "fearful",
            "avoidance", "detach", "distant", "withdraw", "breadcrumb",
            // communication in relationship context
            "message", "messages", "messaging", "text", "texting", "reply", "replies",
            "read receipt", "left on read", "ghosting", "ghost",
            // meetings in dating/social context
            "meeting", "meetings", "meet", "coffee", "dinner", "date night",
            "first date", "second date", "seeing someone",
            // attraction/compatibility terms
            "vibe", "chemistry", "compatibility", "type", "red flag", "green flag",
            "situationship", "talking stage", "exclusive"
        ]),
        // Cars specifically: engine diagnostics, makes/models, repairs, driving.
        // Cylinder, misfire, spark plug, trough (RPM trough), headache (car problem)
        // all belong here — these are automotive fault-finding terms.
        ("cars", "Cars & Transport", [
            "car", "cars", "vehicle", "vehicles", "truck", "suv", "sedan", "coupe",
            "drive", "driving", "drove", "engine", "tire", "tyre", "wheel", "wheels",
            "tesla", "bmw", "ford", "honda", "toyota", "audi", "mercedes", "porsche",
            "electric vehicle", "hybrid", "petrol", "diesel", "fuel", "mpg",
            // engine diagnostics — the core of the user's feedback
            "cylinder", "cylinders", "misfire", "misfiring", "spark plug", "spark plugs",
            "ignition", "coil", "piston", "compression", "exhaust", "catalytic",
            "obd", "dtc", "p0300", "check engine", "rough idle", "idle",
            "trough",        // RPM trough / power trough = engine symptom
            "headache",      // car headache = fault/problem in this context
            "mechanic", "garage", "workshop", "service", "repair", "parts",
            "battery", "alternator", "starter", "coolant", "radiator", "thermostat",
            "transmission", "gearbox", "clutch", "brake", "suspension", "steering",
            "oil", "filter", "flush", "mileage", "odometer", "mot", "registration"
        ]),
        // Everything else practical: money, health, home, food, fitness
        ("life", "Practical Life", [
            "money", "finance", "budget", "cost", "price", "insurance", "mortgage",
            "rent", "house", "home", "apartment", "property", "health", "medical",
            "doctor", "gym", "diet", "food", "sleep", "body", "travel", "shopping",
            "cooking", "fitness", "weight", "energy", "routine", "errand", "city",
            "moving", "physical", "nutrition", "schedule", "habit"
        ]),
        // Code, CLI, software — Command*, Local Command, Stdout, Connectors, Exit all here.
        // "command" as a prefix unambiguously means CLI/terminal work in this dataset.
        ("work", "Work & Building", [
            "swift", "swiftui", "code", "coding", "app", "build", "xcode", "github",
            "project", "function", "struct", "class", "server", "api", "database",
            "deploy", "feature", "bug", "test", "business", "job", "career", "work",
            "startup", "product", "interface", "software", "program", "script", "task",
            "system", "tool", "workflow", "service", "backend", "frontend", "component",
            "command", "local command", "command args", "command message", "command caveat",
            "command stdout", "exit message", "connectors", "connector",
            "strata", "heatmap", "terminal", "shell", "bash", "python",
            "javascript", "typescript", "react", "node", "package", "module",
            "debug", "error", "fix", "refactor", "commit", "branch", "merge",
            "pull", "push", "release", "version", "docs", "documentation"
        ]),
        // Personal psychology, emotional states, self-reflection
        ("mind", "Mind & Self", [
            "anxiety", "anxious", "mood", "feeling", "emotion", "self", "identity",
            "worth", "confidence", "therapy", "mental", "thought", "belief", "pattern",
            "habit", "psychology", "mindset", "ego", "meaning", "purpose", "value",
            "fear", "trauma", "shame", "pride", "anger", "sadness", "grief", "joy",
            "depression", "wellbeing", "spiritual", "growth", "aware", "awareness",
            "reflect", "reflection", "introspect", "consciousness", "detective"
        ]),
        ("creative", "Creative & Learning", [
            "music", "writing", "write", "art", "film", "movie", "reading", "read",
            "learning", "learn", "book", "books", "study", "research", "idea", "ideas",
            "creative", "story", "stories", "language", "paint", "drawing", "draw",
            "compose", "composition", "explore", "discover", "photography", "photo",
            "video", "podcast", "essay", "design", "fiction", "poetry", "poem",
            "craft", "skill", "practice", "teach", "knowledge", "curiosity",
            "four months", "voice data", "voice note"
        ]),
        // AI models, products, hardware — Pro Max (iPhone/Mac model), Sonnet (Claude model),
        // Keyboard/Voice Note as Apple input peripherals
        ("ai", "AI & Technology", [
            "claude", "gpt", "llm", "model", "prompt", "chatgpt", "conversation",
            "agent", "anthropic", "openai", "gemini", "intelligence", "machine",
            "neural", "context", "token", "inference", "embedding", "fine tuning",
            "cursor", "copilot", "automation", "generation",
            // Apple product names that surface as themes
            "pro max", "sonnet", "opus", "haiku",
            "iphone", "ipad", "mac", "macbook", "apple",
            // Peripherals / input
            "keyboard", "voice note", "microphone", "speaker"
        ]),
    ]

    // Substring-aware scoring: a keyword matches if it appears anywhere in the
    // theme label (or the theme appears in a multi-word keyword). This handles
    // bigrams like "Pro Max", "Command Args", "Four Months" and proper nouns.
    func matchScore(_ theme: String, _ keywords: [String]) -> Int {
        let t = theme.lowercased()
        var score = 0
        for kw in keywords {
            let k = kw.lowercased()
            // exact word boundary check inside theme, or theme inside keyword
            if t.contains(k) || k.contains(t) { score += 1 }
        }
        return score
    }

    var buckets: [String: [ThemeBubble]] = Dictionary(uniqueKeysWithValues: defs.map { ($0.id, [ThemeBubble]()) })
    buckets["other"] = []

    for bubble in bubbles {
        var best = "other"; var bestScore = 0
        for d in defs {
            let s = matchScore(bubble.theme, d.keywords)
            if s > bestScore { bestScore = s; best = d.id }
        }
        buckets[best, default: []].append(bubble)
    }

    var result: [ThemeGroup] = []
    for d in defs {
        if let bs = buckets[d.id], !bs.isEmpty {
            result.append(ThemeGroup(id: d.id, name: d.name, bubbles: bs))
        }
    }
    if let other = buckets["other"], !other.isEmpty {
        result.append(ThemeGroup(id: "other", name: "Other", bubbles: other))
    }
    return result
}

// MARK: - Theme bubbles (primary visualization)

public struct ThemeBubble: Identifiable, Sendable {
    public let id: String
    public let theme: String
    public let totalWeight: Double
    public let distinctConversationCount: Int   // how many unique convs contain this theme
    public let allContributorIds: [String]
    /// Spread score: rewards themes that recur across many conversations over time,
    /// not just ones that dominated a single long session.
    public var spreadScore: Double {
        let n = Double(max(1, distinctConversationCount))
        return n * log(1.0 + totalWeight / n)
    }
    public init(theme: String, totalWeight: Double, distinctConversationCount: Int, allContributorIds: [String]) {
        self.id = theme; self.theme = theme
        self.totalWeight = totalWeight
        self.distinctConversationCount = distinctConversationCount
        self.allContributorIds = allContributorIds
    }
}

public func buildBubbles(from matrix: HeatmapMatrix) -> [ThemeBubble] {
    var weights: [String: Double] = [:]
    var ids: [String: Set<String>] = [:]
    for (r, theme) in matrix.themes.enumerated() {
        for c in 0..<matrix.buckets.count {
            let cell = matrix.cells[r][c]
            weights[theme, default: 0] += cell.weight
            cell.contributors.forEach { ids[theme, default: []].insert($0) }
        }
    }
    return matrix.themes.compactMap { theme -> ThemeBubble? in
        let w = weights[theme] ?? 0
        guard w > 0 else { return nil }
        let convIds = Array(ids[theme] ?? [])
        return ThemeBubble(theme: theme, totalWeight: w,
                           distinctConversationCount: convIds.count,
                           allContributorIds: convIds)
    }.sorted { $0.spreadScore > $1.spreadScore }   // persistent themes rank highest
}

// MARK: - Heatmap matrix (kept for time-bucketed drill-down)

public enum BucketSize: String, CaseIterable, Identifiable, Sendable {
    case day, week, month
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    var component: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }
}

public struct TimeBucket: Identifiable, Hashable, Sendable {
    public let id: Int
    public let start: Date
    public let label: String   // full, for drill-down ("Wk of May 4, 2026")
    public let short: String   // compact, for the x-axis ("5/4")
}

public struct HeatmapCell: Sendable {
    public let weight: Double
    public let contributors: [String]   // conversation ids feeding this cell
}

// MARK: - Theme sort order

public enum ThemeSort: String, CaseIterable, Identifiable, Sendable {
    case frequencyDesc  = "Most frequent"
    case frequencyAsc   = "Least frequent"
    case alphabetical   = "A → Z"
    case alphabeticalRev = "Z → A"
    case chronoDesc     = "Recent first"
    case chronoAsc      = "Oldest first"
    public var id: String { rawValue }
}

public struct HeatmapMatrix: Sendable {
    public let themes: [String]          // row labels (display, title-cased)
    public let buckets: [TimeBucket]     // columns
    public let cells: [[HeatmapCell]]    // [row][col]
    public let maxWeight: Double
    public let conversationCount: Int

    public func normalized(_ row: Int, _ col: Int) -> Double {
        guard maxWeight > 0, row < cells.count, col < cells[row].count else { return 0 }
        return cells[row][col].weight / maxWeight
    }

    /// Return a copy with rows reordered according to the chosen sort.
    public func sorted(by sort: ThemeSort) -> HeatmapMatrix {
        let indices: [Int]
        switch sort {
        case .frequencyDesc:
            // Default order — rows are already sorted by total weight desc
            indices = Array(0..<themes.count)
        case .frequencyAsc:
            indices = Array(0..<themes.count).reversed()
        case .alphabetical:
            indices = themes.indices.sorted { themes[$0].lowercased() < themes[$1].lowercased() }
        case .alphabeticalRev:
            indices = themes.indices.sorted { themes[$0].lowercased() > themes[$1].lowercased() }
        case .chronoDesc:
            // "Chronological intensity": last bucket with any activity, most recent first
            indices = themes.indices.sorted { a, b in
                let lastA = cells[a].indices.reversed().first { cells[a][$0].weight > 0 } ?? -1
                let lastB = cells[b].indices.reversed().first { cells[b][$0].weight > 0 } ?? -1
                return lastA > lastB
            }
        case .chronoAsc:
            indices = themes.indices.sorted { a, b in
                let firstA = cells[a].indices.first { cells[a][$0].weight > 0 } ?? Int.max
                let firstB = cells[b].indices.first { cells[b][$0].weight > 0 } ?? Int.max
                return firstA < firstB
            }
        }
        let newThemes = indices.map { themes[$0] }
        let newCells  = indices.map { cells[$0] }
        return HeatmapMatrix(themes: newThemes, buckets: buckets, cells: newCells,
                             maxWeight: maxWeight, conversationCount: conversationCount)
    }
}

public func buildMatrix(conversations: [Conversation],
                        themes: [ConversationThemes],
                        bucket: BucketSize,
                        topThemeCount: Int = 200) -> HeatmapMatrix {
    let empty = HeatmapMatrix(themes: [], buckets: [], cells: [], maxWeight: 0, conversationCount: conversations.count)
    let cal = Calendar.current
    let convByID = Dictionary(conversations.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let valid = themes.filter { convByID[$0.id] != nil }
    guard !valid.isEmpty else { return empty }

    let dates = valid.compactMap { convByID[$0.id]?.lastTimestamp }.filter { $0 > Date.distantPast }
    guard let minDate = dates.min(), let maxDate = dates.max() else { return empty }

    func bucketStart(_ d: Date) -> Date {
        cal.dateInterval(of: bucket.component, for: d)?.start ?? d
    }

    // enumerate columns from first to last bucket
    var bucketStarts: [Date] = []
    var cur = bucketStart(minDate)
    let end = bucketStart(maxDate)
    var guardCount = 0
    while cur <= end, guardCount < 5000 {
        bucketStarts.append(cur)
        guard let next = cal.date(byAdding: bucket.component, value: 1, to: cur) else { break }
        cur = next
        guardCount += 1
    }
    if bucketStarts.isEmpty { bucketStarts = [bucketStart(minDate)] }
    let indexByStart = Dictionary(uniqueKeysWithValues: bucketStarts.enumerated().map { ($1, $0) })

    // accumulate weights per theme per column
    var weights: [String: [Int: Double]] = [:]
    var contributors: [String: [Int: [String]]] = [:]
    var totalByTheme: [String: Double] = [:]
    for ct in valid {
        guard let conv = convByID[ct.id] else { continue }
        let col = indexByStart[bucketStart(conv.lastTimestamp)] ?? 0
        for term in ct.terms {
            weights[term.label, default: [:]][col, default: 0] += term.weight
            contributors[term.label, default: [:]][col, default: []].append(ct.id)
            totalByTheme[term.label, default: 0] += term.weight
        }
    }

    // Deduplicate terms that collide after titleCase (e.g. "bpd" and "BPD" both → "Bpd").
    // Keep the highest-weight variant; drop the rest.
    var deduped: [String: String] = [:]  // lowercased key → canonical raw label
    for (label, weight) in totalByTheme.sorted(by: { $0.value > $1.value }) {
        let key = label.lowercased()
        if deduped[key] == nil { deduped[key] = label }
        // If already seen, merge weight into the canonical label
        else if deduped[key] != label {
            totalByTheme[deduped[key]!, default: 0] += weight
            totalByTheme[label] = 0
        }
    }
    let topThemes = totalByTheme.sorted { $0.value > $1.value }.prefix(topThemeCount).map { $0.key }
    let buckets = bucketStarts.enumerated().map { idx, start -> TimeBucket in
        let labels = makeLabels(start, bucket)
        return TimeBucket(id: idx, start: start, label: labels.full, short: labels.short)
    }

    var cells: [[HeatmapCell]] = []
    var maxW = 0.0
    for theme in topThemes {
        var row: [HeatmapCell] = []
        for c in 0..<bucketStarts.count {
            let w = weights[theme]?[c] ?? 0
            maxW = max(maxW, w)
            row.append(HeatmapCell(weight: w, contributors: contributors[theme]?[c] ?? []))
        }
        cells.append(row)
    }

    return HeatmapMatrix(themes: topThemes.map(titleCase),
                         buckets: buckets, cells: cells,
                         maxWeight: maxW, conversationCount: conversations.count)
}

private func titleCase(_ s: String) -> String {
    s.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
}

private func makeLabels(_ d: Date, _ b: BucketSize) -> (full: String, short: String) {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    switch b {
    case .day:
        f.dateFormat = "MMMM d, yyyy"; let full = f.string(from: d)
        f.dateFormat = "MMMM d"; return (full, f.string(from: d))
    case .week:
        f.dateFormat = "MMMM d, yyyy"; let full = "Wk of " + f.string(from: d)
        f.dateFormat = "MMMM d"; return (full, f.string(from: d))
    case .month:
        f.dateFormat = "MMMM yyyy"; let full = f.string(from: d)
        f.dateFormat = "MMMM yyyy"; return (full, f.string(from: d))
    }
}
