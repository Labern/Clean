import Foundation
import Observation

// MARK: - Periods and sums

nonisolated enum Period: String, CaseIterable, Identifiable, Sendable {
    case week, month, quarter, year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .quarter: "Quarter"
        case .year: "Year"
        }
    }

    /// What the period is compared against, as it reads in a sentence.
    var before: String {
        switch self {
        case .week: "last week"
        case .month: "last month"
        case .quarter: "last quarter"
        case .year: "last year"
        }
    }

    /// The size of one bar when the period is charted.
    var bucket: Calendar.Component {
        switch self {
        case .week, .month: .day
        case .quarter: .weekOfYear
        case .year: .month
        }
    }

    func start(now: Date, calendar: Calendar) -> Date {
        switch self {
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        case .month:
            return calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        case .quarter:
            let parts = calendar.dateComponents([.year, .month], from: now)
            let month = ((max(1, parts.month ?? 1) - 1) / 3) * 3 + 1
            return calendar.date(from: DateComponents(year: parts.year, month: month, day: 1)) ?? calendar.startOfDay(for: now)
        case .year:
            return calendar.dateInterval(of: .year, for: now)?.start ?? calendar.startOfDay(for: now)
        }
    }

    /// From the start of this period until now.
    func current(now: Date, calendar: Calendar) -> DateInterval {
        DateInterval(start: start(now: now, calendar: calendar), end: now)
    }

    /// The same stretch of the period before, so the two compare like for like.
    func previous(now: Date, calendar: Calendar) -> DateInterval {
        let begin = self.start(now: now, calendar: calendar)
        let back: Date?
        switch self {
        case .week: back = calendar.date(byAdding: .weekOfYear, value: -1, to: begin)
        case .month: back = calendar.date(byAdding: .month, value: -1, to: begin)
        case .quarter: back = calendar.date(byAdding: .month, value: -3, to: begin)
        case .year: back = calendar.date(byAdding: .year, value: -1, to: begin)
        }
        let from = back ?? begin
        let end = min(begin, from.addingTimeInterval(now.timeIntervalSince(begin)))
        return DateInterval(start: from, end: max(from, end))
    }
}

nonisolated struct Bucket: Identifiable, Equatable, Sendable {
    let date: Date
    let amount: Int
    var id: Date { date }
}

/// Everyone who has paid, summed up.
nonisolated struct Customer: Identifiable, Hashable, Sendable {
    let name: String
    let total: Int
    let count: Int
    let last: Date
    var id: String { name }
}

nonisolated enum Ledger {
    /// Customers by what they've paid in all, biggest first.
    static func customers(_ payments: [Payment]) -> [Customer] {
        var sums: [String: (total: Int, count: Int, last: Date)] = [:]
        for payment in payments where payment.counted > 0 {
            let now = sums[payment.who] ?? (0, 0, payment.date)
            sums[payment.who] = (now.total + payment.counted, now.count + 1, max(now.last, payment.date))
        }
        return sums.map { Customer(name: $0.key, total: $0.value.total, count: $0.value.count, last: $0.value.last) }
            .sorted { ($1.total, $0.name) < ($0.total, $1.name) }
    }

    /// Revenue in a stretch of time: from its start up to, not including, its end.
    static func total(_ payments: [Payment], in interval: DateInterval) -> Int {
        payments.reduce(0) { sum, payment in
            payment.date >= interval.start && payment.date < interval.end ? sum + payment.counted : sum
        }
    }

    static func fees(_ payments: [Payment], in interval: DateInterval) -> Int {
        payments.reduce(0) { sum, payment in
            payment.date >= interval.start && payment.date < interval.end ? sum + (payment.fee ?? 0) : sum
        }
    }

    static func refunds(_ payments: [Payment], in interval: DateInterval) -> Int {
        payments.reduce(0) { sum, payment in
            payment.date >= interval.start && payment.date < interval.end ? sum + payment.refunded : sum
        }
    }

    static func sales(_ payments: [Payment], in interval: DateInterval) -> Int {
        payments.filter { $0.date >= interval.start && $0.date < interval.end && $0.counted > 0 }.count
    }

    /// Fractional change, or nil when there's nothing to compare against.
    static func change(from previous: Int, to current: Int) -> Double? {
        guard previous > 0 else { return nil }
        return Double(current - previous) / Double(previous)
    }

    /// Revenue cut into equal steps of the calendar, oldest first.
    static func buckets(_ payments: [Payment], from start: Date, to end: Date,
                        by component: Calendar.Component, calendar: Calendar) -> [Bucket] {
        var result: [Bucket] = []
        var cursor = start
        while cursor < end, result.count < 400 {
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor), next > cursor else { break }
            result.append(Bucket(date: cursor, amount: total(payments, in: DateInterval(start: cursor, end: next))))
            cursor = next
        }
        return result
    }

    /// One bucket per day for the last `days` days, ending today.
    static func daily(_ payments: [Payment], days: Int, now: Date, calendar: Calendar) -> [Bucket] {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }
        return buckets(payments, from: start, to: end, by: .day, calendar: calendar)
    }

    /// A trailing average, to calm a spiky daily series into a trend.
    static func rolling(_ buckets: [Bucket], window: Int) -> [Bucket] {
        buckets.indices.map { index in
            let from = max(0, index - window + 1)
            let slice = buckets[from...index]
            return Bucket(date: buckets[index].date, amount: slice.reduce(0) { $0 + $1.amount } / slice.count)
        }
    }
}

// MARK: - Example figures

/// Shown until a Stripe key is connected, and always labelled as an example.
/// The prices are Focus Pro's: £5 a month, £50 a year, £99 once.
nonisolated enum Example {
    nonisolated private struct Dice {
        var state: UInt64
        mutating func roll(_ sides: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(max(1, sides)))
        }
    }

    private static let buyers = [
        "A. Okafor", "M. Lindqvist", "R. Castellanos", "J. Whitcombe", "S. Nakamura", "E. Brandt",
        "T. Achterberg", "L. Moreau", "D. Ferreira", "K. Sandoval", "P. Hartley", "N. Ivanova",
    ]

    static func snapshot(now: Date, calendar: Calendar = .current) -> Snapshot {
        var dice = Dice(state: 20261117)
        var payments: [Payment] = []
        let today = calendar.startOfDay(for: now)
        let elapsed = max(60, Int(now.timeIntervalSince(today)))

        for back in 0..<420 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            // Sales thin out the further back you look: a business that's growing.
            let ceiling = back < 30 ? 6 : back < 120 ? 4 : back < 260 ? 3 : 2
            let count = dice.roll(ceiling)
            for n in 0..<count {
                let pick = dice.roll(10)
                let amount: Int
                let what: String
                if pick < 5 {
                    amount = 500
                    what = "Focus Pro, monthly"
                } else if pick < 8 {
                    amount = 5000
                    what = "Focus Pro, yearly"
                } else {
                    amount = 9900
                    what = "Focus Pro, forever"
                }
                let seconds = back == 0 ? dice.roll(elapsed) : 8 * 3600 + dice.roll(13 * 3600)
                let fee = Int((Double(amount) * 0.015).rounded()) + 20
                let slip = dice.roll(60)
                var status = PaymentStatus.succeeded
                if slip == 0 { status = .refunded }
                if slip == 1 { status = .failed }
                let cards = ["Visa", "Mastercard", "Amex"]
                let method = "\(cards[dice.roll(cards.count)]) ···· \(1000 + dice.roll(9000))"
                payments.append(Payment(
                    id: "example_\(back)_\(n)",
                    amount: amount,
                    refunded: status == .refunded ? amount : 0,
                    fee: status == .failed ? nil : fee,
                    net: status == .failed ? nil : amount - fee,
                    date: day.addingTimeInterval(TimeInterval(seconds)),
                    status: status,
                    who: buyers[dice.roll(buyers.count)],
                    what: what,
                    method: method))
            }
        }
        payments.sort { $0.date > $1.date }

        var snapshot = Snapshot()
        snapshot.payments = payments
        let recent = payments.filter { now.timeIntervalSince($0.date) < 3 * 86_400 }
        let upcoming = recent.reduce(0) { $0 + ($1.net ?? 0) }
        func day(_ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: today) ?? today }
        snapshot.payouts = [
            Payout(id: "example_po_1", amount: max(upcoming, 4200), arrives: day(2), status: "in_transit"),
            Payout(id: "example_po_2", amount: 31_840, arrives: day(-5), status: "paid"),
            Payout(id: "example_po_3", amount: 27_310, arrives: day(-12), status: "paid"),
        ]
        snapshot.disputes = [
            Dispute(id: "example_dp_1", amount: 9900, reason: "product not received", due: day(7), status: "needs_response"),
        ]
        snapshot.available = 62_120
        snapshot.pending = max(upcoming, 4200)
        snapshot.subscribers = 46
        snapshot.mrr = 26_500
        return snapshot
    }
}

// MARK: - The store

@Observable final class MoneyStore {
    static let keyName = "stripe-key"

    /// False while the figures on screen are the example ones.
    var live = false
    var payments: [Payment] = []
    var payouts: [Payout] = []
    var disputes: [Dispute] = []
    var available = 0
    var pending = 0
    var subscribers: Int? = nil
    var mrr: Int? = nil
    var currency = "gbp"
    var loading = false
    var problem: String? = nil
    var updated: Date? = nil

    init() {
        show(Example.snapshot(now: .now))
    }

    var hasKey: Bool { Keychain.get(Self.keyName) != nil }

    var nextPayout: Payout? {
        payouts.filter(\.isUpcoming).min { $0.arrives < $1.arrives }
    }

    var openDisputes: [Dispute] { disputes.filter(\.needsResponse) }

    func failed(since date: Date) -> [Payment] {
        payments.filter { $0.status == .failed && $0.date >= date }
    }

    func money(_ minor: Int, pennies: Bool = false) -> String {
        Money.string(minor, currency: currency, pennies: pennies)
    }

    /// The figures on screen, as one value.
    var snapshot: Snapshot {
        Snapshot(payments: payments, payouts: payouts, disputes: disputes, available: available,
                 pending: pending, subscribers: subscribers, mrr: mrr, currency: currency)
    }

    private func show(_ snapshot: Snapshot) {
        payments = snapshot.payments
        payouts = snapshot.payouts
        disputes = snapshot.disputes
        available = snapshot.available
        pending = snapshot.pending
        subscribers = snapshot.subscribers
        mrr = snapshot.mrr
        currency = snapshot.currency
    }

    /// Two calendar years back, so a year can be compared with the one before.
    nonisolated static func horizon(now: Date, calendar: Calendar = .current) -> Date {
        let year = calendar.dateInterval(of: .year, for: now)?.start ?? now
        return calendar.date(byAdding: .year, value: -1, to: year) ?? year
    }

    func refresh() async {
        guard !loading else { return }
        guard let key = Keychain.get(Self.keyName) else {
            live = false
            problem = nil
            show(Example.snapshot(now: .now))
            return
        }
        loading = true
        defer { loading = false }
        do {
            let snapshot = try await StripeClient(key: key).snapshot(since: Self.horizon(now: .now))
            show(snapshot)
            Herald.absorb(snapshot)
            live = true
            problem = nil
            updated = .now
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Tries a key against Stripe and keeps it only if it works.
    /// Returns what went wrong, or nil.
    func connect(_ key: String) async -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("rk_") || trimmed.hasPrefix("sk_") else {
            return "That doesn't look like a Stripe key. It starts rk_live_."
        }
        loading = true
        defer { loading = false }
        do {
            let snapshot = try await StripeClient(key: trimmed).snapshot(since: Self.horizon(now: .now))
            guard Keychain.set(trimmed, for: Self.keyName) else {
                return "The key worked, but the Keychain wouldn't store it."
            }
            show(snapshot)
            Herald.absorb(snapshot)
            live = true
            problem = nil
            updated = .now
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func disconnect() {
        Keychain.delete(Self.keyName)
        Herald.save(Seen())
        live = false
        problem = nil
        updated = nil
        show(Example.snapshot(now: .now))
    }
}
