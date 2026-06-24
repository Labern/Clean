import SwiftUI
import AppKit
import StrataCore

// MARK: - Tab enum

enum StrataTab: String, CaseIterable {
    case timeline = "Timeline"
    case themes   = "Themes"
}

// MARK: - Root view

struct HeatmapView: View {
    @StateObject private var model = HeatmapModel()
    @State private var tab: StrataTab = .timeline
    @State private var bubblesGrouped = true

    var body: some View {
        ZStack {
            LinearGradient(colors: [.bgDeep, .bgMid, .bgDeep],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                Divider().background(Color.white.opacity(0.08))

                Group {
                    switch tab {
                    case .timeline: timelineBody
                    case .themes:   themesBody
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .sheet(item: $model.selected) { ConversationListView(sel: $0) }
        }
        .onAppear { model.start() }
    }

    // MARK: - header

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Strata")
                    .font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                Text(model.statusText)
                    .font(.system(size: 17)).foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            // Tab switcher
            HStack(spacing: 0) {
                ForEach(StrataTab.allCases, id: \.self) { t in
                    Button(t.rawValue) { withAnimation(.easeInOut(duration: 0.15)) { tab = t } }
                        .buttonStyle(TabButtonStyle(active: tab == t))
                }
            }
            .background(Capsule().fill(Color.white.opacity(0.07)))
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))

            // Bucket picker — only meaningful on timeline
            if tab == .timeline {
                Picker("", selection: Binding(get: { model.bucket }, set: { model.changeBucket($0) })) {
                    ForEach(BucketSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            // Max subjects stepper
            HStack(spacing: 6) {
                Text("Subjects:")
                    .font(.system(size: 17)).foregroundStyle(.white.opacity(0.45))
                Stepper(
                    value: Binding(
                        get: { model.topThemeCount },
                        set: { model.changeTopThemeCount($0) }
                    ),
                    in: 10...500, step: 10
                ) {
                    Text("\(model.topThemeCount)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(minWidth: 28, alignment: .trailing)
                }
                .controlSize(.small)
            }

            if model.isSyncing { ProgressView().controlSize(.small).tint(.accentTeal) }

            if model.needsLogin {
                Button("Connect claude.ai") { model.showLogin() }
                    .buttonStyle(.borderedProminent).tint(.accentViolet)
            }

            Button { Task { await model.syncFromWeb() } } label: {
                Image(systemName: "arrow.clockwise").foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain).disabled(model.isSyncing).help("Sync now")
        }
    }

    // MARK: - tab bodies

    @ViewBuilder
    private var timelineBody: some View {
        if let m = model.matrix, !m.themes.isEmpty {
            TimelineTabView(
                matrix: m.sorted(by: model.themeSort),
                sort: Binding(get: { model.themeSort }, set: { model.changeThemeSort($0) }),
                onSelect: { model.select(row: $0, col: $1) },
                onSelectTheme: { model.selectTheme($0) }
            )
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private var themesBody: some View {
        if !model.bubbles.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Picker("", selection: $bubblesGrouped) {
                        Text("Grouped").tag(true)
                        Text("All").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    .padding(.horizontal, 22)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                }
                if bubblesGrouped {
                    GroupedBubblesView(
                        groups: groupBubbles(model.bubbles),
                        onTap: { model.select(bubble: $0) }
                    )
                } else {
                    BubblesCanvas(bubbles: model.bubbles) { model.select(bubble: $0) }
                }
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            if model.isSyncing {
                ProgressView().controlSize(.large).tint(.accentTeal)
                Text("Syncing conversations…").font(.system(size: 16)).foregroundStyle(.white.opacity(0.55))
            } else if model.needsLogin {
                Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 52))
                    .foregroundStyle(.white.opacity(0.2))
                Text("Connect claude.ai to include all your conversations")
                    .font(.system(size: 17)).foregroundStyle(.white.opacity(0.7))
                Button("Connect claude.ai") { model.showLogin() }
                    .buttonStyle(.borderedProminent).tint(.accentViolet)
            } else {
                ProgressView().controlSize(.large).tint(.accentTeal)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Tab button style

struct TabButtonStyle: ButtonStyle {
    let active: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? .white : Color.white.opacity(0.5))
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(active ? Capsule().fill(Color.white.opacity(0.16)) : nil)
    }
}

// MARK: - Timeline tab (theme × time heatmap)

struct TimelineTabView: View {
    let matrix: HeatmapMatrix
    @Binding var sort: ThemeSort
    let onSelect: (Int, Int) -> Void
    let onSelectTheme: (Int) -> Void

    @State private var searchText: String = ""

    /// Rows that match the search — returns all indices when search is empty.
    private var matchingIndices: Set<Int> {
        guard !searchText.isEmpty else { return Set(matrix.themes.indices) }
        let q = searchText.lowercased()
        return Set(matrix.themes.indices.filter { matrix.themes[$0].lowercased().contains(q) })
    }

    private let labelW: CGFloat = 240
    private let cellSize: CGFloat = 36
    private let gap: CGFloat = 4
    private let headerH: CGFloat = 46
    private let colW: CGFloat = 84

    var body: some View {
        // Single GeometryReader so controls bar and grid share the same 5% sidePad.
        GeometryReader { geo in
        let sidePad = geo.size.width * 0.05
        VStack(spacing: 0) {
            // ── Controls bar: sort + search ──────────────────────────────────
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Text("Order:")
                        .font(.system(size: 13, design: .monospaced)).foregroundStyle(.white.opacity(0.45))
                    Picker("", selection: $sort) {
                        ForEach(ThemeSort.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                // Search bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                    TextField("Filter themes…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(width: 200)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.12), lineWidth: 1))

                if !searchText.isEmpty {
                    Text("\(matchingIndices.count) of \(matrix.themes.count)")
                        .font(.system(size: 13, design: .monospaced)).foregroundStyle(.white.opacity(0.4))
                }

                Spacer()
            }
            .padding(.horizontal, sidePad)
            .padding(.vertical, 8)

            // Outer vertical scroll — label column pinned left, cells scroll horizontally.
            // 5% padding each side so the grid occupies 90% of the app width.
                ScrollView(.vertical, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 0) {

                        // ── Sticky label column ──────────────────────────────────────
                        VStack(alignment: .trailing, spacing: gap) {
                            Color.clear.frame(width: labelW, height: headerH)
                            ForEach(Array(matrix.themes.enumerated()), id: \.offset) { r, theme in
                                let matched = matchingIndices.contains(r)
                                Button { onSelectTheme(r) } label: {
                                    Text(theme)
                                        .font(.system(size: 15, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(matched ? 0.92 : 0.18))
                                        .lineLimit(1).truncationMode(.tail)
                                        .frame(width: labelW, height: cellSize, alignment: .trailing)
                                }
                                .buttonStyle(.plain)
                                .help("Show all \"\(theme)\" conversations")
                            }
                        }
                        .overlay(alignment: .trailing) {
                            LinearGradient(colors: [.clear, Color.bgMid.opacity(0.0)],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(width: 8)
                        }
                        .padding(.trailing, 6)
                        .background(
                            LinearGradient(colors: [.bgDeep, .bgMid],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                            .ignoresSafeArea()
                        )
                        .zIndex(10)

                        // ── Horizontally scrollable cell grid ────────────────────────
                        ScrollView(.horizontal, showsIndicators: true) {
                            VStack(alignment: .leading, spacing: gap) {
                                // Column headers
                                HStack(spacing: gap) {
                                    ForEach(matrix.buckets) { b in
                                        Text(b.short)
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(Color.accentTeal.opacity(0.65))
                                            .multilineTextAlignment(.center)
                                            .lineLimit(2)
                                            .frame(width: colW, height: headerH, alignment: .bottom)
                                            .padding(.bottom, 4)
                                    }
                                }
                                // Data rows
                                ForEach(Array(matrix.themes.enumerated()), id: \.offset) { r, theme in
                                    let matched = matchingIndices.contains(r)
                                    HStack(spacing: gap) {
                                        ForEach(0..<matrix.buckets.count, id: \.self) { c in
                                            let t = matrix.normalized(r, c)
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(heatmapColor(t))
                                                .frame(width: colW, height: cellSize)
                                                .overlay(RoundedRectangle(cornerRadius: 4)
                                                    .stroke(.white.opacity(0.06), lineWidth: 1))
                                                .opacity(matched ? 1.0 : 0.12)
                                                .onTapGesture { if matched { onSelect(r, c) } }
                                                .help(t > 0 && matched ? "\(theme) · \(matrix.buckets[c].label)" : "")
                                        }
                                    }
                                }
                            }
                            .padding(.trailing, sidePad)
                        }
                    }
                    .padding(.leading, sidePad)
                    .padding(.vertical, 16)
                }
            }
        .safeAreaInset(edge: .bottom) {
            GeometryReader { geo in
                HStack(spacing: 8) {
                    Text("less").font(.system(size: 16)).foregroundStyle(.white.opacity(0.4))
                    LinearGradient(colors: [.accentTeal, .accentViolet, .accentPink],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 160, height: 7).clipShape(Capsule())
                    Text("more").font(.system(size: 16)).foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    Text("tap a cell to see conversations")
                        .font(.system(size: 16)).foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, geo.size.width * 0.05)
                .padding(.vertical, 10)
            }
            .frame(height: 36)
            .background(Color.bgDeep.opacity(0.85))
        }
        } // end VStack
    }
}

/// Single teal → violet → pink ramp used by both the heatmap and bubble views.
private func accentRamp(_ t: Double) -> Color {
    let tt = max(0, min(1, t))
    let teal = (0.369, 0.918, 0.831); let violet = (0.655, 0.545, 0.980); let pink = (0.957, 0.447, 0.714)
    func lerp(_ a: Double, _ b: Double, _ k: Double) -> Double { a + (b - a) * k }
    let rgb: (Double, Double, Double)
    if tt < 0.5 { let k = tt / 0.5; rgb = (lerp(teal.0,violet.0,k), lerp(teal.1,violet.1,k), lerp(teal.2,violet.2,k)) }
    else         { let k = (tt-0.5)/0.5; rgb = (lerp(violet.0,pink.0,k), lerp(violet.1,pink.1,k), lerp(violet.2,pink.2,k)) }
    return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
}

private func heatmapColor(_ t: Double) -> Color { accentRamp(t).opacity(t == 0 ? 0.07 : 0.25 + 0.75 * t) }

// MARK: - Bubbles tab

struct BubblesCanvas: View {
    let bubbles: [ThemeBubble]
    let onTap: (ThemeBubble) -> Void

    var body: some View {
        GeometryReader { geo in
            let layout = BubbleLayout(bubbles: bubbles, canvasSize: geo.size)
            ZStack {
                ForEach(Array(bubbles.enumerated()), id: \.element.id) { i, bubble in
                    let t = Double(i) / Double(max(1, bubbles.count - 1))
                    BubbleView(bubble: bubble, radius: layout.radii[i], colorT: 1.0 - t)
                        .position(layout.centers[i])
                        .onTapGesture { onTap(bubble) }
                }
            }
        }
        .padding(.bottom, 16)
    }
}

struct BubbleView: View {
    let bubble: ThemeBubble
    let radius: CGFloat
    let colorT: Double

    var body: some View {
        ZStack {
            Circle().fill(bubbleColor(colorT).opacity(0.22 + 0.55 * colorT))
            Circle().stroke(bubbleColor(colorT).opacity(0.45 + 0.35 * colorT), lineWidth: 1.5)
            Text(bubble.theme)
                .font(.system(size: labelSize, weight: radius > 55 ? .semibold : .regular))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(radius * 0.2)
        }
        .frame(width: radius * 2, height: radius * 2)
    }

    private var labelSize: CGFloat {
        if radius > 70 { return 16 }
        if radius > 48 { return 14 }
        if radius > 32 { return 12 }
        return 10
    }
}

private func bubbleColor(_ t: Double) -> Color { accentRamp(t) }

// MARK: - Circle packing

struct BubbleLayout {
    let centers: [CGPoint]
    let radii: [CGFloat]

    init(bubbles: [ThemeBubble], canvasSize: CGSize, padding: CGFloat = 5) {
        let maxW = bubbles.map(\.totalWeight).max() ?? 1
        let minW = bubbles.map(\.totalWeight).min() ?? 0
        let range = max(maxW - minW, 1e-6)
        let maxR = min(canvasSize.width, canvasSize.height) * 0.18
        let minR = max(16, maxR * 0.22)

        let r: [CGFloat] = bubbles.map { b in
            let t = (b.totalWeight - minW) / range
            return minR + (maxR - minR) * CGFloat(sqrt(t))
        }
        radii = r

        let cx = canvasSize.width / 2, cy = canvasSize.height / 2
        var placed: [CGPoint] = []

        for i in 0..<r.count {
            guard i > 0 else { placed.append(CGPoint(x: cx, y: cy)); continue }
            var best = CGPoint(x: cx, y: cy + CGFloat(i) * 8)
            var bestDist = CGFloat.infinity
            for j in 0..<placed.count {
                let gap = r[j] + r[i] + padding
                let steps = max(36, Int(gap * 0.8))
                for s in 0..<steps {
                    let a = CGFloat(s) / CGFloat(steps) * 2 * .pi
                    let candidate = CGPoint(x: placed[j].x + cos(a)*gap, y: placed[j].y + sin(a)*gap)
                    let overlaps = (0..<placed.count).contains {
                        let dx = candidate.x-placed[$0].x, dy = candidate.y-placed[$0].y
                        return sqrt(dx*dx+dy*dy) < r[$0]+r[i]+padding-0.5
                    }
                    guard !overlaps else { continue }
                    let d = sqrt(pow(candidate.x-cx,2)+pow(candidate.y-cy,2))
                    if d < bestDist { bestDist = d; best = candidate }
                }
            }
            placed.append(best)
        }

        let clusterCX = ((placed.map(\.x).min() ?? 0) + (placed.map(\.x).max() ?? 0)) / 2
        let clusterCY = ((placed.map(\.y).min() ?? 0) + (placed.map(\.y).max() ?? 0)) / 2
        centers = placed.map { CGPoint(x: $0.x + cx - clusterCX, y: $0.y + cy - clusterCY) }
    }
}

// MARK: - Grouped bubbles tab

/// Wrapping flow layout for bubble groups — wraps items left-to-right, no fixed grid cell size.
struct BubbleFlow: Layout {
    var spacing: CGFloat = 8

    struct Cache {}
    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        compute(width: proposal.width ?? 400, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let result = compute(width: bounds.width, subviews: subviews)
        for (i, pt) in result.positions.enumerated() {
            let sz = subviews[i].sizeThatFits(.unspecified)
            subviews[i].place(
                at: CGPoint(x: bounds.minX + pt.x + sz.width / 2,
                            y: bounds.minY + pt.y + sz.height / 2),
                anchor: .center, proposal: .unspecified)
        }
    }

    private struct Computed { let size: CGSize; let positions: [CGPoint] }

    private func compute(width: CGFloat, subviews: Subviews) -> Computed {
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for subview in subviews {
            let sz = subview.sizeThatFits(.unspecified)
            if x + sz.width > width && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            positions.append(CGPoint(x: x, y: y))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return Computed(size: CGSize(width: width, height: y + rowH), positions: positions)
    }
}

struct GroupedBubblesView: View {
    let groups: [ThemeGroup]
    let onTap: (ThemeBubble) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(groups) { group in
                    GroupSection(group: group, onTap: onTap)
                }
            }
            .padding(22)
        }
    }
}

struct GroupSection: View {
    let group: ThemeGroup
    let onTap: (ThemeBubble) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.name.uppercased())
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(1.2)

            BubbleFlow(spacing: 6) {
                ForEach(Array(group.bubbles.enumerated()), id: \.element.id) { i, bubble in
                    let t = Double(i) / Double(max(1, group.bubbles.count - 1))
                    BubbleView(bubble: bubble, radius: radius(for: bubble), colorT: 1.0 - t * 0.6)
                        .onTapGesture { onTap(bubble) }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func radius(for bubble: ThemeBubble) -> CGFloat {
        let maxScore = group.bubbles.map(\.spreadScore).max() ?? 1.0
        let t = bubble.spreadScore / max(maxScore, 1e-9)
        return 18 + (46 - 18) * CGFloat(sqrt(t))
    }
}

// MARK: - Conversation list (shared drill-down)

struct ConversationListView: View {
    let sel: HeatmapModel.SelectedBubble
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(sel.theme)
                        .font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                    Text("\(sel.conversations.count) conversation\(sel.conversations.count == 1 ? "" : "s")")
                        .font(.system(size: 15)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Button("Done") { dismiss() }
            }
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(sel.conversations) { ConversationRow(conv: $0, theme: sel.theme) }
                }
            }
        }
        .padding(20)
        .frame(width: 560, height: 620)
        .background(LinearGradient(colors: [.bgDeep, .bgMid], startPoint: .top, endPoint: .bottom))
    }
}

struct ConversationRow: View {
    let conv: Conversation
    let theme: String
    @State private var hovering = false

    var claudeURL: URL? {
        guard conv.source == "claude.ai", !conv.id.hasPrefix("code:") else { return nil }
        // Anchor to the most theme-relevant message if we have its UUID
        let base = "https://claude.ai/chat/\(conv.id)"
        if let msgId = conv.bestMessageId(forTheme: theme) {
            return URL(string: "\(base)#\(msgId)")
        }
        return URL(string: base)
    }

    var body: some View {
        Button { if let url = claudeURL { openInChrome(url) } } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conv.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(hovering && claudeURL != nil ? Color.accentViolet : .white)
                    HStack(spacing: 5) {
                        Text(relativeDate(conv.lastTimestamp))
                        Text("·")
                        Text(conv.source)
                    }
                    .font(.system(size: 16)).foregroundStyle(.white.opacity(0.4))
                    Text(snippet(conv.combinedText))
                        .font(.system(size: 17)).foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                if claudeURL != nil {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(hovering ? 0.8 : 0.2))
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(hovering && claudeURL != nil ? Color.white.opacity(0.09) : Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(hovering && claudeURL != nil ? Color.accentViolet.opacity(0.45) : Color.white.opacity(0.09), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(claudeURL != nil ? "Open in Chrome" : "Local Code session — no URL")
        .disabled(claudeURL == nil)
    }

    private func relativeDate(_ d: Date) -> String {
        let diff = Date().timeIntervalSince(d)
        if diff < 3600 { return "\(Int(diff/60))m ago" }
        if diff < 86_400 { return "\(Int(diff/3600))h ago" }
        if diff < 7*86_400 { return "\(Int(diff/86_400))d ago" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMM d, yyyy"
        return f.string(from: d)
    }

    private func snippet(_ s: String) -> String {
        let c = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        return c.count > 160 ? String(c.prefix(160)) + "…" : c
    }
}

private func openInChrome(_ url: URL) {
    let chromePath = "/Applications/Google Chrome.app"
    if FileManager.default.fileExists(atPath: chromePath),
       let chromeURL = URL(fileURLWithPath: chromePath) as URL? {
        let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: chromeURL, configuration: cfg, completionHandler: nil)
    } else {
        NSWorkspace.shared.open(url)
    }
}
