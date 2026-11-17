import Testing
import Foundation
import SwiftData
@testable import ParadoxHQ

private let london: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/London")!
    calendar.locale = Locale(identifier: "en_GB")
    calendar.firstWeekday = 2
    return calendar
}()

private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
    london.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

private func paid(_ amount: Int, _ date: Date, refunded: Int = 0, status: PaymentStatus = .succeeded) -> Payment {
    Payment(id: UUID().uuidString, amount: amount, refunded: refunded, fee: 20, net: amount - 20,
            date: date, status: status, who: "Test")
}

@Suite("Money")
struct MoneyTests {
    @Test func wholePounds() {
        #expect(Money.string(184_000, locale: Locale(identifier: "en_GB")) == "£1,840")
    }

    @Test func withPennies() {
        #expect(Money.string(236_370, pennies: true, locale: Locale(identifier: "en_GB")) == "£2,363.70")
    }
}

@Suite("Stripe decoding")
struct StripeDecodingTests {
    static let charges = """
    {"object":"list","has_more":false,"data":[
      {"id":"ch_1","amount":9900,"amount_refunded":0,"currency":"gbp","created":1794873600,"status":"succeeded",
       "paid":true,"refunded":false,"disputed":false,"description":"Focus Pro","receipt_email":"a@example.com",
       "billing_details":{"name":"Ada Example","email":"a@example.com"},
       "payment_method_details":{"type":"card","card":{"brand":"visa","last4":"4242"}},
       "balance_transaction":{"id":"txn_1","fee":169,"net":9731}},
      {"id":"ch_2","amount":500,"amount_refunded":500,"currency":"gbp","created":1794870000,"status":"succeeded",
       "paid":true,"refunded":true,"disputed":false,"description":null,"receipt_email":"b@example.com",
       "billing_details":{"name":null,"email":null},
       "payment_method_details":null,
       "balance_transaction":"txn_2"},
      {"id":"ch_3","amount":5000,"amount_refunded":0,"currency":"gbp","created":1794860000,"status":"failed",
       "paid":false,"refunded":false,"disputed":false,"description":null,"receipt_email":null,
       "billing_details":null,"payment_method_details":null,"balance_transaction":null}
    ]}
    """

    @Test func chargesBecomePayments() throws {
        let list = try StripeClient.decoder().decode(StripeList<StripeCharge>.self, from: Data(Self.charges.utf8))
        let payments = list.data.map { Payment($0) }
        #expect(payments.count == 3)

        #expect(payments[0].status == .succeeded)
        #expect(payments[0].who == "Ada Example")
        #expect(payments[0].method == "Visa ···· 4242")
        #expect(payments[0].fee == 169)
        #expect(payments[0].net == 9731)
        #expect(payments[0].counted == 9900)

        // An id where the fee object would be: the fee is unknown, nothing else breaks.
        #expect(payments[1].status == .refunded)
        #expect(payments[1].fee == nil)
        #expect(payments[1].who == "b@example.com")
        #expect(payments[1].counted == 0)

        #expect(payments[2].status == .failed)
        #expect(payments[2].who == "Customer")
        #expect(payments[2].counted == 0)
    }

    @Test func subscriptionsBecomeMonthlyRevenue() throws {
        let json = """
        {"has_more":false,"data":[
          {"id":"sub_1","items":{"data":[{"quantity":1,"price":{"unit_amount":500,"recurring":{"interval":"month","interval_count":1}}}]}},
          {"id":"sub_2","items":{"data":[{"quantity":1,"price":{"unit_amount":6000,"recurring":{"interval":"year","interval_count":1}}}]}}
        ]}
        """
        let list = try StripeClient.decoder().decode(StripeList<StripeSubscription>.self, from: Data(json.utf8))
        #expect(list.data.map(\.monthly) == [500, 500])
    }

    @Test func errorsCarryStripesWords() throws {
        let json = #"{"error":{"message":"Invalid API Key provided","type":"invalid_request_error"}}"#
        let failure = try StripeClient.decoder().decode(StripeFailure.self, from: Data(json.utf8))
        #expect(failure.error.message == "Invalid API Key provided")
    }
}

@Suite("Ledger")
struct LedgerTests {
    @Test func totalsCountWhatWasKept() {
        let day = at(2026, 11, 17)
        let payments = [
            paid(9900, day),
            paid(5000, day, refunded: 5000, status: .refunded),
            paid(5000, day, refunded: 1000),
            paid(500, day, status: .failed),
            paid(500, at(2026, 11, 18)),
        ]
        let interval = DateInterval(start: at(2026, 11, 17, 0), end: at(2026, 11, 18, 0))
        #expect(Ledger.total(payments, in: interval) == 9900 + 4000)
        #expect(Ledger.refunds(payments, in: interval) == 6000)
        #expect(Ledger.sales(payments, in: interval) == 2)
    }

    @Test func monthComparesLikeForLike() {
        let now = at(2026, 11, 17, 12)
        let current = Period.month.current(now: now, calendar: london)
        let previous = Period.month.previous(now: now, calendar: london)
        #expect(current.start == at(2026, 11, 1, 0))
        #expect(previous.start == at(2026, 10, 1, 0))
        #expect(abs(previous.duration - current.duration) < 1)
    }

    @Test func quarterStartsOnItsFirstMonth() {
        #expect(Period.quarter.start(now: at(2026, 11, 17), calendar: london) == at(2026, 10, 1, 0))
        #expect(Period.quarter.start(now: at(2026, 2, 3), calendar: london) == at(2026, 1, 1, 0))
        #expect(Period.year.start(now: at(2026, 11, 17), calendar: london) == at(2026, 1, 1, 0))
    }

    @Test func dailyBucketsEndToday() {
        let now = at(2026, 11, 17, 15)
        let payments = [paid(500, at(2026, 11, 17, 9)), paid(500, at(2026, 11, 17, 10)), paid(9900, at(2026, 11, 15))]
        let days = Ledger.daily(payments, days: 7, now: now, calendar: london)
        #expect(days.count == 7)
        #expect(days.last?.amount == 1000)
        #expect(days[4].amount == 9900)
        #expect(days.first?.date == at(2026, 11, 11, 0))
    }

    @Test func rollingAveragesTheTrailingWindow() {
        let buckets = [10, 20, 30, 40].enumerated().map { Bucket(date: at(2026, 11, 1 + $0.offset), amount: $0.element) }
        #expect(Ledger.rolling(buckets, window: 2).map(\.amount) == [10, 15, 25, 35])
    }

    @Test func changeNeedsSomethingToCompare() {
        #expect(Ledger.change(from: 0, to: 500) == nil)
        #expect(Ledger.change(from: 1000, to: 1230) == 0.23)
    }

    @Test func exampleFiguresAreStable() {
        let now = at(2026, 11, 17, 12)
        let first = Example.snapshot(now: now, calendar: london)
        let second = Example.snapshot(now: now, calendar: london)
        #expect(first.payments == second.payments)
        #expect(first.payments.count > 200)
        #expect(first.payments.allSatisfy { $0.date <= now })
    }
}

@Suite("Feed")
@MainActor
struct FeedTests {
    static func store() throws -> ModelContext {
        let container = try ModelContainer(for: Project.self, FocusItem.self, Deadline.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    static let json = """
    {"projects":[{"id":"focus","name":"Focus","stage":"0.19","tint":"A78BFA","items":[
      {"id":"a","title":"Add Stripe","children":[{"id":"a1","title":"Live keys"},{"id":"a2","title":"Tax"}]},
      {"id":"b","title":"Tutorial"}
    ]}]}
    """

    @Test func bundledFeedIsValid() throws {
        let feed = try #require(Feed.bundled())
        #expect(feed.projects.count >= 3)
        #expect(feed.projects.contains { $0.id == "focus" })
    }

    @Test func firstPullCreatesEverything() throws {
        let context = try Self.store()
        let outcome = try Feed.decode(Data(Self.json.utf8)).apply(to: context)
        #expect(outcome == FeedOutcome(projects: 1, items: 4, ticked: 0))

        let project = try #require(try context.fetch(FetchDescriptor<Project>()).first)
        #expect(project.name == "Focus")
        #expect(project.tint == 0xA78BFA)
        #expect(project.sortedItems.map(\.title) == ["Add Stripe", "Tutorial"])
        #expect(project.sortedItems[0].sortedChildren.map(\.title) == ["Live keys", "Tax"])
        #expect(project.tally.total == 3)
    }

    @Test func pullingAgainChangesNothing() throws {
        let context = try Self.store()
        let feed = try Feed.decode(Data(Self.json.utf8))
        feed.apply(to: context)
        #expect(feed.apply(to: context) == FeedOutcome())
        #expect(try context.fetchCount(FetchDescriptor<FocusItem>()) == 4)
    }

    @Test func ticksOnThePhoneSurviveAPull() throws {
        let context = try Self.store()
        let feed = try Feed.decode(Data(Self.json.utf8))
        feed.apply(to: context)
        let project = try #require(try context.fetch(FetchDescriptor<Project>()).first)
        let tutorial = try #require(project.sortedItems.last)
        tutorial.set(done: true)
        feed.apply(to: context)
        #expect(tutorial.done)
    }

    @Test func aTickFromClaudeLandsAndNewLinesAppend() throws {
        let context = try Self.store()
        try Feed.decode(Data(Self.json.utf8)).apply(to: context)
        let next = """
        {"projects":[{"id":"focus","name":"Focus","items":[
          {"id":"b","title":"Tutorial","done":true},
          {"id":"c","title":"Named sessions"}
        ]}]}
        """
        let outcome = try Feed.decode(Data(next.utf8)).apply(to: context)
        #expect(outcome == FeedOutcome(projects: 0, items: 1, ticked: 1))
        let project = try #require(try context.fetch(FetchDescriptor<Project>()).first)
        #expect(project.sortedItems.map(\.title) == ["Add Stripe", "Tutorial", "Named sessions"])
        #expect(project.openItems.map(\.title) == ["Add Stripe", "Named sessions"])
    }

    @Test func projectsMadeOnThePhoneAreLeftAlone() throws {
        let context = try Self.store()
        let mine = Project(name: "Mine")
        context.insert(mine)
        try Feed.decode(Data(Self.json.utf8)).apply(to: context)
        #expect(try context.fetchCount(FetchDescriptor<Project>()) == 2)
        #expect(mine.name == "Mine")
        #expect(mine.items.isEmpty)
    }
}

@Suite("Focus lines")
@MainActor
struct FocusLineTests {
    @Test func tickingRunsUpAndDownTheTree() throws {
        let context = try FeedTests.store()
        let parent = FocusItem(title: "Stripe live")
        let one = FocusItem(title: "Keys")
        let two = FocusItem(title: "Tax", order: 1)
        context.insert(parent)
        context.insert(one)
        context.insert(two)
        one.parent = parent
        two.parent = parent

        one.set(done: true)
        #expect(!parent.done)
        two.set(done: true)
        #expect(parent.done)
        one.set(done: false)
        #expect(!parent.done)
        parent.set(done: true)
        #expect(one.done && two.done)
    }

    @Test func aRepeatingDeadlineRollsForward() {
        let yearly = Deadline(title: "Confirmation statement", date: at(2026, 2, 14), everyMonths: 12)
        #expect(yearly.markDone(calendar: london))
        #expect(yearly.date == at(2027, 2, 14))
        let once = Deadline(title: "One-off", date: at(2026, 2, 14), everyMonths: 0)
        #expect(!once.markDone(calendar: london))
    }
}

@Suite("Customers")
struct CustomerTests {
    @Test func rankedByWhatTheyPaid() {
        let day = at(2026, 11, 17)
        let payments = [
            Payment(id: "1", amount: 500, date: day, who: "Small"),
            Payment(id: "2", amount: 9900, date: day, who: "Big"),
            Payment(id: "3", amount: 5000, date: at(2026, 11, 18), who: "Big"),
            Payment(id: "4", amount: 9900, refunded: 9900, date: day, status: .refunded, who: "Refunded"),
            Payment(id: "5", amount: 500, date: day, status: .failed, who: "Failed"),
        ]
        let customers = Ledger.customers(payments)
        #expect(customers.map(\.name) == ["Big", "Small"])
        #expect(customers[0].total == 14_900)
        #expect(customers[0].count == 2)
        #expect(customers[0].last == at(2026, 11, 18))
    }
}

@Suite("Notifications")
struct HeraldTests {
    static let gb = Locale(identifier: "en_GB")

    static func snapshot(_ payments: [Payment], payouts: [Payout] = [], disputes: [Dispute] = []) -> Snapshot {
        Snapshot(payments: payments, payouts: payouts, disputes: disputes)
    }

    @Test func theFirstLookSaysNothing() {
        let snapshot = Self.snapshot(
            [paid(5000, at(2026, 11, 16)), paid(500, at(2026, 11, 17))],
            payouts: [Payout(id: "po_1", amount: 4000, arrives: at(2026, 11, 19), status: "in_transit")],
            disputes: [Dispute(id: "dp_1", amount: 9900, reason: "fraudulent", due: at(2026, 11, 24), status: "needs_response")])
        let result = Herald.digest(snapshot, seen: Seen(), locale: Self.gb, calendar: london)
        #expect(result.announcements.isEmpty)
        #expect(result.seen.lastPayment == at(2026, 11, 17))
        #expect(result.seen.payouts == ["po_1"])
        #expect(result.seen.disputes == ["dp_1"])
    }

    @Test func aNewPaymentIsAnnouncedOnce() {
        let old = paid(5000, at(2026, 11, 16))
        let new = Payment(id: "ch_new", amount: 5000, date: at(2026, 11, 17), who: "Ada Example", what: "Focus Pro, yearly")
        let failed = Payment(id: "ch_bad", amount: 500, date: at(2026, 11, 17, 13), status: .failed, who: "Nobody")
        let seen = Seen(lastPayment: at(2026, 11, 16))
        let first = Herald.digest(Self.snapshot([old, new, failed]), seen: seen, locale: Self.gb, calendar: london)
        #expect(first.announcements == [
            Announcement(id: "payment-ch_new", kind: .payment, title: "Payment received",
                         body: "£50.00 from Ada Example · Focus Pro, yearly"),
        ])
        let second = Herald.digest(Self.snapshot([old, new, failed]), seen: first.seen, locale: Self.gb, calendar: london)
        #expect(second.announcements.isEmpty)
    }

    @Test func aBurstBecomesOneNotification() {
        let payments = (0..<5).map { paid(500, at(2026, 11, 17, 9 + $0)) }
        let seen = Seen(lastPayment: at(2026, 11, 16))
        let result = Herald.digest(Self.snapshot(payments), seen: seen, locale: Self.gb, calendar: london)
        #expect(result.announcements.count == 1)
        #expect(result.announcements[0].title == "5 payments received")
        #expect(result.announcements[0].body == "£25.00 in total")
    }

    @Test func newPayoutsAndDisputesAreAnnounced() {
        let seen = Seen(lastPayment: at(2026, 11, 16), payouts: ["po_old"], disputes: [])
        let snapshot = Self.snapshot(
            [],
            payouts: [Payout(id: "po_old", amount: 100, arrives: at(2026, 11, 10), status: "paid"),
                      Payout(id: "po_new", amount: 51_200, arrives: at(2026, 11, 19), status: "in_transit")],
            disputes: [Dispute(id: "dp_1", amount: 9900, reason: "", due: nil, status: "needs_response"),
                       Dispute(id: "dp_won", amount: 500, reason: "", due: nil, status: "won")])
        let result = Herald.digest(snapshot, seen: seen, locale: Self.gb, calendar: london)
        #expect(result.announcements.map(\.kind) == [.payout, .dispute])
        #expect(result.announcements[0].body == "£512.00 lands Thursday")
        #expect(result.announcements[1].title == "Dispute: £99.00")
        #expect(Herald.digest(snapshot, seen: result.seen, locale: Self.gb, calendar: london).announcements.isEmpty)
    }
}

@Suite("Widgets")
struct WidgetTests {
    @Test func snapshotSurvivesTheTrip() throws {
        let data = try JSONEncoder().encode(WidgetSnapshot.sample)
        #expect(try JSONDecoder().decode(WidgetSnapshot.self, from: data) == WidgetSnapshot.sample)
    }

    @Test func todayResetsWhenTheDayTurns() {
        var snapshot = WidgetSnapshot.sample
        snapshot.updated = at(2026, 11, 17, 18)
        #expect(snapshot.todayValue(now: at(2026, 11, 17, 23), calendar: london) == 18_400)
        #expect(snapshot.todayValue(now: at(2026, 11, 18, 1), calendar: london) == 0)
    }

    @Test func compactFigures() {
        let gb = Locale(identifier: "en_GB")
        #expect(Money.compact(84_000, locale: gb) == "£840")
        #expect(Money.compact(184_200, locale: gb) == "£1.8k")
        #expect(Money.compact(12_400_000, locale: gb) == "£124k")
    }

    @Test func filledFromTheLedger() {
        let now = at(2026, 11, 17, 15)
        let snapshot = Snapshot(payments: [
            paid(5000, at(2026, 11, 17, 9)), paid(9900, at(2026, 11, 3)), paid(5000, at(2026, 10, 5)),
        ])
        var widget = WidgetSnapshot()
        Bridge.fill(&widget, from: snapshot, example: false, now: now, calendar: london)
        #expect(widget.today == 5000)
        #expect(widget.month == 14_900)
        #expect(widget.monthChange == Ledger.change(from: 5000, to: 14_900))
        #expect(widget.trend.count == 30)
        #expect(!widget.example)
    }

    @Test func sparklineSpansItsBox() {
        let points = Sparkline.points([0, 50, 100], in: CGSize(width: 100, height: 40))
        #expect(points.map(\.x) == [0, 50, 100])
        #expect(points[0].y > points[2].y)
        #expect(Sparkline.points([7], in: CGSize(width: 100, height: 40)).isEmpty)
    }
}

@Suite("Sending back to the feed")
@MainActor
struct OutboxTests {
    @Test func gitHubLinksInEveryShape() {
        let expected = FeedAddress(owner: "acme", repo: "hq", path: "data/feed.json", ref: "main")
        #expect(FeedAddress.github("https://github.com/acme/hq/blob/main/data/feed.json") == expected)
        #expect(FeedAddress.github("https://raw.githubusercontent.com/acme/hq/main/data/feed.json") == expected)
        #expect(FeedAddress.github("https://raw.githubusercontent.com/acme/hq/refs/heads/main/data/feed.json") == expected)
        #expect(FeedAddress.github("https://api.github.com/repos/acme/hq/contents/data/feed.json?ref=main") == expected)
        #expect(FeedAddress.github("https://api.github.com/repos/acme/hq/contents/feed.json")?.ref == nil)
        #expect(FeedAddress.github("https://example.com/feed.json") == nil)
        #expect(expected.api?.absoluteString == "https://api.github.com/repos/acme/hq/contents/data/feed.json?ref=main")
    }

    @Test func ticksAndNewLinesGoIntoTheFile() throws {
        var outgoing = Outgoing()
        outgoing.ticks = ["a1", "b"]
        outgoing.lines["focus"] = [NewLine(id: "phone-1", title: "From the phone",
                                           children: [NewLine(id: "phone-2", title: "And a sub-item")])]
        outgoing.subs["a"] = [NewLine(id: "phone-3", title: "Webhooks", done: true)]

        let patched = try FeedPatch.apply(Data(FeedTests.json.utf8), outgoing)
        #expect(patched.ticked == 2)
        #expect(patched.added == 3)

        let feed = try Feed.decode(patched.data)
        let items = try #require(feed.projects.first?.items)
        #expect(items.map(\.title) == ["Add Stripe", "Tutorial", "From the phone"])
        #expect(items[0].children?.map(\.title) == ["Live keys", "Tax", "Webhooks"])
        #expect(items[0].children?.map { $0.done ?? false } == [true, false, true])
        #expect(items[1].done == true)
        #expect(items[2].children?.first?.id == "phone-2")
        // The rest of the file is carried through untouched.
        #expect(feed.projects.first?.stage == "0.19")

        // Sending the same thing again finds nothing left to do.
        let again = try FeedPatch.apply(patched.data, outgoing)
        #expect(again.ticked == 0)
        #expect(again.added == 0)
    }

    @Test func thePhonesWorkIsGatheredUp() throws {
        let context = try FeedTests.store()
        try Feed.decode(Data(FeedTests.json.utf8)).apply(to: context)
        let project = try #require(try context.fetch(FetchDescriptor<Project>()).first)
        let stripe = try #require(project.sortedItems.first)
        let tutorial = try #require(project.sortedItems.last)

        tutorial.set(done: true)
        let mine = FocusItem(title: "Made on the phone", order: project.nextOrder)
        context.insert(mine)
        mine.project = project
        let sub = FocusItem(title: "A sub-item", order: stripe.nextOrder)
        context.insert(sub)
        sub.parent = stripe

        // A project made on the phone has nowhere in the feed to go.
        let local = Project(name: "Local only")
        context.insert(local)
        let stray = FocusItem(title: "Stays here")
        context.insert(stray)
        stray.project = local

        let plan = Outbox.plan(context)
        #expect(plan.outgoing.ticks == ["b"])
        #expect(plan.outgoing.lines["focus"]?.map(\.title) == ["Made on the phone"])
        #expect(plan.outgoing.subs["a"]?.map(\.title) == ["A sub-item"])
        #expect(plan.outgoing.lines.count == 1)
        #expect(plan.naming.count == 2)
        #expect(plan.naming.allSatisfy { $0.id.hasPrefix("phone-") })

        // Once named, a second plan has nothing new to add.
        for (item, id) in plan.naming { item.remoteID = id }
        let next = Outbox.plan(context)
        #expect(next.outgoing.lines.isEmpty)
        #expect(next.outgoing.subs.isEmpty)
    }
}
