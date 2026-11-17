import SwiftUI
import SwiftData
import Charts

/// The front page: what came in, where the money is, what needs a decision,
/// and the next line of every project.
struct TodayView: View {
    @Environment(MoneyStore.self) private var money
    @Environment(SiteMonitor.self) private var site
    @Environment(FeedSync.self) private var feed
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.order) private var projects: [Project]
    @Query(sort: \Deadline.date) private var deadlines: [Deadline]
    @State private var connecting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        MarkView(width: 170)
                        Spacer(minLength: 8)
                        if money.loading {
                            ProgressView()
                        }
                    }
                    .padding(.top, 6)

                    if !money.live {
                        ExampleBanner { connecting = true }
                    }
                    TakingsCard()
                    BalanceTiles()
                    NeedsYou(needs: needs)
                    FocusNow(projects: projects)
                }
                .page()
            }
            .scrollIndicators(.hidden)
            .background(Ink.ground)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await money.refresh()
                await feed.pull(into: context)
                await site.check()
            }
            .sheet(isPresented: $connecting) {
                ConnectStripe()
            }
        }
    }

    private var needs: [Need] {
        var list: [Need] = []
        for dispute in money.openDisputes {
            var detail = dispute.reason.isEmpty ? "Needs a response" : dispute.reason.capitalized
            if let due = dispute.due {
                detail = "Respond by \(due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
            }
            list.append(Need(id: dispute.id, color: Ink.hazard,
                             title: "Dispute: \(money.money(dispute.amount))", detail: detail))
        }
        let week = Date.now.addingTimeInterval(-7 * 86_400)
        let failed = money.failed(since: week)
        if !failed.isEmpty {
            let sum = failed.reduce(0) { $0 + $1.amount }
            list.append(Need(id: "failed", color: Ink.amber,
                             title: failed.count == 1 ? "1 payment failed" : "\(failed.count) payments failed",
                             detail: "\(money.money(sum)) in the last 7 days"))
        }
        if money.problem != nil {
            list.append(Need(id: "stripe", color: Ink.hazard, title: "Stripe didn't answer",
                             detail: money.problem ?? ""))
        }
        if site.isDown {
            list.append(Need(id: "site", color: Ink.hazard, title: "\(site.host) is down", detail: "Checked just now"))
        }
        for deadline in deadlines {
            let days = Days.count(to: deadline.date)
            guard days <= 30 else { continue }
            let when = deadline.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            list.append(Need(id: "deadline-\(deadline.title)-\(deadline.date.timeIntervalSince1970)",
                             color: days < 0 ? Ink.hazard : Ink.amber,
                             title: deadline.title,
                             detail: days < 0 ? "\(when), \(-days) days late" : days == 0 ? "Due today" : "\(when), \(days) days"))
        }
        return list
    }
}

struct Need: Identifiable {
    let id: String
    let color: Color
    let title: String
    let detail: String
}

/// Today's takings against the same stretch of this day last week,
/// over the trend of the last 30 days.
struct TakingsCard: View {
    @Environment(MoneyStore.self) private var money

    var body: some View {
        let calendar = Calendar.current
        let now = Date.now
        let start = calendar.startOfDay(for: now)
        let today = Ledger.total(money.payments, in: DateInterval(start: start, end: now.addingTimeInterval(1)))
        let lastStart = calendar.date(byAdding: .day, value: -7, to: start) ?? start
        let lastEnd = lastStart.addingTimeInterval(now.timeIntervalSince(start))
        let last = Ledger.total(money.payments, in: DateInterval(start: lastStart, end: max(lastStart, lastEnd)))
        let trend = Ledger.rolling(Ledger.daily(money.payments, days: 36, now: now, calendar: calendar), window: 7).suffix(30)
        let weekday = now.formatted(.dateTime.weekday(.wide))

        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Today")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Ink.muted)
                    Spacer(minLength: 8)
                    Text(now, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.footnote)
                        .foregroundStyle(Ink.muted)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(money.money(today))
                        .font(.system(size: 40, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 8)
                    difference(today - last, weekday: weekday)
                }
                Chart(Array(trend)) { bucket in
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
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 72)
                .accessibilityLabel("Revenue over the last 30 days")
                HStack {
                    Text("30 days ago")
                    Spacer()
                    Text("Today")
                }
                .font(.caption)
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
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Ink.muted)
                    Text(money.money(month))
                        .font(.title2.bold())
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    ChangePill(change: Ledger.change(from: before, to: month))
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stripe balance")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Ink.muted)
                    Text(money.money(money.available))
                        .font(.title2.bold())
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let payout = money.nextPayout {
                        Text("\(money.money(payout.amount)) out \(payout.arrives.formatted(.dateTime.weekday(.abbreviated)))")
                            .font(.caption)
                            .foregroundStyle(Ink.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text("\(money.money(money.pending)) pending")
                            .font(.caption)
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
                                            .font(.caption)
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
                            FocusNowRow(item: row.1, project: row.0)
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

    var body: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.snappy.delay(item.done ? 0 : 0.34)) { item.set(done: !item.done) }
            } label: {
                Tick(done: item.done, color: Color(hex: UInt32(project.tint)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? "Reopen" : "Tick")
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .foregroundStyle(Ink.body)
                    .lineLimit(2)
                Text(project.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Ink.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .padding(.vertical, 4)
        .sensoryFeedback(.success, trigger: item.done) { _, new in new }
    }
}
