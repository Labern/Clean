import SwiftUI
import SwiftData
import Charts

/// Where a tap on the Work card leads.
enum WorkRoute: Hashable {
    /// Everything done on one day.
    case day(Date)
    /// Everything, day by day.
    case all
}

/// The Work card: how much went out today, a graph of the last thirty days,
/// and a way into what was done on any one of them.
struct WorkCard: View {
    @Environment(WorkStore.self) private var work
    @Query private var notes: [Note]
    @State private var measure: WorkMeasure = .pushed
    @State private var touched: Date? = nil
    /// The day last read off the graph. It stays chosen when the finger lifts.
    @State private var chosen: Date = Calendar.current.startOfDay(for: .now)
    let open: (WorkRoute) -> Void

    var body: some View {
        let calendar = Calendar.current
        let now = Date.now
        let pushed = WorkLedger.perDay(work.entries, days: WorkStore.days, now: now, calendar: calendar)
        let claude = WorkLedger.perDay(work.claude, days: WorkStore.days, now: now, calendar: calendar)
        let writing = NoteText.perDay(notes.map(\.created), days: WorkStore.days, now: now, calendar: calendar)
        let bars = switch measure {
        case .pushed: pushed
        case .claude: claude
        case .writing: writing
        }
        let picked = touched.flatMap { Ledger.pick(bars, at: $0) }
        let week = { (all: [Bucket]) in all.suffix(7).reduce(0) { $0 + $1.amount } }
        let live = work.entries.filter { $0.published && $0.date > now.addingTimeInterval(-7 * 86_400) }.count
        let shown = bars.first { $0.date == chosen } ?? bars.last
        let dayWork = WorkLedger.on(chosen, work.entries, calendar: calendar)

        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Work", trailing: work.loading ? "Reading GitHub" : "")
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 0) {
                        figure(pushed.last?.amount ?? 0, "Pushed today", "\(week(pushed)) this week")
                        figure(live, "Published", "this week")
                        figure(claude.last?.amount ?? 0, "Claude messages", "\(week(claude)) this week")
                    }

                    Picker("Graph", selection: $measure.animation(.snappy)) {
                        ForEach(WorkMeasure.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .sensoryFeedback(.selection, trigger: measure)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(Self.count((picked ?? shown)?.amount ?? 0, measure))
                                .font(Face.style(.footnote, .semibold))
                                .foregroundStyle(Ink.head)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Spacer(minLength: 8)
                            Text((picked ?? shown)?.date ?? chosen, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                                .font(Face.style(.footnote))
                                .foregroundStyle(Ink.muted)
                        }
                        // Drag along it: each day reads off in turn, with a tick as the finger crosses.
                        Chart(bars) { bar in
                            BarMark(x: .value("Day", bar.date, unit: .day),
                                    y: .value(measure.rawValue, max(Double(bar.amount), 0.12)))
                                .cornerRadius(2)
                                .foregroundStyle(bar.date == (picked?.date ?? chosen)
                                                 ? Ink.head : Ink.violet.opacity(bar.amount == 0 ? 0.25 : 0.7))
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .chartXSelection(value: $touched)
                        .sensoryFeedback(.selection, trigger: picked?.date)
                        .frame(height: 64)
                        .accessibilityLabel("\(measure.rawValue) per day, last thirty days")
                    }

                    // What was done on the chosen day, and the way in to all of it.
                    VStack(spacing: 0) {
                        ForEach(dayWork.prefix(3)) { entry in
                            WorkLine(entry: entry, compact: true)
                            Hairline(inset: 0)
                        }
                        Button { open(.day(chosen)) } label: {
                            HStack {
                                Text(dayWork.isEmpty ? "Nothing pushed that day" : Self.dayLabel(chosen, dayWork.count, calendar))
                                    .font(Face.style(.subheadline, .semibold))
                                    .foregroundStyle(dayWork.isEmpty ? Ink.muted : Ink.head)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(Face.style(.caption, .semibold))
                                    .foregroundStyle(Ink.idle)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(dayWork.isEmpty)
                        Hairline(inset: 0)
                        Button { open(.all) } label: {
                            HStack {
                                Text("All work")
                                    .font(Face.style(.subheadline))
                                    .foregroundStyle(Ink.body)
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
                    if !work.problem.isEmpty {
                        Text(work.problem)
                            .font(Face.style(.footnote))
                            .foregroundStyle(Ink.amber)
                    }
                }
            }
        }
        .onChange(of: picked?.date) { _, day in
            if let day { chosen = day }
        }
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    nonisolated static func count(_ n: Int, _ measure: WorkMeasure) -> String {
        "\(n) \(n == 1 ? measure.unit.one : measure.unit.many)"
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
    /// On the card: one line, no bullets.
    var compact = false
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
                    Text(entry.date, format: .dateTime.hour().minute())
                        .monospacedDigit()
                    if !entry.project.isEmpty {
                        Text(entry.project)
                    }
                    if entry.published {
                        Text("Live").foregroundStyle(Ink.ok)
                    }
                    if entry.claude {
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
                }
            }
            Spacer(minLength: 0)
            if !compact, let link = entry.link {
                Button { openURL(link) } label: {
                    Image(systemName: "arrow.up.forward")
                        .font(Face.style(.caption, .semibold))
                        .foregroundStyle(Ink.idle)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open on GitHub")
            }
        }
        .padding(.vertical, compact ? 8 : 6)
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

/// What was done, at each time: one day, or every day there is.
struct WorkLog: View {
    @Environment(WorkStore.self) private var work
    /// Nil shows every day.
    let day: Date?

    var body: some View {
        let calendar = Calendar.current
        let entries = day.map { WorkLedger.on($0, work.entries, calendar: calendar) } ?? work.entries
        let days = WorkLedger.byDay(entries, calendar: calendar)
        List {
            if days.isEmpty {
                Text("Nothing pushed.")
                    .foregroundStyle(Ink.muted)
                    .listRowBackground(Ink.surface)
            }
            ForEach(days, id: \.day) { group in
                Section {
                    ForEach(group.entries) { entry in
                        WorkLine(entry: entry)
                            .listRowBackground(Ink.surface)
                            .listRowSeparatorTint(Ink.line)
                    }
                } header: {
                    HStack {
                        Text(group.day, format: .dateTime.weekday(.wide).day().month(.wide))
                        Spacer()
                        Text(Self.tally(group.entries))
                            .monospacedDigit()
                    }
                    .font(Face.at(12, .semibold))
                    .textCase(.uppercase)
                    .tracking(0.9)
                    .foregroundStyle(Ink.muted)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Ink.ground)
        .navigationTitle(day == nil ? "All work" : "Work")
        .navigationBarTitleDisplayMode(.inline)
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
