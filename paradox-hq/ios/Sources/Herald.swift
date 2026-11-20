import Foundation
import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks
import WidgetKit

// Notifications without a server. iOS wakes the app in the background every so
// often; it asks Stripe what's new since it last looked and says so. That makes
// them minutes to hours late, never instant: instant needs Stripe's webhook to
// reach Apple's push service, which is a server's job.

nonisolated enum AnnouncementKind: String, Sendable {
    case payment, payout, dispute
}

nonisolated struct Announcement: Equatable, Sendable {
    let id: String
    let kind: AnnouncementKind
    let title: String
    let body: String
}

/// What has already been announced, so nothing is said twice.
nonisolated struct Seen: Codable, Equatable, Sendable {
    var lastPayment: Date? = nil
    var payouts: Set<String> = []
    var disputes: Set<String> = []
}

nonisolated enum Herald {
    /// Works out what's new in a snapshot. The first time it sees an account it
    /// says nothing and just takes note, so connecting Stripe doesn't set off a
    /// notification for every payment there has ever been.
    static func digest(_ snapshot: Snapshot, seen: Seen, locale: Locale = .current,
                       calendar: Calendar = .current) -> (announcements: [Announcement], seen: Seen) {
        var next = seen
        var out: [Announcement] = []
        let first = seen.lastPayment == nil
        let currency = snapshot.currency
        func money(_ minor: Int) -> String {
            Money.string(minor, currency: currency, pennies: true, locale: locale)
        }
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)

        let newest = snapshot.payments.map(\.date).max()
        if let last = seen.lastPayment {
            let fresh = snapshot.payments
                .filter { $0.date > last && $0.status == .succeeded }
                .sorted { $0.date < $1.date }
            if fresh.count > 3 {
                let sum = fresh.reduce(0) { $0 + $1.amount }
                out.append(Announcement(id: "payments-\(Int(last.timeIntervalSince1970))", kind: .payment,
                                        title: "\(fresh.count) payments received", body: "\(money(sum)) in total"))
            } else {
                for payment in fresh {
                    let what = payment.what.isEmpty ? "" : " · \(payment.what)"
                    out.append(Announcement(id: "payment-\(payment.id)", kind: .payment,
                                            title: "Payment received",
                                            body: "\(money(payment.amount)) from \(payment.who)\(what)"))
                }
            }
        }
        let epoch = Date(timeIntervalSince1970: 0)
        next.lastPayment = max(seen.lastPayment ?? epoch, newest ?? epoch)

        if !first {
            for payout in snapshot.payouts where payout.isUpcoming && !seen.payouts.contains(payout.id) {
                out.append(Announcement(id: "payout-\(payout.id)", kind: .payout,
                                        title: "Payout on its way",
                                        body: "\(money(payout.amount)) lands \(payout.arrives.formatted(style.weekday(.wide)))"))
            }
            for dispute in snapshot.disputes where dispute.needsResponse && !seen.disputes.contains(dispute.id) {
                var body = dispute.reason.isEmpty ? "Needs a response" : dispute.reason.capitalized
                if let due = dispute.due {
                    body = "Respond by \(due.formatted(style.weekday(.abbreviated).day().month(.abbreviated)))"
                }
                out.append(Announcement(id: "dispute-\(dispute.id)", kind: .dispute,
                                        title: "Dispute: \(money(dispute.amount))", body: body))
            }
        }
        next.payouts = Set(snapshot.payouts.map(\.id))
        next.disputes = Set(snapshot.disputes.map(\.id))
        return (out, next)
    }

    static func load() -> Seen {
        guard let data = UserDefaults.standard.data(forKey: "seen"),
              let seen = try? JSONDecoder().decode(Seen.self, from: data) else { return Seen() }
        return seen
    }

    static func save(_ seen: Seen) {
        guard let data = try? JSONEncoder().encode(seen) else { return }
        UserDefaults.standard.set(data, forKey: "seen")
    }

    /// The app is open and the figures are on screen: note them, say nothing.
    static func absorb(_ snapshot: Snapshot) {
        save(digest(snapshot, seen: load()).seen)
    }
}

/// Which notifications are wanted, and the sending of them.
enum Notifier {
    static func wants(_ kind: AnnouncementKind) -> Bool {
        UserDefaults.standard.object(forKey: "notify-\(kind.rawValue)") as? Bool ?? true
    }

    static var wantsDeadlines: Bool {
        UserDefaults.standard.object(forKey: "notify-deadline") as? Bool ?? true
    }

    @discardableResult
    static func ask() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func post(_ announcement: Announcement) async {
        let content = UNMutableNotificationContent()
        content.title = announcement.title
        content.body = announcement.body
        content.sound = .default
        let request = UNNotificationRequest(identifier: announcement.id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Deadlines are known in advance, so their reminders are set on the phone's
    /// own clock: 09:00, seven days before and the day before.
    static func remind(of deadlines: [Deadline], now: Date = .now, calendar: Calendar = .current) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard wantsDeadlines else { return }
        for deadline in deadlines {
            for ahead in [7, 1] {
                guard let day = calendar.date(byAdding: .day, value: -ahead, to: calendar.startOfDay(for: deadline.date)),
                      let moment = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day),
                      moment > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = deadline.title
                let who = deadline.who.isEmpty ? "" : " · \(deadline.who)"
                content.body = (ahead == 1 ? "Due tomorrow" : "Due in \(ahead) days") + who
                content.sound = .default
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: moment)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                let id = "deadline-\(deadline.title)-\(Int(deadline.date.timeIntervalSince1970))-\(ahead)"
                try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
    }
}

/// What iOS runs when it wakes the app in the background.
enum Background {
    static let id = "com.labern.paradox.hq.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: id)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func run() async {
        schedule()
        guard let key = Keychain.get(MoneyStore.keyName),
              let snapshot = try? await StripeClient(key: key).snapshot(since: MoneyStore.horizon(now: .now)) else { return }
        let result = Herald.digest(snapshot, seen: Herald.load())
        for announcement in result.announcements where Notifier.wants(announcement.kind) {
            await Notifier.post(announcement)
        }
        Herald.save(result.seen)

        var widget = WidgetSnapshot.load() ?? WidgetSnapshot()
        Bridge.fill(&widget, from: snapshot, example: false, now: .now, calendar: .current)
        widget.needs = widget.otherNeeds + Bridge.moneyNeeds(snapshot, now: .now)
        widget.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// One thing waiting on a decision.
struct Need: Identifiable {
    let id: String
    let color: Color
    let title: String
    let detail: String
}

/// Turns the app's state into what Today lists and what the widgets draw.
enum Bridge {
    /// Disputes to answer, plus one line if payments failed this week.
    nonisolated static func moneyNeeds(_ snapshot: Snapshot, now: Date) -> Int {
        let week = now.addingTimeInterval(-7 * 86_400)
        let failed = snapshot.payments.contains { $0.status == .failed && $0.date >= week }
        return snapshot.disputes.filter(\.needsResponse).count + (failed ? 1 : 0)
    }

    nonisolated static func fill(_ widget: inout WidgetSnapshot, from snapshot: Snapshot, example: Bool,
                                 now: Date, calendar: Calendar) {
        let start = calendar.startOfDay(for: now)
        let month = Period.month.current(now: now, calendar: calendar)
        let end = now.addingTimeInterval(1)
        widget.today = Ledger.total(snapshot.payments, in: DateInterval(start: start, end: end))
        widget.month = Ledger.total(snapshot.payments, in: DateInterval(start: month.start, end: end))
        let before = Ledger.total(snapshot.payments, in: Period.month.previous(now: now, calendar: calendar))
        widget.monthChange = Ledger.change(from: before, to: widget.month)
        widget.trend = Ledger.rolling(Ledger.daily(snapshot.payments, days: 36, now: now, calendar: calendar), window: 7)
            .suffix(30).map(\.amount)
        widget.currency = snapshot.currency
        widget.example = example
        widget.updated = now
    }

    static func needs(money: MoneyStore, site: SiteMonitor, deadlines: [Deadline], now: Date = .now) -> [Need] {
        var list: [Need] = []
        for dispute in money.openDisputes {
            var detail = dispute.reason.isEmpty ? "Needs a response" : dispute.reason.capitalized
            if let due = dispute.due {
                detail = "Respond by \(due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
            }
            list.append(Need(id: dispute.id, color: Ink.hazard,
                             title: "Dispute: \(money.money(dispute.amount))", detail: detail))
        }
        let failed = money.failed(since: now.addingTimeInterval(-7 * 86_400))
        if !failed.isEmpty {
            let sum = failed.reduce(0) { $0 + $1.amount }
            list.append(Need(id: "failed", color: Ink.amber,
                             title: failed.count == 1 ? "1 payment failed" : "\(failed.count) payments failed",
                             detail: "\(money.money(sum)) in the last 7 days"))
        }
        if let problem = money.problem {
            list.append(Need(id: "stripe", color: Ink.hazard, title: "Stripe didn't answer", detail: problem))
        }
        if site.isDown {
            list.append(Need(id: "site", color: Ink.hazard, title: "\(site.host) is down", detail: "Checked just now"))
        }
        for deadline in deadlines {
            let days = Days.count(to: deadline.date, from: now)
            guard days <= 30 else { continue }
            let when = deadline.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            list.append(Need(id: "deadline-\(deadline.title)-\(deadline.date.timeIntervalSince1970)",
                             color: days < 0 ? Ink.hazard : Ink.amber,
                             title: deadline.title,
                             detail: days < 0 ? "\(when), \(-days) days late" : days == 0 ? "Due today" : "\(when), \(days) days"))
        }
        return list
    }

    /// Hands the widgets the latest figures and resets the deadline reminders.
    static func publish(money: MoneyStore, site: SiteMonitor, context: ModelContext) async {
        let deadlines = (try? context.fetch(FetchDescriptor<Deadline>(sortBy: [SortDescriptor(\Deadline.date)]))) ?? []
        let snapshot = money.snapshot
        let now = Date.now
        var widget = WidgetSnapshot()
        fill(&widget, from: snapshot, example: !money.live, now: now, calendar: .current)
        let all = needs(money: money, site: site, deadlines: deadlines, now: now).count
        let fromMoney = moneyNeeds(snapshot, now: now)
        widget.needs = all
        widget.otherNeeds = max(0, all - fromMoney)
        if WidgetSnapshot.load() != widget {
            widget.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
        await Notifier.remind(of: deadlines, now: now)
    }
}
