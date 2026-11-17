import SwiftUI
import Charts

/// Stripe in full: revenue over any period, subscribers, payouts, every payment.
struct MoneyView: View {
    @Environment(MoneyStore.self) private var money
    @State private var period: Period = .month
    @State private var connecting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Heading(title: "Money", detail: updatedLine)
                    if !money.live {
                        ExampleBanner { connecting = true }
                    }
                    if let problem = money.problem {
                        Text(problem)
                            .font(.footnote)
                            .foregroundStyle(Ink.hazard)
                    }
                    Picker("Period", selection: $period) {
                        ForEach(Period.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    RevenueCard(period: period)
                    SubscriberTiles()
                    PayoutsCard()
                    CustomersCard()
                    PaymentsCard()
                    ChargeCard()
                }
                .page()
            }
            .scrollIndicators(.hidden)
            .background(Ink.ground)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await money.refresh() }
            .navigationDestination(for: Payment.self) { PaymentDetail(payment: $0) }
            .navigationDestination(for: Customer.self) { CustomerDetail(customer: $0) }
            .sheet(isPresented: $connecting) { ConnectStripe() }
        }
    }

    private var updatedLine: String {
        guard money.live, let updated = money.updated else { return "" }
        return "Updated \(updated.formatted(date: .omitted, time: .shortened))"
    }
}

struct RevenueCard: View {
    @Environment(MoneyStore.self) private var money
    let period: Period
    /// Where the finger is on the chart, while it's down.
    @State private var touched: Date? = nil

    var body: some View {
        let calendar = Calendar.current
        let now = Date.now
        let current = period.current(now: now, calendar: calendar)
        let previous = period.previous(now: now, calendar: calendar)
        // Sums run up to, not including, the end; a second past now takes in a payment made this instant.
        let window = DateInterval(start: current.start, end: now.addingTimeInterval(1))
        let total = Ledger.total(money.payments, in: window)
        let before = Ledger.total(money.payments, in: previous)
        let fees = Ledger.fees(money.payments, in: window)
        let refunds = Ledger.refunds(money.payments, in: window)
        let sales = Ledger.sales(money.payments, in: window)
        let bars = Ledger.buckets(money.payments, from: current.start, to: window.end,
                                  by: period.bucket, calendar: calendar)
        let latest = bars.last?.date
        // Dragging along the bars reads each one off, with a tick of the haptic
        // every time the finger crosses onto the next.
        let picked = touched.flatMap { Ledger.pick(bars, at: $0) }
        let lit = picked?.date ?? latest

        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(picked.map { Self.label($0.date, period) } ?? "Revenue this \(period.title.lowercased())")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(picked == nil ? Ink.muted : Color.white)
                        Text(money.money(picked?.amount ?? total))
                            .font(.system(size: 36, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        ChangePill(change: Ledger.change(from: before, to: total))
                        Text("on \(period.before)")
                            .font(.caption2)
                            .foregroundStyle(Ink.muted)
                    }
                    .opacity(picked == nil ? 1 : 0)
                }
                Chart(bars) { bar in
                    BarMark(x: .value("Date", bar.date, unit: period.bucket),
                            y: .value("Revenue", Double(bar.amount) / 100))
                        .cornerRadius(3)
                        .foregroundStyle(bar.date == lit ? Color.white : Ink.violet.opacity(0.6))
                }
                .chartXSelection(value: $touched)
                .sensoryFeedback(.selection, trigger: picked?.date)
                .onChange(of: period) { _, _ in touched = nil }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel()
                            .foregroundStyle(Ink.muted)
                    }
                }
                .frame(height: 130)
                .accessibilityLabel("Revenue this \(period.title.lowercased())")

                HStack(spacing: 0) {
                    stat("Sales", "\(sales)")
                    stat("Average", sales > 0 ? money.money(total / sales) : "–")
                    stat("Fees", fees > 0 ? money.money(fees) : "–")
                    stat("Refunds", refunds > 0 ? money.money(refunds) : "–")
                }
            }
        }
    }

    /// What a bar stands for, in words: a day, a week, or a month.
    static func label(_ date: Date, _ period: Period) -> String {
        switch period.bucket {
        case .weekOfYear: "Week of \(date.formatted(.dateTime.day().month(.abbreviated)))"
        case .month: date.formatted(.dateTime.month(.wide).year())
        default: date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Ink.muted)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Ink.body)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Focus Pro is mostly subscriptions, so the monthly run-rate gets its own tiles.
struct SubscriberTiles: View {
    @Environment(MoneyStore.self) private var money

    var body: some View {
        if let subscribers = money.subscribers, let mrr = money.mrr {
            HStack(alignment: .top, spacing: 12) {
                Card {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Subscribers")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Ink.muted)
                        Text("\(subscribers)")
                            .font(.title2.bold())
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Monthly recurring")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Ink.muted)
                        Text(money.money(mrr))
                            .font(.title2.bold())
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
        }
    }
}

struct PayoutsCard: View {
    @Environment(MoneyStore.self) private var money

    var body: some View {
        let payouts = Array(money.payouts.prefix(3))
        if !payouts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Payouts", trailing: "\(money.money(money.pending)) pending")
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(payouts.enumerated()), id: \.element.id) { index, payout in
                            if index > 0 { Hairline(inset: 58) }
                            InfoRow(symbol: "arrow.up.right",
                                    symbolColor: payout.isUpcoming ? .white : Ink.muted,
                                    title: payout.label,
                                    detail: payout.arrives.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) {
                                Text(money.money(payout.amount, pennies: true))
                                    .monospacedDigit()
                                    .foregroundStyle(Ink.body)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct PaymentsCard: View {
    @Environment(MoneyStore.self) private var money

    var body: some View {
        let payments = Array(money.payments.prefix(40))
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Payments")
            Card(padding: 0) {
                if payments.isEmpty {
                    Text("No payments yet.")
                        .foregroundStyle(Ink.muted)
                        .padding(14)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(payments.enumerated()), id: \.element.id) { index, payment in
                            if index > 0 { Hairline(inset: 58) }
                            NavigationLink(value: payment) {
                                PaymentRow(payment: payment)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

extension PaymentStatus {
    var color: Color {
        switch self {
        case .succeeded: Ink.ok
        case .pending: Ink.amber
        case .failed, .disputed: Ink.hazard
        case .refunded: Ink.muted
        }
    }

    var symbol: String {
        switch self {
        case .succeeded: "arrow.down.left"
        case .pending: "clock"
        case .failed: "xmark"
        case .disputed: "exclamationmark.triangle"
        case .refunded: "arrow.uturn.backward"
        }
    }
}

struct PaymentRow: View {
    @Environment(MoneyStore.self) private var money
    let payment: Payment

    var body: some View {
        InfoRow(symbol: payment.status.symbol,
                symbolColor: payment.status.color,
                title: payment.who,
                detail: detail) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.string(payment.amount, currency: payment.currency, pennies: true))
                    .monospacedDigit()
                    .foregroundStyle(payment.status == .failed ? Ink.muted : Ink.body)
                    .strikethrough(payment.status == .refunded)
                if payment.status != .succeeded {
                    Text(payment.status.label)
                        .font(.caption)
                        .foregroundStyle(payment.status.color)
                }
            }
        }
    }

    private var detail: String {
        let when = payment.date.formatted(.relative(presentation: .named))
        return payment.what.isEmpty ? when : "\(payment.what) · \(when)"
    }
}

struct PaymentDetail: View {
    @Environment(\.openURL) private var openURL
    let payment: Payment

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    Image(systemName: payment.status.symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(payment.status.color)
                        .frame(width: 56, height: 56)
                        .background(Ink.surface, in: Circle())
                    Text(Money.string(payment.amount, currency: payment.currency, pennies: true))
                        .font(.system(size: 40, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Pill(text: payment.status.label, color: payment.status.color)
                    Text("\(payment.who) · \(payment.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(Ink.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

                Card(padding: 0) {
                    VStack(spacing: 0) {
                        if !payment.what.isEmpty {
                            line("For", payment.what)
                            Hairline()
                        }
                        if !payment.method.isEmpty {
                            line("Paid with", payment.method)
                            Hairline()
                        }
                        if payment.refunded > 0 {
                            line("Refunded", Money.string(payment.refunded, currency: payment.currency, pennies: true))
                            Hairline()
                        }
                        line("Stripe fee", payment.fee.map { Money.string($0, currency: payment.currency, pennies: true) } ?? "–")
                        Hairline()
                        line("You keep", payment.net.map { Money.string($0, currency: payment.currency, pennies: true) } ?? "–",
                             strong: true)
                    }
                }

                if !payment.id.hasPrefix("example_") {
                    Button {
                        if let url = URL(string: "https://dashboard.stripe.com/payments/\(payment.id)") {
                            openURL(url)
                        }
                    } label: {
                        Label("Open in Stripe", systemImage: "arrow.up.forward")
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }
            .page()
        }
        .background(Ink.ground)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func line(_ title: String, _ value: String, strong: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(Ink.muted)
            Spacer(minLength: 12)
            Text(value)
                .monospacedDigit()
                .fontWeight(strong ? .semibold : .regular)
                .foregroundStyle(strong ? Color.white : Ink.body)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// Where the Stripe key goes in. It is checked against Stripe, then kept in
/// the Keychain on this phone. It never leaves the device except to Stripe.
struct ConnectStripe: View {
    @Environment(MoneyStore.self) private var money
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var key = ""
    @State private var problem: String? = nil
    @State private var working = false

    private static let reads = ["Charges", "Balance", "Balance transaction sources", "Payouts", "Disputes", "Subscriptions"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if money.live {
                        Card {
                            HStack(spacing: 10) {
                                Circle().fill(Ink.ok).frame(width: 10, height: 10)
                                Text("Connected")
                                    .foregroundStyle(Ink.body)
                                Spacer()
                            }
                        }
                        Button("Disconnect", role: .destructive) {
                            money.disconnect()
                            dismiss()
                        }
                        .buttonStyle(QuietButtonStyle())
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("In Stripe, make a restricted key with Read on each of these and nothing else:")
                                .foregroundStyle(Ink.body)
                            ForEach(Self.reads, id: \.self) { name in
                                Label(name, systemImage: "checkmark")
                                    .font(.subheadline)
                                    .foregroundStyle(Ink.muted)
                            }
                        }
                        Button {
                            if let url = URL(string: "https://dashboard.stripe.com/apikeys/create") { openURL(url) }
                        } label: {
                            Label("Make the key in Stripe", systemImage: "arrow.up.forward")
                        }
                        .buttonStyle(QuietButtonStyle())

                        SecureField("rk_live_…", text: $key)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                            .padding(.horizontal, 14)
                            .frame(minHeight: 50)
                            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        if let problem {
                            Text(problem)
                                .font(.footnote)
                                .foregroundStyle(Ink.hazard)
                        }
                        Button {
                            Task { await connect() }
                        } label: {
                            if working { ProgressView().tint(.black) } else { Text("Connect") }
                        }
                        .buttonStyle(WhiteButtonStyle())
                        .disabled(working || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Text("A read-only key can't move money or change anything. It's stored in the Keychain on this phone.")
                            .font(.footnote)
                            .foregroundStyle(Ink.muted)
                    }
                }
                .page()
            }
            .background(Ink.ground)
            .navigationTitle("Stripe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func connect() async {
        working = true
        problem = await money.connect(key)
        working = false
        if problem == nil {
            // Connected: this is the moment payment notifications start to mean something.
            await Notifier.ask()
            dismiss()
        }
    }
}

/// Who pays the most, from every payment on record.
struct CustomersCard: View {
    @Environment(MoneyStore.self) private var money

    var body: some View {
        let customers = Ledger.customers(money.payments)
        if !customers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Customers", trailing: "\(customers.count)")
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(customers.prefix(5).enumerated()), id: \.element.id) { index, customer in
                            if index > 0 { Hairline(inset: 58) }
                            NavigationLink(value: customer) {
                                CustomerRow(customer: customer)
                            }
                            .buttonStyle(.plain)
                        }
                        if customers.count > 5 {
                            Hairline(inset: 58)
                            NavigationLink {
                                CustomerList(customers: customers)
                            } label: {
                                InfoRow(symbol: "person.2", title: "All customers") {
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(Ink.idle)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

struct CustomerRow: View {
    @Environment(MoneyStore.self) private var money
    let customer: Customer

    var body: some View {
        InfoRow(symbol: "person", title: customer.name,
                detail: customer.count == 1 ? "1 payment" : "\(customer.count) payments") {
            Text(money.money(customer.total))
                .monospacedDigit()
                .foregroundStyle(Ink.body)
        }
    }
}

struct CustomerList: View {
    let customers: [Customer]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Heading(title: "Customers", detail: "\(customers.count)")
                Card(padding: 0) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(customers.enumerated()), id: \.element.id) { index, customer in
                            if index > 0 { Hairline(inset: 58) }
                            NavigationLink(value: customer) {
                                CustomerRow(customer: customer)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .page()
        }
        .background(Ink.ground)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CustomerDetail: View {
    @Environment(MoneyStore.self) private var money
    let customer: Customer

    var body: some View {
        let payments = money.payments.filter { $0.who == customer.name }
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Heading(title: customer.name)
                HStack(alignment: .top, spacing: 12) {
                    Card {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Paid in all")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Ink.muted)
                            Text(money.money(customer.total))
                                .font(.title2.bold())
                                .monospacedDigit()
                                .foregroundStyle(.white)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last paid")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Ink.muted)
                            Text(customer.last, format: .dateTime.day().month(.abbreviated).year(.twoDigits))
                                .font(.title2.bold())
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Payments", trailing: "\(payments.count)")
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(payments.enumerated()), id: \.element.id) { index, payment in
                                if index > 0 { Hairline(inset: 58) }
                                NavigationLink(value: payment) {
                                    PaymentRow(payment: payment)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .page()
        }
        .background(Ink.ground)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Charging someone by hand happens in Stripe itself: the key here is read-only
/// on purpose, so these open Stripe at the right page.
struct ChargeCard: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Charge someone")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    row("doc.text", "New invoice", "https://dashboard.stripe.com/invoices/create")
                    Hairline(inset: 58)
                    row("link", "New payment link", "https://dashboard.stripe.com/payment-links/create")
                }
            }
        }
    }

    private func row(_ symbol: String, _ title: String, _ address: String) -> some View {
        Button {
            if let url = URL(string: address) { openURL(url) }
        } label: {
            InfoRow(symbol: symbol, title: title, detail: "Opens Stripe") {
                Image(systemName: "arrow.up.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Ink.idle)
            }
        }
        .buttonStyle(.plain)
    }
}
