import Testing
import Foundation
import SwiftData
import SwiftUI
import UIKit
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
        let container = try ModelContainer(for: Project.self, FocusItem.self, Deadline.self, Note.self,
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

    private static func line(_ title: String, under parent: FocusItem? = nil, in project: Project? = nil,
                             _ context: ModelContext) -> FocusItem {
        let item = FocusItem(title: title, order: parent?.nextOrder ?? project?.nextOrder ?? 0)
        context.insert(item)
        if let parent { item.parent = parent } else { item.project = project }
        return item
    }

    @Test func tickingRunsThroughEveryDepth() throws {
        let context = try FeedTests.store()
        let project = Project(name: "Site")
        context.insert(project)
        let launch = Self.line("Launch", in: project, context)
        let copy = Self.line("Copy", under: launch, context)
        let hero = Self.line("Hero", under: copy, context)
        let footer = Self.line("Footer", under: copy, context)
        let deploy = Self.line("Deploy", under: launch, context)

        hero.set(done: true)
        #expect(!copy.done)
        footer.set(done: true)
        #expect(copy.done)
        #expect(!launch.done)
        deploy.set(done: true)
        #expect(launch.done)

        // Reopening the deepest line reopens everything above it, and nothing beside it.
        hero.set(done: false)
        #expect(!copy.done && !launch.done)
        #expect(footer.done && deploy.done)

        // Ticking the top ticks every depth below.
        launch.set(done: true)
        #expect(hero.done && footer.done && copy.done && deploy.done)
    }

    @Test func theTallyCountsTheSmallestLines() throws {
        let context = try FeedTests.store()
        let project = Project(name: "Site")
        context.insert(project)
        let launch = Self.line("Launch", in: project, context)
        let copy = Self.line("Copy", under: launch, context)
        let hero = Self.line("Hero", under: copy, context)
        _ = Self.line("Footer", under: copy, context)
        _ = Self.line("Deploy", under: launch, context)
        _ = Self.line("Invoice", in: project, context)

        #expect(project.tally == (0, 4))
        hero.set(done: true)
        #expect(project.tally == (1, 4))
        #expect(copy.leaves() == (1, 2))
        #expect(hero.depth == 2)
        #expect(hero.owner === project)
        #expect(hero.ancestors.map(\.title) == ["Launch", "Copy"])
        #expect(launch.contains(hero))
        #expect(!hero.contains(launch))
    }

    @Test func addingUnderAFinishedLineReopensIt() throws {
        let context = try FeedTests.store()
        let project = Project(name: "Site")
        context.insert(project)
        let launch = Self.line("Launch", in: project, context)
        let copy = Self.line("Copy", under: launch, context)
        launch.set(done: true)
        copy.collapsed = true

        let new = copy.add("Legal page", in: context)
        #expect(new.parent === copy)
        #expect(!copy.done && !launch.done)
        #expect(!copy.collapsed)
    }

    @Test func foldedLinesHideWhatsUnderThem() throws {
        let context = try FeedTests.store()
        let project = Project(name: "Site")
        context.insert(project)
        let launch = Self.line("Launch", in: project, context)
        let copy = Self.line("Copy", under: launch, context)
        _ = Self.line("Hero", under: copy, context)
        _ = Self.line("Invoice", in: project, context)

        func titles(_ rows: [Outline.Row]) -> [String] {
            rows.map { row in
                switch row {
                case .line(let item, let depth): String(repeating: "-", count: depth) + item.title
                case .draft(let parent, let depth): String(repeating: "-", count: depth) + "[\(parent.title)]"
                }
            }
        }

        #expect(titles(Outline.rows(project.openItems)) == ["Launch", "-Copy", "--Hero", "Invoice"])
        copy.collapsed = true
        #expect(titles(Outline.rows(project.openItems)) == ["Launch", "-Copy", "Invoice"])
        launch.collapsed = true
        #expect(titles(Outline.rows(project.openItems)) == ["Launch", "Invoice"])
        // Typing under a folded line opens it for the new row.
        #expect(titles(Outline.rows(project.openItems, drafting: launch)) == ["Launch", "-Copy", "-[Launch]", "Invoice"])
    }

    @Test func linesMoveInAndOutALevel() throws {
        let context = try FeedTests.store()
        let project = Project(name: "Site")
        context.insert(project)
        let launch = Self.line("Launch", in: project, context)
        let copy = Self.line("Copy", in: project, context)
        let invoice = Self.line("Invoice", in: project, context)

        #expect(!launch.indent())
        #expect(copy.indent())
        #expect(copy.parent === launch && copy.project == nil)
        #expect(project.sortedItems.map(\.title) == ["Launch", "Invoice"])

        #expect(copy.outdent())
        #expect(copy.parent == nil && copy.project === project)
        #expect(project.sortedItems.map(\.title) == ["Launch", "Copy", "Invoice"])
        #expect(!invoice.outdent())
    }

    // MARK: Dragging

    /// A, a1, a2 under it, B, C with c1 under it, D.
    private func tree() throws -> (Project, [String: FocusItem]) {
        let context = try FeedTests.store()
        let project = Project(name: "Site")
        context.insert(project)
        var lines: [String: FocusItem] = [:]
        lines["A"] = Self.line("A", in: project, context)
        lines["a1"] = Self.line("a1", under: lines["A"]!, context)
        lines["a2"] = Self.line("a2", under: lines["A"]!, context)
        lines["B"] = Self.line("B", in: project, context)
        lines["C"] = Self.line("C", in: project, context)
        lines["c1"] = Self.line("c1", under: lines["C"]!, context)
        lines["D"] = Self.line("D", in: project, context)
        return (project, lines)
    }

    private func drawn(_ project: Project, drafting: FocusItem? = nil) -> [String] {
        Outline.rows(project.openItems, drafting: drafting).map { row in
            switch row {
            case .line(let item, let depth): String(repeating: "-", count: depth) + item.title
            case .draft(let parent, let depth): String(repeating: "-", count: depth) + "[\(parent.title)]"
            }
        }
    }

    /// Drags the row at `source` to the gap at `destination`, as a list reports it.
    private func drag(_ project: Project, _ source: Int, to destination: Int, drafting: FocusItem? = nil) -> Bool {
        Outline.move(Outline.rows(project.openItems, drafting: drafting), from: source, to: destination)
    }

    @Test func aLineDragsUpAndDownItsLevel() throws {
        let (project, _) = try tree()
        #expect(drawn(project) == ["A", "-a1", "-a2", "B", "C", "-c1", "D"])
        #expect(drag(project, 6, to: 0))
        #expect(drawn(project) == ["D", "A", "-a1", "-a2", "B", "C", "-c1"])
        // Sub-items reorder among themselves.
        #expect(drag(project, 3, to: 2))
        #expect(drawn(project) == ["D", "A", "-a2", "-a1", "B", "C", "-c1"])
    }

    @Test func aDraggedLineTakesItsSubItemsAlong() throws {
        let (project, lines) = try tree()
        #expect(drag(project, 0, to: 4))
        #expect(drawn(project) == ["B", "A", "-a1", "-a2", "C", "-c1", "D"])
        #expect(lines["a1"]?.parent === lines["A"])
    }

    @Test func aLineLandsWhereItIsLetGo() throws {
        // Between two sub-items, it becomes one.
        var (project, lines) = try tree()
        #expect(drag(project, 6, to: 2))
        #expect(drawn(project) == ["A", "-a1", "-D", "-a2", "B", "C", "-c1"])
        #expect(lines["D"]?.parent === lines["A"] && lines["D"]?.project == nil)

        // Just under a line whose sub-items are showing, it becomes the first of them.
        (project, lines) = try tree()
        #expect(drag(project, 6, to: 1))
        #expect(drawn(project) == ["A", "-D", "-a1", "-a2", "B", "C", "-c1"])

        // Above the first line, a sub-item becomes a line of the project.
        (project, lines) = try tree()
        #expect(drag(project, 1, to: 0))
        #expect(drawn(project) == ["a1", "A", "-a2", "B", "C", "-c1", "D"])
        #expect(lines["a1"]?.parent == nil && lines["a1"]?.project === project)
    }

    /// After the last sub-item of something, the gap could be either level: a line keeps its own.
    @Test func anAmbiguousGapKeepsTheLinesLevel() throws {
        var (project, lines) = try tree()
        #expect(drag(project, 5, to: 3))
        #expect(drawn(project) == ["A", "-a1", "-a2", "-c1", "B", "C", "D"])
        #expect(lines["c1"]?.parent === lines["A"])

        (project, lines) = try tree()
        #expect(drag(project, 6, to: 3))
        #expect(drawn(project) == ["A", "-a1", "-a2", "D", "B", "C", "-c1"])
        #expect(lines["D"]?.parent == nil)
    }

    @Test func droppingALineWhereItAlreadyIsChangesNothing() throws {
        let (project, _) = try tree()
        for gap in 0...3 { #expect(!drag(project, 0, to: gap), "A to \(gap)") }
        #expect(!drag(project, 2, to: 2))
        #expect(!drag(project, 2, to: 3))
        #expect(!drag(project, 3, to: 3))
        #expect(!drag(project, 3, to: 4))
        #expect(!drag(project, 9, to: 0))
        #expect(drawn(project) == ["A", "-a1", "-a2", "B", "C", "-c1", "D"])
    }

    @Test func aFoldedLineIsNotDroppedInto() throws {
        let (project, lines) = try tree()
        lines["A"]?.collapsed = true
        #expect(drawn(project) == ["A", "B", "C", "-c1", "D"])
        #expect(drag(project, 4, to: 1))
        #expect(drawn(project) == ["A", "D", "B", "C", "-c1"])
        #expect(lines["D"]?.parent == nil)
    }

    /// The row being typed in counts as the last sub-item of its line.
    @Test func draggingAroundARowBeingTyped() throws {
        var (project, lines) = try tree()
        #expect(drawn(project, drafting: lines["C"]) == ["A", "-a1", "-a2", "B", "C", "-c1", "-[C]", "D"])
        #expect(!drag(project, 6, to: 0, drafting: lines["C"]))
        #expect(drag(project, 1, to: 7, drafting: lines["C"]))
        #expect(drawn(project) == ["A", "-a2", "B", "C", "-c1", "-a1", "D"])
        #expect(lines["a1"]?.parent === lines["C"])

        (project, lines) = try tree()
        #expect(drag(project, 3, to: 7, drafting: lines["C"]))
        #expect(drawn(project) == ["A", "-a1", "-a2", "C", "-c1", "B", "D"])
        #expect(lines["B"]?.parent == nil)
    }

    @Test func aFinishedLineReopensWhenOpenWorkIsDroppedIntoIt() throws {
        let (project, lines) = try tree()
        let a1 = try #require(lines["a1"])
        let x = a1.add("x", in: try #require(a1.modelContext))
        a1.set(done: true)
        #expect(a1.done && x.done)
        #expect(drawn(project) == ["A", "-a1", "--x", "-a2", "B", "C", "-c1", "D"])
        #expect(drag(project, 7, to: 2))
        #expect(drawn(project) == ["A", "-a1", "--D", "--x", "-a2", "B", "C", "-c1"])
        #expect(!a1.done)
        #expect(x.done)
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

    @Test func newLinesDeepInTheTreeAreSentToo() throws {
        let context = try FeedTests.store()
        try Feed.decode(Data(FeedTests.json.utf8)).apply(to: context)
        let project = try #require(try context.fetch(FetchDescriptor<Project>()).first)
        let stripe = try #require(project.sortedItems.first)
        let known = FocusItem(title: "Known", order: stripe.nextOrder)
        context.insert(known)
        known.parent = stripe
        known.remoteID = "a-known"
        let deep = known.add("Two levels down", in: context)

        let plan = Outbox.plan(context)
        #expect(plan.outgoing.subs["a-known"]?.map(\.title) == ["Two levels down"])
        #expect(plan.naming.contains { $0.item === deep })
    }
}

@Suite("Scrubbing a chart")
struct ScrubTests {
    @Test func theFingerPicksTheBarItIsOver() {
        let bars = [Bucket(date: at(2026, 11, 1, 0), amount: 100),
                    Bucket(date: at(2026, 11, 2, 0), amount: 200),
                    Bucket(date: at(2026, 11, 3, 0), amount: 300)]
        #expect(Ledger.pick(bars, at: at(2026, 11, 2, 0))?.amount == 200)
        #expect(Ledger.pick(bars, at: at(2026, 11, 2, 23))?.amount == 200)
        #expect(Ledger.pick(bars, at: at(2026, 11, 3, 1))?.amount == 300)
        // Off either end, it holds the nearest one.
        #expect(Ledger.pick(bars, at: at(2026, 10, 20))?.amount == 100)
        #expect(Ledger.pick(bars, at: at(2026, 12, 25))?.amount == 300)
        #expect(Ledger.pick([], at: at(2026, 11, 2)) == nil)
    }
}

@Suite("Notes")
@MainActor
struct NoteTests {
    /// Done is a mark on the note and nothing else: undoing it leaves the note as it was.
    @Test func doneIsEasilyUndone() {
        let note = Note(text: "Call the accountant", created: at(2026, 11, 1))
        note.pinned = true
        note.set(done: true, at: at(2026, 11, 10))
        #expect(note.done && note.finished == at(2026, 11, 10))
        #expect(note.edited == at(2026, 11, 1))
        note.set(done: false)
        #expect(!note.done && note.finished == nil)
        #expect(note.pinned && note.text == "Call the accountant" && note.edited == at(2026, 11, 1))
    }

    @Test func theDoneListShowsTheLatestFirst() {
        let a = Note(text: "A", created: at(2026, 11, 1))
        let b = Note(text: "B", created: at(2026, 11, 2))
        let c = Note(text: "C", created: at(2026, 11, 3))
        a.set(done: true, at: at(2026, 11, 12))
        c.set(done: true, at: at(2026, 11, 10))
        #expect(Note.doneOrder([a, b, c]).map(\.text) == ["A", "C"])
    }

    @Test func theFirstLineIsTheTitle() {
        #expect(NoteText.title("Focus pricing\nAnnual at £45") == "Focus pricing")
        #expect(NoteText.title("\n\n   Indented title  \nbody") == "Indented title")
        #expect(NoteText.title("") == "New note")
        #expect(NoteText.title("  \n ") == "New note")
    }

    @Test func theRestIsTheSnippet() {
        #expect(NoteText.snippet("Title\n\nFirst line.\n  Second line.") == "First line. Second line.")
        #expect(NoteText.snippet("Only a title") == "")
    }

    @Test func searchWantsEveryWord() {
        let text = "Launch film\nOpen on the menu bar going quiet."
        #expect(NoteText.matches(text, ""))
        #expect(NoteText.matches(text, "launch"))
        #expect(NoteText.matches(text, "quiet FILM"))
        #expect(!NoteText.matches(text, "launch pricing"))
    }

    @Test func wordsAreCounted() {
        #expect(NoteText.words("") == 0)
        #expect(NoteText.words("One two\nthree   four") == 4)
    }

    @Test func notesPerDayEndsToday() {
        let now = at(2026, 11, 17, 15)
        let dates = [at(2026, 11, 17, 9), at(2026, 11, 17, 10), at(2026, 11, 15), at(2026, 10, 1)]
        let days = NoteText.perDay(dates, days: 7, now: now, calendar: london)
        #expect(days.map(\.amount) == [0, 0, 0, 0, 1, 0, 2])
        #expect(days.last?.date == at(2026, 11, 17, 0))
    }

    @Test func aNoteKeepsItsDates() throws {
        let context = try FeedTests.store()
        let made = at(2026, 11, 3, 9)
        context.insert(Note(text: "Dated", created: made))
        try context.save()
        let note = try #require(try context.fetch(FetchDescriptor<Note>(sortBy: [SortDescriptor(\Note.edited, order: .reverse)])).first)
        #expect(note.created == made)
        #expect(note.edited == made)
        note.edited = at(2026, 11, 17, 15)
        try context.save()
        #expect(note.edited == at(2026, 11, 17, 15))
    }

    @Test func aProjectsNotesOutliveIt() throws {
        let context = try FeedTests.store()
        let project = Project(name: "Focus")
        context.insert(project)
        let note = Note(text: "Pricing", project: project)
        context.insert(note)
        try context.save()
        #expect(project.notes.count == 1)

        context.delete(project)
        try context.save()
        let left = try context.fetch(FetchDescriptor<Note>())
        #expect(left.count == 1)
        #expect(left.first?.project == nil)
    }

    @Test func myOwnListIsMadeOnceAndKeptFirst() throws {
        let context = try FeedTests.store()
        try Feed.decode(Data(FeedTests.json.utf8)).apply(to: context)
        let mine = Seed.personal(context)
        #expect(mine.isPersonal)
        #expect(Seed.personal(context) === mine)
        let projects = try context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\Project.order)]))
        #expect(projects.count == 2)
        #expect(projects.first === mine)

        // It stays on the phone: nothing of it is sent to the feed.
        let todo = FocusItem(title: "Ring the dentist")
        context.insert(todo)
        todo.project = mine
        let plan = Outbox.plan(context)
        #expect(plan.outgoing.lines.isEmpty)
        #expect(plan.naming.isEmpty)
    }
}

@Suite("Feed keeps the phone's edits", .serialized)
@MainActor
struct FeedRespectTests {
    static func fresh() throws -> ModelContext {
        UserDefaults.standard.removeObject(forKey: Tombstones.key)
        let context = try FeedTests.store()
        try Feed.decode(Data(FeedTests.json.utf8)).apply(to: context)
        return context
    }

    static func pull(_ context: ModelContext, _ json: String = FeedTests.json) throws {
        try Feed.decode(Data(json.utf8)).apply(to: context)
    }

    @Test func aRenameOnThePhoneSticks() throws {
        let context = try Self.fresh()
        let project = try #require(try context.fetch(FetchDescriptor<Project>()).first)
        let stripe = try #require(project.sortedItems.first)
        stripe.title = "Stripe, properly"
        project.name = "Focus app"
        try Self.pull(context)
        #expect(stripe.title == "Stripe, properly")
        #expect(project.name == "Focus app")

        // A change of wording on the feed's side still arrives.
        try Self.pull(context, FeedTests.json.replacingOccurrences(of: "Add Stripe", with: "Stripe live"))
        #expect(stripe.title == "Stripe live")
    }

    @Test func aLineMovedOnThePhoneIsNotDuplicated() throws {
        let context = try Self.fresh()
        let project = try #require(try context.fetch(FetchDescriptor<Project>()).first)
        let tutorial = try #require(project.sortedItems.last)
        #expect(tutorial.indent())
        try Self.pull(context)
        let all = try context.fetch(FetchDescriptor<FocusItem>())
        #expect(all.filter { $0.remoteID == "b" }.count == 1)
        #expect(tutorial.parent?.remoteID == "a")
    }

    @Test func aLineDeletedOnThePhoneStaysDeleted() throws {
        let context = try Self.fresh()
        let project = try #require(try context.fetch(FetchDescriptor<Project>()).first)
        let stripe = try #require(project.sortedItems.first)
        stripe.remove(from: context)
        try Self.pull(context)
        let ids = Set(try context.fetch(FetchDescriptor<FocusItem>()).map(\.remoteID))
        #expect(!ids.contains("a") && !ids.contains("a1") && !ids.contains("a2"))
        #expect(ids.contains("b"))
        UserDefaults.standard.removeObject(forKey: Tombstones.key)
    }

    @Test func aTickFromTheFeedRunsDownTheTree() throws {
        let context = try Self.fresh()
        try Self.pull(context, FeedTests.json.replacingOccurrences(of: #""title":"Add Stripe","#,
                                                                   with: #""title":"Add Stripe","done":true,"#))
        let project = try #require(try context.fetch(FetchDescriptor<Project>()).first)
        let stripe = try #require(project.sortedItems.first)
        #expect(stripe.done)
        let allDone = stripe.children.allSatisfy { $0.done }
        #expect(allDone)
    }
}

@Suite("Links")
@MainActor
struct LinkTests {
    /// Every link has its company's tile, and the tile is in the bundle.
    @Test func everyLinkHasItsLogo() {
        for link in QuickLink.all {
            #expect(UIImage(named: link.logo) != nil, "\(link.title) has no \(link.logo)")
        }
    }

    /// An app claims paths on its site, never the bare home address: sending
    /// Stripe or Claude there is what said "App not installed".
    @Test func appAddressesAreOnesAnAppClaims() {
        for link in QuickLink.all {
            for route in link.app where route.scheme == "https" {
                #expect(route.path().count > 1, "\(link.title) sends the app to its site's home page")
            }
        }
        #expect(QuickLink.all.first { $0.title == "Stripe" }?.app.first?.path() == "/dashboard")
        #expect(QuickLink.all.first { $0.title == "Claude" }?.app.first?.path() == "/new")
    }

    @Test func onlyOutsideCompaniesOfferAnApp() {
        let offered = QuickLink.all.filter(\.opensApp).map(\.title)
        #expect(offered == ["Google Workspace", "Stripe", "GitHub", "Claude", "Tesla"])
    }
}

@Suite("Work")
@MainActor
struct WorkTests {
    private func read(_ message: String, branches: [String] = ["claude/x"]) -> WorkEntry {
        WorkEntry.read(id: "abc", date: at(2026, 11, 17), repo: "Labern/Clean", branches: branches, message: message)
    }

    /// A version says what it did in plain words: added, fixed, styled.
    @Test func aCommitReadsAsWhatWasDone() {
        let added = read("""
        feat(paradox-hq): icon designer, built on the logo playground

        - Company > Settings > Create custom app icon: pick a mark and a ground,
          move, size and spin it with your fingers
        - Saved icons sit in the picker

        Co-Authored-By: Claude <noreply@anthropic.com>
        Claude-Session: https://claude.ai/code/session_x
        """)
        #expect(added.kind == .added)
        #expect(added.project == "paradox-hq")
        #expect(added.subject == "icon designer, built on the logo playground")
        #expect(added.line == "Added: icon designer, built on the logo playground")
        #expect(added.points == ["Company > Settings > Create custom app icon: pick a mark and a ground, move, size and spin it with your fingers",
                                 "Saved icons sit in the picker"])
        #expect(added.claude && !added.published)

        #expect(read("fix(focus): the Dock icon stayed").kind == .fixed)
        #expect(read("style: quieter banner").kind == .styled)
        #expect(read("style: quieter banner").project.isEmpty)
        #expect(read("docs(paradox-hq): how the feed works").kind == .wrote)
        #expect(read("ci(paradox-hq): photograph the Projects pane").kind == .tidied)
        #expect(!read("fix: x").claude)
    }

    @Test func plainSentencesAreReadToo() {
        let add = read("Add the weight chart")
        #expect(add.kind == .added && add.subject == "the weight chart")
        #expect(read("Polish the lock screen").kind == .styled)
        let release = read("Focus 0.0.4: stress-tested, oldest-survives single instance")
        #expect(release.project == "Focus")
        #expect(release.subject == "stress-tested, oldest-survives single instance")
        #expect(release.kind == .changed)
        #expect(read("Something else entirely").subject == "Something else entirely")
    }

    @Test func liveBranchesCountAsPublished() {
        #expect(read("feat: x", branches: ["master"]).published)
        #expect(read("feat: x", branches: ["gh-pages", "claude/x"]).published)
        #expect(!read("feat: x", branches: ["claude/x"]).published)
    }

    /// The same commit on two branches is one piece of work.
    @Test func aCommitOnTwoBranchesIsCountedOnce() {
        var first = read("feat: x", branches: ["claude/x"])
        var second = read("feat: x", branches: ["master"])
        first.id = "1"; second.id = "1"
        var other = read("fix: y")
        other.id = "2"
        other.date = at(2026, 11, 18)
        let merged = WorkLedger.merged([first, second, other])
        #expect(merged.map(\.id) == ["2", "1"])
        #expect(merged[1].branches == ["claude/x", "master"])
        #expect(merged[1].published)
    }

    @Test func workIsCountedPerDay() {
        var a = read("feat: a"), b = read("fix: b"), c = read("style: c")
        a.id = "a"; b.id = "b"; c.id = "c"
        a.date = at(2026, 11, 17, 9); b.date = at(2026, 11, 17, 18); c.date = at(2026, 11, 15, 12)
        let bars = WorkLedger.perDay([a, b, c], days: 4, now: at(2026, 11, 17, 20), calendar: london)
        #expect(bars.map(\.amount) == [0, 1, 0, 2])
        #expect(WorkLedger.on(at(2026, 11, 17), [a, b, c], calendar: london).map(\.id) == ["b", "a"])
        #expect(WorkLedger.byDay([a, b, c], calendar: london).map(\.entries.count) == [2, 1])
        #expect(WorkLog.tally([a, b, c]) == "1 added · 1 fixed · 1 styled")
    }

    private func session(_ id: String, _ hours: [String: Int], last: Date) -> ClaudeSession {
        ClaudeSession(id: id, started: last.addingTimeInterval(-3600), last: last, hours: hours)
    }

    /// Messages are kept per session per UTC hour, and a session reported twice counts once.
    @Test func claudeMessagesAreCountedOncePerSession() {
        let mac = session("aaaa", ["2026-11-17T10": 4, "2026-11-17T11": 6], last: at(2026, 11, 17, 11))
        let cloudCopy = session("aaaa", ["2026-11-17T10": 4], last: at(2026, 11, 17, 10))
        let other = session("bbbb", ["2026-11-17T20": 3], last: at(2026, 11, 17, 20))
        let unique = WorkLedger.unique([cloudCopy, mac, other])
        #expect(unique.map(\.id) == ["bbbb", "aaaa"])                    // latest used first
        #expect(unique.last?.messages == 10)                             // the fuller report wins
        let points = WorkLedger.messages([cloudCopy, mac, other])
        #expect(points.reduce(0) { $0 + $1.amount } == 13)
        // London is on UTC in November, so 20:00 UTC is 8pm there.
        let evening = WorkLedger.total(points, from: at(2026, 11, 17, 19), to: at(2026, 11, 17, 21), calendar: london)
        #expect(evening == 3)
        #expect(WorkLedger.total(points, from: at(2026, 11, 17, 0), to: at(2026, 11, 17, 23), calendar: london) == 13)
    }

    /// The older file, with days only, still reads.
    @Test func theOlderCountOfDaysStillReads() {
        let old = WorkLedger.sessions(from: [ClaudeDay(day: "2026-11-17", messages: 40, sessions: 3)])
        #expect(old.first?.messages == 40)
        let bars = WorkLedger.buckets(WorkLedger.messages(old), unit: .day, count: 3, now: at(2026, 11, 18, 9), calendar: london)
        #expect(bars.map(\.amount) == [0, 40, 0])
        #expect(WorkLedger.stamp(at(2026, 1, 5), london) == "2026-01-05")
    }

    @Test func theGraphIsCutByTheHourOrTheDay() {
        let points = [(date: at(2026, 11, 17, 9), amount: 1), (date: at(2026, 11, 17, 9), amount: 2), (date: at(2026, 11, 17, 11), amount: 5)]
        let hours = WorkLedger.buckets(points, unit: .hour, count: 4, now: at(2026, 11, 17, 12), calendar: london)
        #expect(hours.map(\.amount) == [3, 0, 5, 0])
        #expect(hours.last?.date == at(2026, 11, 17, 12))
        #expect(WorkSpan.day.graph.count == 24 && WorkSpan.week.graph.count == 7 && WorkSpan.month.graph.count == 30)
    }

    /// Today or the last 24 hours; this week or the last 7 days: the switch at the bottom left.
    @Test func aStretchIsCalendarOrRolling() {
        let now = at(2026, 11, 18, 15)                                   // a Wednesday
        func start(_ span: WorkSpan, _ rolling: Bool) -> Date {
            span.start(now: now, calendar: london, rolling: rolling, session: at(2026, 11, 18, 9))
        }
        #expect(start(.hour, false) == at(2026, 11, 18, 15))
        #expect(start(.session, false) == at(2026, 11, 18, 9))
        #expect(start(.day, false) == at(2026, 11, 18, 0))
        #expect(start(.day, true) == at(2026, 11, 17, 15))
        #expect(start(.week, false) == at(2026, 11, 16, 0))             // Monday
        #expect(start(.week, true) == at(2026, 11, 11, 15))
        #expect(start(.month, false) == at(2026, 11, 1, 0))
        #expect(WorkSpan.day.title(rolling: true) == "24 h" && WorkSpan.day.title(rolling: false) == "Today")
        #expect(WorkSpan.day.caption(rolling: true) == "last 24 hours")
    }

    /// A change made in a Claude conversation carries the way back to it.
    @Test func aChangeRemembersItsClaudeConversation() {
        let linked = read("""
        feat(paradox-hq): Work tab

        Co-Authored-By: Claude <noreply@anthropic.com>
        Claude-Session: https://claude.ai/code/session_01561EZoimxQTm7bYAzipx1m
        """)
        #expect(linked.session == "https://claude.ai/code/session_01561EZoimxQTm7bYAzipx1m")
        #expect(linked.sessionLink?.path() == "/code/session_01561EZoimxQTm7bYAzipx1m")
        #expect(linked.claude)
        let footer = read("fix: x\n\n🤖 Generated with Claude\n\nhttps://claude.ai/code/session_abc123)")
        #expect(footer.session == "https://claude.ai/code/session_abc123")
        #expect(read("fix: x\n\nCo-Authored-By: Claude Opus <noreply@anthropic.com>").session == nil)
        #expect(read("fix: see https://claude.ai/code/session_ for more").session == nil)
    }

    /// GitHub's push events no longer carry commits: only which branch moved.
    @Test func pushedBranchesComeFromTheEventFeed() throws {
        let json = """
        [{"type":"PushEvent","payload":{"ref":"refs/heads/claude/a","head":"1","before":"0"}},
         {"type":"DeleteEvent","payload":{"ref":"old"}},
         {"type":"PushEvent","payload":{"ref":"refs/heads/ci/paradox-hq"}},
         {"type":"PushEvent","payload":{"ref":"refs/heads/master"}},
         {"type":"PushEvent","payload":{"ref":"refs/heads/claude/a"}}]
        """
        let events = try GitHubWork.decoder().decode([GitHubWork.Event].self, from: Data(json.utf8))
        #expect(GitHubWork.branches(in: events) == ["claude/a", "master"])
    }

    /// Only the account's own repos that were pushed to lately are read, newest first.
    @Test func onlyReposWorkedOnLatelyAreRead() throws {
        let json = """
        [{"full_name":"Labern/Old","default_branch":"main","pushed_at":"2026-08-01T10:00:00Z","fork":false},
         {"full_name":"Labern/iOS","default_branch":"main","pushed_at":"2026-11-16T10:00:00Z","fork":false},
         {"full_name":"Labern/Fork","default_branch":"main","pushed_at":"2026-11-17T10:00:00Z","fork":true},
         {"full_name":"Labern/Clean","default_branch":"master","pushed_at":"2026-11-17T23:00:00Z"}]
        """
        let repos = try GitHubWork.decoder().decode([GitHubWork.Repo].self, from: Data(json.utf8))
        let active = GitHubWork.active(repos, since: at(2026, 10, 18), limit: 4)
        #expect(active.map(\.full_name) == ["Labern/Clean", "Labern/iOS"])
        #expect(active.first?.default_branch == "master")
        #expect(GitHubWork.active(repos, since: at(2026, 10, 18), limit: 1).count == 1)
    }

    /// A repo's own default branch is published, whatever it is called.
    @Test func theDefaultBranchIsPublished() throws {
        let json = """
        [{"sha":"1","parents":[],"commit":{"message":"feat: a","committer":{"name":"x","date":"2026-11-17T10:00:00Z"},"author":{"name":"Labern","date":"2026-11-17T10:00:00Z"}}}]
        """
        let commits = try GitHubWork.decoder().decode([GitHubWork.Commit].self, from: Data(json.utf8))
        #expect(GitHubWork.entries(commits, repo: "Labern/iOS", branch: "trunk", live: true).first?.published == true)
        #expect(GitHubWork.entries(commits, repo: "Labern/iOS", branch: "trunk").first?.published == false)
    }

    @Test func mergesAndTheBuildRobotAreNotWork() throws {
        let json = """
        [{"sha":"1","parents":[{"sha":"0"}],"commit":{"message":"feat: a","committer":{"name":"GitHub","date":"2026-11-17T10:00:00Z"},"author":{"name":"Claude","date":"2026-11-17T10:00:00Z"}}},
         {"sha":"2","parents":[{"sha":"0"},{"sha":"1"}],"commit":{"message":"Merge","committer":{"name":"x","date":"2026-11-17T11:00:00Z"},"author":{"name":"Labern","date":"2026-11-17T11:00:00Z"}}},
         {"sha":"3","parents":[],"commit":{"message":"CI abc","committer":{"name":"x","date":"2026-11-17T12:00:00Z"},"author":{"name":"paradox-hq-ci","date":"2026-11-17T12:00:00Z"}}}]
        """
        let commits = try GitHubWork.decoder().decode([GitHubWork.Commit].self, from: Data(json.utf8))
        let entries = GitHubWork.entries(commits, repo: "Labern/Clean", branch: "master")
        #expect(entries.map(\.id) == ["1"])
        #expect(entries.first?.published == true)
    }
}

@Suite("Colours")
@MainActor
struct ColourTests {
    /// Words on a coloured button are black or white, whichever reads.
    @Test func buttonWordsReadOnAnyColour() {
        for hue in Palette.hues + Palette.presets.flatMap({ [$0.accent, $0.second] }) {
            for ground in [hue, Palette.deep(hue)] {
                let ink = Palette.ink(on: ground)
                func luminance(_ hex: UInt32) -> Double {
                    Palette.luminance(Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF))
                }
                let (a, b) = (luminance(ink), luminance(ground))
                #expect((max(a, b) + 0.05) / (min(a, b) + 0.05) >= 4.5, "\(String(hue, radix: 16))")
            }
        }
    }

    /// In the light appearance a chosen colour is deepened until it reads on white.
    @Test func chosenColoursReadOnWhite() {
        for hue in Palette.hues {
            let deep = Palette.deep(hue)
            let l = Palette.luminance(Double((deep >> 16) & 0xFF), Double((deep >> 8) & 0xFF), Double(deep & 0xFF))
            #expect((1.05) / (l + 0.05) >= 3, "\(String(hue, radix: 16))")
        }
    }

    @Test func theDefaultIsFocusPurpleAndGreen() {
        #expect(Palette.presets.first?.accent == 0xA78BFA && Palette.presets.first?.second == 0x5FD7AF)
        #expect(Palette.hues.count == 9)
    }
}

@Suite("Profile photo")
@MainActor
struct ProfileTests {
    private let portrait = CGSize(width: 1000, height: 1400)

    @Test func aPhotoFillsItsCircleByItsShorterSide() {
        let plain = Framing()
        #expect(plain.drawn(portrait, side: 100) == CGSize(width: 100, height: 140))
        #expect(plain.offset(portrait, side: 100) == .zero)
        #expect(Framing(zoom: 2).drawn(CGSize(width: 1400, height: 1000), side: 100) == CGSize(width: 280, height: 200))
    }

    /// The point chosen sits in the middle of the circle.
    @Test func theChosenPointIsCentred() {
        let face = Framing(x: 0.5, y: 0.25, zoom: 2)
        #expect(face.drawn(portrait, side: 100) == CGSize(width: 200, height: 280))
        #expect(face.offset(portrait, side: 100) == CGSize(width: 0, height: 70))
    }

    /// The circle never shows past the edge of the photo, however it is pushed.
    @Test func thePhotoCannotBePushedOutOfItsCircle() {
        let corner = Framing(x: 0, y: 0, zoom: 1).clamped(to: portrait)
        #expect(corner.x == 0.5)
        #expect(abs(corner.y - 1000.0 / 2800.0) < 0.0001)
        let far = Framing(x: 2, y: 2, zoom: 2).clamped(to: portrait)
        #expect(abs(far.x - 0.75) < 0.0001)
        #expect(abs(far.y - (1 - 1000.0 / 5600.0)) < 0.0001)
        #expect(Framing(zoom: 0.2).clamped(to: portrait).zoom == 1)
        #expect(Framing(zoom: 99).clamped(to: portrait).zoom == Framing.closest)
        #expect(Framing(x: 0.3, y: 0.3, zoom: 3).clamped(to: .zero) == Framing())
    }

    @Test func draggingMovesThePhotoWithTheFinger() {
        let start = Framing(x: 0.5, y: 0.5, zoom: 2)
        // Drawn 200pt wide: 20pt to the right shows what was a tenth further left.
        let moved = start.dragged(by: CGSize(width: 20, height: -28), photo: portrait, side: 100)
        #expect(abs(moved.x - 0.4) < 0.0001)
        #expect(abs(moved.y - 0.6) < 0.0001)
        #expect(moved.zoom == 2)
        #expect(abs(start.zoomed(by: 1.5, photo: portrait).zoom - 3) < 0.0001)
    }

    /// The sliders run exactly as far as the photo can travel at the current zoom.
    @Test func thePhotoHasRoomToMoveOnceItIsZoomed() {
        let wide = Framing().room(in: portrait)
        #expect(wide.x == 0.5...0.5)                       // a tall photo at full width: no room sideways
        #expect(abs(wide.y.lowerBound - 1000.0 / 2800.0) < 0.0001)
        let close = Framing(zoom: 2).room(in: portrait)
        #expect(close.x == 0.25...0.75)
        #expect(abs(close.y.upperBound - (1 - 1000.0 / 5600.0)) < 0.0001)
        #expect(Framing().room(in: .zero).x == 0.5...0.5)
    }

    /// With no face found, an upright portrait starts on head and shoulders.
    @Test func aPortraitStartsOnHeadAndShoulders() {
        let start = Framing.standing(for: CGSize(width: 1122, height: 1402))
        #expect(start.x == 0.5 && start.y == 0.25 && start.zoom == 2.2)
        #expect(Framing.standing(for: CGSize(width: 1600, height: 1000)) == Framing())
    }

    /// A new photo is framed on the face, with room for the hair.
    @Test func aFaceIsFramedWithRoomAroundIt() {
        let photo = CGSize(width: 1122, height: 1402)
        let face = CGRect(x: 0.39, y: 0.17, width: 0.22, height: 0.2)
        let framing = Framing.around(face: face, in: photo)
        #expect(abs(framing.x - 0.5) < 0.0001)
        #expect(framing.y > 0.2 && framing.y < 0.3)
        #expect(framing.zoom > 2 && framing.zoom < 2.6)
        #expect(framing == framing.clamped(to: photo))
    }

    /// Any number of roles can be worn at once, listed in the order of the menu.
    @Test func rolesStack() {
        let order = Profile.roles
        var worn = ["Founder & Director"]
        worn = Profile.toggled(worn, "Writer", order: order)
        worn = Profile.toggled(worn, "Programmer", order: order)
        #expect(worn == ["Founder & Director", "Writer", "Programmer"])
        worn = Profile.toggled(worn, "Founder & Director", order: order)
        #expect(worn == ["Writer", "Programmer"])
        #expect(Profile.toggled(["Writer"], "Writer", order: order).isEmpty)
        #expect(Profile.toggled(["Composer"], "Writer", order: order + ["Composer"]) == ["Writer", "Composer"])
    }

    @Test func rolesAddedAreKeptWithoutRepeats() {
        #expect(Profile.merged(["Founder & Director", "Writer"], ["Composer", "writer", "Composer"])
            == ["Founder & Director", "Writer", "Composer"])
        #expect(Profile.roles.first == "Founder & Director")
        #expect(Profile.roles.contains("Writer") && Profile.roles.contains("Programmer") && Profile.roles.contains("Actor"))
    }
}

@Suite("Icon designer")
@MainActor
struct IconDesignerTests {
    private func shelf() -> (IconShelf, URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "icons-\(UUID().uuidString)")
        return (IconShelf(folder: folder), folder)
    }

    private func square(_ side: Int, alpha: CGFloat = 1) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).pngData { context in
            UIColor.red.withAlphaComponent(alpha).setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    /// The page and the outlines it draws both have to be in the app.
    @Test func theDesignerShipsInTheApp() throws {
        let page = try #require(DesignerBoard.page)
        let outlines = page.deletingLastPathComponent().appending(path: "logos.js")
        #expect(FileManager.default.fileExists(atPath: outlines.path(percentEncoded: false)))
        #expect(try String(contentsOf: page, encoding: .utf8).contains("window.D="))
    }

    @Test func aSavedIconIsKeptAndCanBeRemoved() throws {
        let (first, folder) = shelf()
        let icon = try first.add(png: square(64), title: "MARK", recipe: "{}")
        #expect(icon.id.count == 8)
        #expect(icon.asset == "AppIcon-Custom-\(icon.id)")
        #expect(first.picture(icon) != nil)

        let reopened = IconShelf(folder: folder)
        #expect(reopened.icons == [icon])

        reopened.wanted = icon.id
        reopened.remove(icon)
        #expect(reopened.icons.isEmpty)
        #expect(reopened.wanted.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: reopened.file(icon).path(percentEncoded: false)))
        reopened.wanted = ""
    }

    /// An app icon must be exactly 1024px with no alpha channel, and the right way up.
    @Test func picturesAreFlattenedForAnIcon() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let source = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300), format: format).pngData { context in
            UIColor.red.withAlphaComponent(0.5).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 150))      // top half
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 150, width: 300, height: 150))    // bottom half
        }
        let flat = try #require(IconShelf.flatten(source))
        let image = try #require(UIImage(data: flat)?.cgImage)
        #expect(image.width == 1024)
        #expect(image.height == 1024)
        #expect([CGImageAlphaInfo.none, .noneSkipLast, .noneSkipFirst].contains(image.alphaInfo))

        // Read one pixel near the top and one near the bottom.
        var bytes = [UInt8](repeating: 0, count: 1024 * 1024 * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        try bytes.withUnsafeMutableBytes { buffer in
            let bitmap = try #require(CGContext(data: buffer.baseAddress, width: 1024, height: 1024, bitsPerComponent: 8,
                                                bytesPerRow: 1024 * 4, space: space,
                                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            bitmap.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        }
        let top = 100 * 1024 * 4 + 512 * 4, bottom = 900 * 1024 * 4 + 512 * 4
        #expect(bytes[top] > 100 && bytes[top + 2] < 30, "the top should still be red")
        #expect(bytes[bottom + 2] > 200 && bytes[bottom] < 30, "the bottom should still be blue")
    }

    @Test func thePagesAnswerIsReadAsAPicture() {
        let png = square(8)
        #expect(IconShelf.decode(dataURL: "data:image/png;base64," + png.base64EncodedString()) == png)
        #expect(IconShelf.decode(dataURL: "data:image/jpeg;base64,AAAA") == nil)
        #expect(IconShelf.decode(dataURL: "nonsense") == nil)
    }

    /// Only icons the build was made with can be worn.
    @Test func knowsWhichIconsABuildCarries() {
        let info: [String: Any] = ["CFBundleIcons": ["CFBundleAlternateIcons": ["AppIcon-Kana": 1, "AppIcon-Custom-ab12cd34": 1]]]
        #expect(IconShelf.installed(in: info) == ["AppIcon-Kana", "AppIcon-Custom-ab12cd34"])
        #expect(IconShelf.installed(in: [:]).isEmpty)
        #expect(IconShelf.installed(in: nil).isEmpty)
    }

    /// The export folder holds exactly the icons on the phone.
    @Test func deletedIconsLeaveTheExportFolder() {
        let strays = IconShelf.strays(in: ["a.png", "b.png", "notes.txt"], keeping: ["a.png"])
        #expect(strays == ["b.png"])
    }
}

@Suite("Backups")
@MainActor
struct BackupTests {
    @Test func everythingSurvivesTheRoundTrip() throws {
        let context = try FeedTests.store()
        try Feed.decode(Data(FeedTests.json.utf8)).apply(to: context)
        let mine = Seed.personal(context)
        let launch = FocusItem(title: "Launch", order: 0)
        context.insert(launch)
        launch.project = mine
        let copy = launch.add("Copy", in: context)
        copy.add("Hero", in: context).set(done: true)
        copy.collapsed = true
        launch.due = at(2026, 12, 1)
        let focus = try #require(try context.fetch(FetchDescriptor<Project>()).first { $0.remoteID == "focus" })
        let pricing = Note(text: "Pricing\nRound numbers.", project: focus, created: at(2026, 11, 1))
        pricing.set(done: true, at: at(2026, 11, 5))
        context.insert(pricing)
        context.insert(Deadline(title: "VAT return", who: "HMRC", date: at(2026, 12, 7), everyMonths: 3))
        try context.save()

        let before = BackupFile.take(context, now: at(2026, 11, 17))
        let read = try BackupFile.read(try before.data())
        // The file keeps times to the millisecond and a fresh `Date()` is finer than
        // that, so what must hold is that reading a file and writing it again changes nothing.
        #expect(try read.data() == before.data())
        #expect(try BackupFile.read(try read.data()) == read)

        let other = try FeedTests.store()
        try read.restore(into: other)
        let after = BackupFile.take(other, now: at(2026, 11, 17))
        let wrote = String(decoding: try before.data(), as: UTF8.self)
        let got = String(decoding: try after.data(), as: UTF8.self)
        let differing = zip(wrote.split(separator: "\n"), got.split(separator: "\n")).filter { $0 != $1 }.prefix(4)
        #expect(differing.isEmpty, "\(differing.map { "\($0) → \($1)" })")
        #expect(after.summary == "2 projects, 7 lines, 1 note")
        let restoredMine = try #require(try other.fetch(FetchDescriptor<Project>()).first(where: \.isPersonal))
        #expect(restoredMine.sortedItems.first?.sortedChildren.first?.collapsed == true)
        let note = try other.fetch(FetchDescriptor<Note>()).first
        #expect(note?.project?.remoteID == "focus")
        #expect(note?.done == true && note?.finished == at(2026, 11, 5))
    }

    /// Backups made before notes could be marked done have no such field.
    @Test func anOlderBackupStillReads() throws {
        let old = """
        {"version":1,"made":"2026-11-17T12:00:00.000Z","projects":[],"deadlines":[],
         "notes":[{"text":"Pricing","created":"2026-11-01T12:00:00.000Z","edited":"2026-11-01T12:00:00.000Z","pinned":false}]}
        """
        let file = try BackupFile.read(Data(old.utf8))
        #expect(file.notes.first?.done == nil)
        let context = try FeedTests.store()
        try file.restore(into: context)
        let note = try #require(try context.fetch(FetchDescriptor<Note>()).first)
        #expect(!note.done && note.finished == nil && note.text == "Pricing")
    }

    @Test func aNewerFormatIsRefused() throws {
        var file = BackupFile(made: .now, projects: [], notes: [], deadlines: [])
        file.version = BackupFile.currentVersion + 1
        let data = try file.data()
        #expect(throws: BackupError.self) { try BackupFile.read(data) }
    }

    @Test func oneFileADayAndAMonthKept() {
        #expect(Backups.fileName(for: at(2026, 11, 17)).hasPrefix("PARADOX 2026-11-17"))
        let names = (1...35).map { String(format: "PARADOX 2026-10-%02d.json", min($0, 31)) + ($0 > 31 ? "x" : "") }
            .filter { $0.hasSuffix(".json") } + ["PARADOX 2026-10-01 before restore.json", "notes.txt"]
        let gone = Backups.surplus(names, keep: 30)
        #expect(gone == ["PARADOX 2026-10-01.json"])
    }
}

@Suite("Lock")
struct LockTests {
    @Test func asksOnlyAfterAWhileAway() {
        let now = at(2026, 11, 17, 12)
        #expect(AppLock.due(lastSeen: nil, now: now, after: 3600))
        #expect(!AppLock.due(lastSeen: now.addingTimeInterval(-600), now: now, after: 3600))
        #expect(AppLock.due(lastSeen: now.addingTimeInterval(-3700), now: now, after: 3600))
    }
}

@Suite("Ink")
struct InkTests {
    /// WCAG contrast between two colours in one appearance.
    static func contrast(_ a: Color, _ b: Color, _ style: UIUserInterfaceStyle) -> Double {
        let traits = UITraitCollection(userInterfaceStyle: style)
        func luminance(_ color: Color) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
            UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &alpha)
            func channel(_ c: CGFloat) -> Double {
                let c = Double(c)
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
        }
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// No white on white, no black on black: every pairing the app draws, in both appearances.
    @Test(arguments: [UIUserInterfaceStyle.dark, .light])
    func nothingDisappearsIntoItsBackground(_ style: UIUserInterfaceStyle) {
        let text: [(String, Color, Color, Double)] = [
            ("head on ground", Ink.head, Ink.ground, 7), ("head on surface", Ink.head, Ink.surface, 7),
            ("body on surface", Ink.body, Ink.surface, 7), ("body on surface2", Ink.body, Ink.surface2, 4.5),
            ("button ink on button", Ink.buttonInk, Ink.button, 7), ("button on ground", Ink.button, Ink.ground, 3),
            ("muted on surface", Ink.muted, Ink.surface, 3), ("muted on ground", Ink.muted, Ink.ground, 3),
            ("violet on surface", Ink.violet, Ink.surface, 3), ("ok on surface", Ink.ok, Ink.surface, 3),
            ("hazard on surface", Ink.hazard, Ink.surface, 3), ("amber on surface", Ink.amber, Ink.surface, 3),
            ("tick ink on head", Ink.onHead, Ink.head, 7), ("tick ink on violet", Ink.onHead, Ink.violet, 3),
        ]
        for (name, front, back, floor) in text {
            let ratio = Self.contrast(front, back, style)
            #expect(ratio >= floor, "\(name) is \(ratio) in \(style == .dark ? "dark" : "light")")
        }
    }

    @Test(arguments: [UIUserInterfaceStyle.dark, .light])
    func whiteMeansHeadingInk(_ style: UIUserInterfaceStyle) {
        #expect(Self.contrast(Ink.tint(0xFFFFFF), Ink.head, style) < 1.01)
    }
}
