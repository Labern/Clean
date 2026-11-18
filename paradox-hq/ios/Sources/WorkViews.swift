import SwiftUI
import SwiftData
import Charts
import UIKit

/// Where a tap on the Work card leads.
enum WorkRoute: Hashable {
    /// Everything done on one day.
    case day(Date)
    /// Everything, day by day.
    case all
}

/// Opens a Claude conversation in the Claude app, or on the web without it.
@MainActor enum ClaudeApp {
    static func open(_ link: URL) {
        // claude.ai/code/… is an address the Claude app claims, so this lands in the app itself.
        UIApplication.shared.open(link, options: [.universalLinksOnly: true]) { opened in
            if !opened {
                Task { @MainActor in UIApplication.shared.open(link, options: [:], completionHandler: nil) }
            }
        }
    }
}

/// The Work card: how much went out in a chosen stretch of time, a graph of
/// it, and a way into what was done.
struct WorkCard: View {
    @Environment(WorkStore.self) private var work
    @Query private var notes: [Note]
    @AppStorage("work-span") private var span: WorkSpan = .day
    /// Bottom left: the last 24 hours, 7 days, 30 days, instead of today, this week, this month.
    @AppStorage("work-rolling") private var rolling = false
    /// Folded, the card is its three figures and nothing else.
    @AppStorage("work-folded") private var folded = false
    /// Settings: also show what reached a product's main branch.
    @AppStorage("work-products") private var products = false
    @State private var measure: WorkMeasure = .pushed
    @State private var touched: Date? = nil
    /// The bar last read off the graph. It stays chosen when the finger lifts.
    @State private var chosen: Date? = nil
    let open: (WorkRoute) -> Void

    var body: some View {
        let calendar = Calendar.current
        let now = Date.now
        let start = span.start(now: now, calendar: calendar, rolling: rolling, session: work.session?.started)
        let pushes = work.entries.map { (date: $0.date, amount: 1) }
        let messages = WorkLedger.messages(work.sessions)
        let written = notes.map { (date: $0.created, amount: 1) }

        // The three figures, for the stretch chosen. A session is a conversation,
        // not a stretch of the clock: its own changes and its own messages.
        let current = span == .session ? work.session : nil
        let pushed = current.map { WorkLedger.work(in: $0, work.entries, now: now) }
            ?? work.entries.filter { $0.date >= start && $0.date <= now }
        let live = pushed.filter(\.published).count
        let sent = current?.messages ?? WorkLedger.total(messages, from: start, to: now, calendar: calendar)
        // Asked for the session before any conversation has been counted: say so, don't show noughts as fact.
        let caption = span == .session && current == nil ? "no session counted yet" : span.caption(rolling: rolling)

        // The graph, cut by the hour or the day to suit the stretch.
        let cut = span.graph
        let points = switch measure {
        case .pushed: pushes
        case .claude: messages
        case .writing: written
        }
        let bars = WorkLedger.buckets(points, unit: cut.unit, count: cut.count, now: now, calendar: calendar)
        let picked = touched.flatMap { Ledger.pick(bars, at: $0) }
        let shown = bars.first { $0.date == chosen } ?? bars.last
        let bar = picked ?? shown
        let barEnd = bar.flatMap { calendar.date(byAdding: cut.unit, value: 1, to: $0.date) } ?? now
        let barWork = work.entries.filter { entry in
            guard let bar else { return false }
            return entry.date >= bar.date && entry.date < barEnd
        }

        VStack(alignment: .leading, spacing: 8) {
            // The heading folds the card: tap to hide the graph and the list, tap to bring them back.
            Button {
                withAnimation(.snappy) { folded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Work")
                        .font(Face.at(12, .semibold))
                        .textCase(.uppercase)
                        .tracking(0.9)
                    Image(systemName: folded ? "chevron.right" : "chevron.down")
                        .font(Face.style(.caption2, .bold))
                    Spacer(minLength: 8)
                    if work.loading {
                        Text("Reading GitHub")
                            .font(Face.at(12, .medium))
                    }
                }
                .foregroundStyle(Ink.muted)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: folded)
            .accessibilityLabel(folded ? "Show the work graph" : "Hide the work graph")

            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 0) {
                        figure(pushed.count, "Pushed", caption)
                        // Published is a live site updated. Products are their own figure, off unless asked for.
                        figure(live, "Published", caption)
                        if products {
                            figure(pushed.filter { $0.shipped == true }.count, "Products", caption)
                        }
                        figure(sent, "Claude messages", work.claudeCounted == nil ? "waiting for a count" : caption)
                    }

                    if !folded {
                        Picker("Graph", selection: $measure.animation(.snappy)) {
                            ForEach(WorkMeasure.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .sensoryFeedback(.selection, trigger: measure)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(Self.count(bar?.amount ?? 0, measure))
                                    .font(Face.style(.footnote, .semibold))
                                    .foregroundStyle(Ink.head)
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                Spacer(minLength: 8)
                                Text(Self.stamp(bar?.date ?? now, hourly: cut.unit == .hour))
                                    .font(Face.style(.footnote))
                                    .foregroundStyle(Ink.muted)
                                    .monospacedDigit()
                            }
                            // Drag along it: each bar reads off in turn, with a tick as the finger crosses.
                            Chart(bars) { item in
                                BarMark(x: .value("When", item.date, unit: cut.unit),
                                        y: .value(measure.rawValue, max(Double(item.amount), 0.12)))
                                    .cornerRadius(2)
                                    .foregroundStyle(item.date == bar?.date
                                                     ? Ink.head : Ink.violet.opacity(item.amount == 0 ? 0.25 : 0.7))
                            }
                            .chartXAxis(.hidden)
                            .chartYAxis(.hidden)
                            .chartXSelection(value: $touched)
                            .sensoryFeedback(.selection, trigger: picked?.date)
                            .frame(height: 64)
                            .accessibilityLabel("\(measure.rawValue), \(cut.unit == .hour ? "hour by hour" : "day by day")")
                        }

                        // What was done in the chosen bar. A line made in a Claude conversation opens it.
                        VStack(spacing: 0) {
                            ForEach(barWork.prefix(3)) { entry in
                                Button {
                                    if let link = entry.sessionLink { ClaudeApp.open(link) } else { open(.day(entry.date)) }
                                } label: {
                                    WorkLine(entry: entry, compact: true)
                                }
                                .buttonStyle(.plain)
                                Hairline(inset: 0)
                            }
                            link(barWork.isEmpty ? "Nothing pushed then" : Self.dayLabel(bar?.date ?? now, barWork.count, calendar),
                                 strong: !barWork.isEmpty) { open(.day(bar?.date ?? now)) }
                                .disabled(barWork.isEmpty)
                            Hairline(inset: 0)
                            link("All work", strong: false) { open(.all) }
                        }
                    }

                    // The stretch of time, along the bottom; bottom left, calendar or rolling.
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Stretch", selection: $span.animation(.snappy)) {
                            ForEach(WorkSpan.allCases) { Text($0.title(rolling: rolling)).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .sensoryFeedback(.selection, trigger: span)
                        HStack {
                            Button {
                                withAnimation(.snappy) { rolling.toggle() }
                            } label: {
                                Label(rolling ? "Last 24 hours" : "Today", systemImage: rolling ? "clock.arrow.circlepath" : "calendar")
                                    .font(Face.style(.caption, .semibold))
                                    .foregroundStyle(Ink.body)
                                    .padding(.horizontal, 10)
                                    .frame(minHeight: 30)
                                    .background(Ink.surface2, in: Capsule())
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .sensoryFeedback(.selection, trigger: rolling)
                            .accessibilityLabel(rolling ? "Counting the last 24 hours. Switch to today." : "Counting today. Switch to the last 24 hours.")
                            Spacer()
                            if span == .session, let session = work.session {
                                // The conversation itself, a tap away when its address is known.
                                Button {
                                    if let link = session.link.flatMap(URL.init(string:)) { ClaudeApp.open(link) }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text("since \(session.started.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                                            .font(Face.style(.caption))
                                            .foregroundStyle(Ink.muted)
                                        if session.link != nil {
                                            LogoTile(name: "Logo-Claude", size: 20)
                                        }
                                    }
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(session.link == nil)
                                .accessibilityLabel("Open this conversation in Claude")
                            }
                        }
                    }
                    if !work.problem.isEmpty {
                        Text(work.problem)
                            .font(Face.style(.footnote))
                            .foregroundStyle(Ink.amber)
                    }
                }
            }
        }
        .onChange(of: picked?.date) { _, date in
            if let date { chosen = date }
        }
        .onChange(of: span) { chosen = nil }
        .onChange(of: measure) { chosen = nil }
    }

    private func figure(_ value: Int, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .figure(30, value: Double(value))
                .foregroundStyle(Ink.head)
            Text(title)
                .font(Face.style(.caption, .semibold))
                .foregroundStyle(Ink.body)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(Face.style(.caption2))
                .foregroundStyle(Ink.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func link(_ title: String, strong: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(Face.style(.subheadline, strong ? .semibold : .regular))
                    .foregroundStyle(strong ? Ink.head : Ink.body)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Face.style(.caption, .semibold))
                    .foregroundStyle(Ink.idle)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    nonisolated static func count(_ n: Int, _ measure: WorkMeasure) -> String {
        "\(n) \(n == 1 ? measure.unit.one : measure.unit.many)"
    }

    /// "Tue 17 Nov", or "Tue 14:00" for an hour's bar.
    static func stamp(_ date: Date, hourly: Bool) -> String {
        hourly ? date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
               : date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func dayLabel(_ day: Date, _ count: Int, _ calendar: Calendar) -> String {
        let name = calendar.isDateInToday(day) ? "Today"
            : calendar.isDateInYesterday(day) ? "Yesterday"
            : day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        return "\(name): \(count) \(count == 1 ? "version" : "versions")"
    }
}

/// One piece of work: when, what kind, and what it was.
struct WorkLine: View {
    let entry: WorkEntry
    /// One line, no bullets.
    var compact = false
    /// Show the day as well as the time (where lines from many days sit together).
    var dated = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.kind.symbol)
                .font(Face.at(13, .semibold))
                .foregroundStyle(Self.colour(entry.kind))
                .frame(width: 28, height: 28)
                .background(Ink.surface2, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.line)
                    .font(Face.style(compact ? .subheadline : .body))
                    .foregroundStyle(Ink.body)
                    .lineLimit(compact ? 1 : nil)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(entry.date, format: dated ? .dateTime.day().month(.abbreviated).hour().minute() : .dateTime.hour().minute())
                        .monospacedDigit()
                    if !entry.project.isEmpty, !dated {
                        Text(entry.project)
                    }
                    if entry.published {
                        Text("Live").foregroundStyle(Ink.ok)
                    } else if entry.shipped == true {
                        Text("Product")
                    }
                    if entry.claude, entry.session == nil {
                        Text("with Claude")
                    }
                }
                .font(Face.style(.caption))
                .foregroundStyle(Ink.muted)
                .lineLimit(1)
                if !compact {
                    ForEach(entry.points, id: \.self) { point in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(Ink.idle)
                                .frame(width: 4, height: 4)
                                .offset(y: -3)
                            Text(point)
                                .font(Face.style(.subheadline))
                                .foregroundStyle(Ink.muted)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    HStack(spacing: 8) {
                        if let link = entry.sessionLink {
                            chip("Open in Claude", logo: "Logo-Claude") { ClaudeApp.open(link) }
                        }
                        if let link = entry.link {
                            chip("GitHub", logo: "Logo-GitHub") { openURL(link) }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            // The conversation it came from rides with every line, a tap away.
            if compact, entry.session != nil {
                LogoTile(name: "Logo-Claude", size: 20)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, compact ? 8 : 6)
        .contentShape(Rectangle())
    }

    private func chip(_ title: String, logo: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                LogoTile(name: logo, size: 18)
                Text(title)
                    .font(Face.style(.caption, .semibold))
                    .foregroundStyle(Ink.body)
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .frame(minHeight: 32)
            .background(Ink.surface2, in: Capsule())
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    static func colour(_ kind: WorkKind) -> Color {
        switch kind {
        case .added: Ink.ok
        case .fixed: Ink.amber
        case .styled: Ink.violet
        default: Ink.body
        }
    }
}

/// What was done, at each time: one day, or every day there is. Lines are one
/// line each until tapped; a day's heading folds the day; the button at the top
/// opens or closes everything at once.
struct WorkLog: View {
    @Environment(WorkStore.self) private var work
    /// Nil shows every day.
    let day: Date?
    /// Lines showing their bullets.
    @State private var open: Set<String> = []
    /// Days folded away.
    @State private var shut: Set<Date> = []

    var body: some View {
        let calendar = Calendar.current
        let entries = day.map { WorkLedger.on($0, work.entries, calendar: calendar) } ?? work.entries
        let days = WorkLedger.byDay(entries, calendar: calendar)
        let allOpen = !entries.isEmpty && open.count >= entries.count
        List {
            if days.isEmpty {
                Text("Nothing pushed.")
                    .foregroundStyle(Ink.muted)
                    .listRowBackground(Ink.surface)
            }
            ForEach(days, id: \.day) { group in
                Section {
                    if !shut.contains(group.day) {
                        ForEach(group.entries) { entry in
                            Button {
                                withAnimation(.snappy) {
                                    if open.contains(entry.id) { open.remove(entry.id) } else { open.insert(entry.id) }
                                }
                            } label: {
                                WorkLine(entry: entry, compact: !open.contains(entry.id))
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Ink.surface)
                            .listRowSeparatorTint(Ink.line)
                        }
                    }
                } header: {
                    Button {
                        withAnimation(.snappy) {
                            if shut.contains(group.day) { shut.remove(group.day) } else { shut.insert(group.day) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(group.day, format: .dateTime.weekday(.wide).day().month(.wide))
                            Image(systemName: shut.contains(group.day) ? "chevron.right" : "chevron.down")
                                .font(Face.style(.caption2, .bold))
                            Spacer()
                            Text(Self.tally(group.entries))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .font(Face.at(12, .semibold))
                        .textCase(.uppercase)
                        .tracking(0.9)
                        .foregroundStyle(Ink.muted)
                        .frame(minHeight: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Ink.ground)
        .navigationTitle(day == nil ? "All work" : "Work")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(allOpen ? "Contract" : "Expand") {
                    withAnimation(.snappy) { open = allOpen ? [] : Set(entries.map(\.id)) }
                }
                .disabled(entries.isEmpty)
            }
        }
        .sensoryFeedback(.selection, trigger: open.count)
        .refreshable { await work.refresh(force: true) }
    }

    /// "5 added · 2 fixed · 1 styled": the day in a line.
    nonisolated static func tally(_ entries: [WorkEntry]) -> String {
        WorkKind.allCases.compactMap { kind in
            let count = entries.filter { $0.kind == kind }.count
            return count == 0 ? nil : "\(count) \(kind.title.lowercased())"
        }
        .joined(separator: " · ")
    }
}

/// On a project's page: the changes that were made to it, each a tap from the
/// Claude conversation it was made in. Nothing shows until GitHub has some.
struct ProjectWork: View {
    @Environment(WorkStore.self) private var work
    let project: Project
    /// Lines showing their bullets.
    @State private var open: Set<String> = []
    @State private var all = false

    var body: some View {
        let mine = work.entries.filter { WorkLedger.belongs($0, toProject: project.name, id: project.remoteID) }
        if !mine.isEmpty {
            Section {
                ForEach(all ? mine : Array(mine.prefix(4))) { entry in
                    Button {
                        withAnimation(.snappy) {
                            if open.contains(entry.id) { open.remove(entry.id) } else { open.insert(entry.id) }
                        }
                    } label: {
                        WorkLine(entry: entry, compact: !open.contains(entry.id), dated: true)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Ink.surface)
                    .listRowSeparatorTint(Ink.line)
                }
                if mine.count > 4 {
                    Button {
                        withAnimation(.snappy) { all.toggle() }
                    } label: {
                        Text(all ? "Show fewer" : "Show all \(mine.count)")
                            .font(Face.style(.subheadline))
                            .foregroundStyle(Ink.head)
                    }
                    .listRowBackground(Ink.surface)
                    .listRowSeparatorTint(Ink.line)
                }
            } header: {
                HStack {
                    Text("Work")
                    Spacer()
                    Text(WorkLog.tally(mine))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .font(Face.at(12, .semibold))
                .textCase(.uppercase)
                .tracking(0.9)
                .foregroundStyle(Ink.muted)
            }
        }
    }
}
