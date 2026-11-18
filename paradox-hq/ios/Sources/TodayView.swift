import SwiftUI
import SwiftData
import Charts

/// The top of the Work tab: the mark on the left, who is running it on the
/// right, and beneath them the word Dashboard with a white line either side.
struct TodayHeader: View {
    let loading: Bool

    var body: some View {
        VStack(spacing: 16) {
            ViewThatFits(in: .horizontal) {
                row(mark: 150)
                row(mark: 124)
                row(mark: 100)
            }
            // ——— Dashboard ———
            HStack(spacing: 14) {
                Rectangle().fill(Ink.head).frame(height: 1)
                Text("Dashboard")
                    .font(Face.graphik(17, .medium))
                    .tracking(0.4)
                    .foregroundStyle(Ink.head)
                    .lineLimit(1)
                    .fixedSize()
                Rectangle().fill(Ink.head).frame(height: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Dashboard")
            .accessibilityAddTraits(.isHeader)
        }
    }

    /// The mark's top and the photo's top line up, however many roles are stacked under the name.
    private func row(mark: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 12) {
            MarkView(width: mark)
                .hunt()
            if loading {
                ProgressView()
            }
            Spacer(minLength: 0)
            ProfileBadge()
                .fixedSize()
        }
    }
}

/// The Work tab, the front page: what was made, what came in, where the money is, what needs a decision,
/// and the next line of every project.
struct TodayView: View {
    @Environment(MoneyStore.self) private var money
    @Environment(SiteMonitor.self) private var site
    @Environment(FeedSync.self) private var feed
    @Environment(WorkStore.self) private var work
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.order) private var projects: [Project]
    @Query(sort: \Deadline.date) private var deadlines: [Deadline]
    @State private var connecting = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    TodayHeader(loading: money.loading)
                        .padding(.top, 6)

                    WorkCard { path.append($0) }

                    if !money.live {
                        ExampleBanner { connecting = true }
                    }
                    TakingsCard().rise(0)
                    BalanceTiles().rise(1)
                    NeedsYou(needs: needs).rise(2)
                    if let mine = projects.first(where: \.isPersonal) {
                        MyListCard(project: mine, open: { path.append($0) }, openAll: { path.append(mine) }) {
                            // Keep the field being typed in above the keyboard.
                            withAnimation(.snappy) { proxy.scrollTo(MyListCard.fieldID, anchor: .bottom) }
                        }
                        .rise(3)
                    }
                    FocusNow(projects: projects.filter { !$0.isPersonal }) { path.append($0) }
                        .rise(4)
                }
                .page()
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .statusBarFade()
            .background(Ink.ground)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await money.refresh()
                await feed.pull(into: context)
                await site.check()
                await work.refresh(force: true)
            }
            .sheet(isPresented: $connecting) {
                ConnectStripe()
            }
            .navigationDestination(for: Project.self) { ProjectDetail(project: $0) }
            .navigationDestination(for: WorkRoute.self) { route in
                switch route {
                case .day(let day): WorkLog(day: day)
                case .all: WorkLog(day: nil)
                }
            }
            .navigationDestination(for: FocusItem.self) { item in
                ItemPage(item: item, tint: Ink.tint(item.owner?.tint ?? 0xFFFFFF))
            }
            .navigationDestination(for: Note.self) { NoteEditor(note: $0) }
            }
            .onAppear {
                // The cloud build opens straight into your own list to photograph it.
                if Launch.screen == "list", path.isEmpty, let mine = projects.first(where: \.isPersonal) {
                    path.append(mine)
                }
            }
        }
    }

    private var needs: [Need] {
        Bridge.needs(money: money, site: site, deadlines: deadlines)
    }
}

/// Today's takings against the same stretch of this day last week,
/// over the trend of the last 30 days.
struct TakingsCard: View {
    @Environment(MoneyStore.self) private var money
    /// Where the finger is on the chart, while it's down.
    @State private var touched: Date? = nil

    var body: some View {
        let calendar = Calendar.current
        let now = Date.now
        let start = calendar.startOfDay(for: now)
        let today = Ledger.total(money.payments, in: DateInterval(start: start, end: now.addingTimeInterval(1)))
        let lastStart = calendar.date(byAdding: .day, value: -7, to: start) ?? start
        let lastEnd = lastStart.addingTimeInterval(now.timeIntervalSince(start))
        let last = Ledger.total(money.payments, in: DateInterval(start: lastStart, end: max(lastStart, lastEnd)))
        let daily = Ledger.daily(money.payments, days: 36, now: now, calendar: calendar)
        let trend = Array(Ledger.rolling(daily, window: 7).suffix(30))
        let weekday = now.formatted(.dateTime.weekday(.wide))
        // Dragging along the chart reads off each day in turn, with a tick of
        // the haptic every time the finger crosses onto another day.
        let picked = touched.flatMap { Ledger.pick(trend, at: $0) }
        let pickedDay = picked.flatMap { point in daily.first { $0.date == point.date } }

        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(picked == nil ? "Today" : "That day")
                        .font(Face.at(12, .semibold)).textCase(.uppercase).tracking(0.9)
                        .foregroundStyle(Ink.muted)
                    Spacer(minLength: 8)
                    Text(picked?.date ?? now, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(Face.style(.footnote))
                        .foregroundStyle(picked == nil ? Ink.muted : Ink.head)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(money.money(pickedDay?.amount ?? today))
                        .figure(44, value: Double(pickedDay?.amount ?? today))
                        .foregroundStyle(Ink.head)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 8)
                    if picked == nil {
                        difference(today - last, weekday: weekday)
                    }
                }
                Chart {
                    ForEach(trend) { bucket in
                        AreaMark(x: .value("Day", bucket.date, unit: .day),
                                 y: .value("Revenue", Double(bucket.amount) / 100))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LinearGradient(colors: [Ink.violet.opacity(0.35), Ink.violet.opacity(0)],
                                                            startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Day", bucket.date, unit: .day),
                                 y: .value("Revenue", Double(bucket.amount) / 100))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            .foregroundStyle(Ink.violet)
                    }
                    if let picked {
                        RuleMark(x: .value("Day", picked.date, unit: .day))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .foregroundStyle(Ink.idle)
                        PointMark(x: .value("Day", picked.date, unit: .day),
                                  y: .value("Revenue", Double(picked.amount) / 100))
                            .symbolSize(70)
                            .foregroundStyle(Ink.head)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartXSelection(value: $touched)
                .sensoryFeedback(.selection, trigger: picked?.date)
                .frame(height: 72)
                .accessibilityLabel("Revenue over the last 30 days")
                HStack {
                    Text("30 days ago")
                    Spacer()
                    Text("Today")
                }
                .font(Face.style(.caption))
                .foregroundStyle(Ink.muted)
            }
        }
    }

    @ViewBuilder
    private func difference(_ delta: Int, weekday: String) -> some View {
        if delta != 0 {
            let up = delta > 0
            Pill(text: "\(up ? "▲" : "▼") \(money.money(abs(delta))) on last \(weekday)",
                 color: up ? Ink.ok : Ink.hazard)
        }
    }
}

struct BalanceTiles: View {
    @Environment(MoneyStore.self) private var money

    var body: some View {
        let calendar = Calendar.current
        let now = Date.now
        let month = Ledger.total(money.payments, in: Period.month.current(now: now, calendar: calendar))
        let before = Ledger.total(money.payments, in: Period.month.previous(now: now, calendar: calendar))

        HStack(alignment: .top, spacing: 12) {
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    Text(now, format: .dateTime.month(.wide))
                        .font(Face.at(12, .semibold)).textCase(.uppercase).tracking(0.9)
                        .foregroundStyle(Ink.muted)
                    Text(money.money(month))
                        .figure(26, value: Double(month))
                        .foregroundStyle(Ink.head)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    ChangePill(change: Ledger.change(from: before, to: month))
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stripe balance")
                        .font(Face.at(12, .semibold)).textCase(.uppercase).tracking(0.9)
                        .foregroundStyle(Ink.muted)
                    Text(money.money(money.available))
                        .figure(26, value: Double(money.available))
                        .foregroundStyle(Ink.head)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let payout = money.nextPayout {
                        Text("\(money.money(payout.amount)) out \(payout.arrives.formatted(.dateTime.weekday(.abbreviated)))")
                            .font(Face.style(.caption))
                            .foregroundStyle(Ink.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text("\(money.money(money.pending)) pending")
                            .font(Face.style(.caption))
                            .foregroundStyle(Ink.muted)
                    }
                }
            }
        }
    }
}

/// Only what needs a decision. With nothing to decide, it isn't there.
struct NeedsYou: View {
    let needs: [Need]

    var body: some View {
        if !needs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Needs you", trailing: "\(needs.count)")
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(needs.enumerated()), id: \.element.id) { index, need in
                            if index > 0 { Hairline(inset: 36) }
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(need.color)
                                    .frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(need.title)
                                        .foregroundStyle(Ink.body)
                                    if !need.detail.isEmpty {
                                        Text(need.detail)
                                            .font(Face.style(.caption))
                                            .foregroundStyle(Ink.muted)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                        }
                    }
                }
            }
        }
    }
}

/// The next open line of each project, tickable from the front page.
struct FocusNow: View {
    let projects: [Project]
    var open: (FocusItem) -> Void = { _ in }

    var body: some View {
        let rows = projects.compactMap { project in
            project.openItems.first.map { (project, $0) }
        }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Focus")
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.1.id) { index, row in
                            if index > 0 { Hairline(inset: 58) }
                            FocusNowRow(item: row.1, project: row.0) { open(row.1) }
                        }
                    }
                }
            }
        }
    }
}

struct FocusNowRow: View {
    let item: FocusItem
    let project: Project
    var open: () -> Void = {}

    var body: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.snappy.delay(item.done ? 0 : 0.34)) { item.set(done: !item.done) }
            } label: {
                Tick(done: item.done, color: Ink.tint(project.tint))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? "Reopen" : "Tick")
            Button(action: open) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .foregroundStyle(Ink.body)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(project.name)
                            .font(Face.style(.caption, .medium))
                            .foregroundStyle(Ink.muted)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .padding(.vertical, 4)
        .sensoryFeedback(.success, trigger: item.done) { _, new in new }
    }
}
