import SwiftUI
import SwiftData

/// The board behind the mark: what needs you, then a row per spine.
struct HomePage: View {
    let open: (Spine) -> Void
    @Environment(CalendarStore.self) private var calendar
    @Query private var todos: [Todo]
    @Query(sort: \Deadline.date) private var deadlines: [Deadline]
    @Query(sort: \Camera.order) private var cameras: [Camera]
    @Query(sort: \Pin.order) private var pins: [Pin]
    @Query(sort: \Entry.day, order: .reverse) private var entries: [Entry]

    struct Attention: Identifiable {
        let id: String
        let spine: Spine
        let symbol: String
        let title: String
        let detail: String
    }

    var body: some View {
        let items = attention

        PageScaffold(spine: .home,
                     eyebrow: Date.now.formatted(.dateTime.day().month(.wide)),
                     title: Date.now.formatted(.dateTime.weekday(.wide)),
                     subtitle: nextLine) {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Needs you", trailing: "\(items.count)")
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { Hairline(inset: 44) }
                                Button { open(item.spine) } label: { AttentionRow(item: item) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        } reach: {
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach([Spine.tesla, .ring, .spotify, .diary]) { spine in
                        if spine != .tesla { Hairline(inset: 28) }
                        Button { open(spine) } label: {
                            StatusRow(spine: spine, status: status(for: spine))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var nextLine: String {
        if let next = calendar.nextToday {
            return "Next: \(next.title ?? "Event") at \(next.startDate.formatted(date: .omitted, time: .shortened))"
        }
        let open = todos.filter { !$0.done }.count
        return open == 0 ? "Nothing waiting" : "\(open) things to do"
    }

    private func status(for spine: Spine) -> String {
        switch spine {
        case .home:
            return ""
        case .tesla:
            let n = todos.filter { $0.spineRaw == Spine.tesla.rawValue && !$0.done }.count
            let today = Calendar.current.startOfDay(for: .now)
            if let next = deadlines.first(where: { $0.date >= today }) {
                return "\(n) to do · \(next.title) \(Days.short(Days.count(to: next.date)))"
            }
            return "\(n) to do"
        case .ring:
            let low = cameras.filter { $0.battery < 0.25 }.count
            return low == 0 ? "\(cameras.count) cameras, all charged" : "\(low) battery low"
        case .spotify:
            let recent = pins.filter { $0.lastOpened != nil }.max { ($0.lastOpened ?? .distantPast) < ($1.lastOpened ?? .distantPast) }
            return recent?.title ?? "\(pins.count) pinned"
        case .diary:
            if calendar.access == .granted {
                return calendar.today.isEmpty ? "Clear today" : "\(calendar.today.count) today"
            }
            let wroteToday = entries.contains { Calendar.current.isDateInToday($0.day) && !$0.text.isEmpty }
            return wroteToday ? "Written today" : "Not written today"
        }
    }

    private var attention: [Attention] {
        var items: [Attention] = []
        for d in deadlines where Days.count(to: d.date) <= 30 {
            items.append(Attention(id: "d\(d.persistentModelID.hashValue)", spine: .tesla, symbol: d.symbol,
                                   title: d.title, detail: Days.short(Days.count(to: d.date))))
        }
        for c in cameras where c.battery < 0.25 {
            items.append(Attention(id: "c\(c.persistentModelID.hashValue)", spine: .ring, symbol: "battery.25",
                                   title: "\(c.name) battery", detail: c.battery.formatted(.percent.precision(.fractionLength(0)))))
        }
        let stale = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        for t in todos where !t.done && t.created < stale {
            let spine = Spine(rawValue: t.spineRaw) ?? .tesla
            let weeks = max(2, Calendar.current.dateComponents([.weekOfYear], from: t.created, to: .now).weekOfYear ?? 2)
            items.append(Attention(id: "t\(t.persistentModelID.hashValue)", spine: spine, symbol: "clock",
                                   title: t.title, detail: "\(weeks) wk"))
        }
        return items
    }
}

struct AttentionRow: View {
    let item: HomePage.Attention

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(item.spine.tint)
                .frame(width: 20)
            Text(item.title)
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: 4)
            Text(item.detail)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(item.spine.tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

/// One row per spine, each led by a sliver of its pigment.
struct StatusRow: View {
    let spine: Spine
    let status: String

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(spine.fill.gradient)
                .frame(width: 4, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(spine.title)
                    .font(.body.weight(.semibold))
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}
