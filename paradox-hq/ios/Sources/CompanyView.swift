import SwiftUI
import SwiftData

/// The admin side: filing deadlines counting down, what the app is connected to,
/// and the lock.
struct CompanyView: View {
    @Environment(MoneyStore.self) private var money
    @Environment(FeedSync.self) private var feed
    @Environment(SiteMonitor.self) private var site
    @Environment(AppLock.self) private var lock
    @Query(sort: \Deadline.date) private var deadlines: [Deadline]
    @State private var draft: DeadlineDraft? = nil
    @State private var sheet: Connection? = nil
    @State private var locking = AppLock.enabled
    @AppStorage("notify-payment") private var notifyPayments = true
    @AppStorage("notify-payout") private var notifyPayouts = true
    @AppStorage("notify-dispute") private var notifyDisputes = true
    @AppStorage("notify-deadline") private var notifyDeadlines = true

    enum Connection: String, Identifiable {
        case stripe, claude, site
        var id: String { rawValue }
    }

    static let usual: [(title: String, who: String, every: Int)] = [
        ("Confirmation statement", "Companies House", 12),
        ("Annual accounts", "Companies House", 12),
        ("Corporation tax", "HMRC", 12),
        ("VAT return", "HMRC", 3),
        ("Apple Developer renewal", "Apple", 12),
        ("Domain renewal", "", 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Heading(title: "Company")
                    deadlineSection
                    connectionSection
                    notifySection
                    lockSection
                    Text("PARADOX \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                        .font(.footnote)
                        .foregroundStyle(Ink.idle)
                        .frame(maxWidth: .infinity)
                }
                .page()
            }
            .scrollIndicators(.hidden)
            .background(Ink.ground)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $draft) { DeadlineEditor(draft: $0) }
            .sheet(item: $sheet) { which in
                switch which {
                case .stripe: ConnectStripe()
                case .claude: FeedSettings()
                case .site: SiteSettings()
                }
            }
        }
    }

    private var deadlineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Deadlines")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    if deadlines.isEmpty {
                        Text("Add each filing date once. It counts down here and shows on Today in its last 30 days.")
                            .font(.subheadline)
                            .foregroundStyle(Ink.muted)
                            .padding(14)
                        Hairline()
                    }
                    ForEach(deadlines) { deadline in
                        Button {
                            draft = DeadlineDraft(deadline: deadline, isNew: false)
                        } label: {
                            DeadlineRow(deadline: deadline)
                        }
                        .buttonStyle(.plain)
                        Hairline(inset: 58)
                    }
                    Menu {
                        ForEach(Self.usual, id: \.title) { usual in
                            Button(usual.title) {
                                draft = DeadlineDraft(deadline: Deadline(title: usual.title, who: usual.who, everyMonths: usual.every),
                                                      isNew: true)
                            }
                        }
                        Divider()
                        Button("Something else") {
                            draft = DeadlineDraft(deadline: Deadline(title: ""), isNew: true)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 32, height: 32)
                            Text("Add a deadline")
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                }
            }
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Connected to")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    Button { sheet = .stripe } label: {
                        InfoRow(symbol: "creditcard", title: "Stripe", detail: "Sales, payouts, disputes") {
                            Pill(text: money.live ? "Connected" : "Example", color: money.live ? Ink.ok : Ink.amber)
                        }
                    }
                    .buttonStyle(.plain)
                    Hairline(inset: 58)
                    Button { sheet = .claude } label: {
                        InfoRow(symbol: "sparkles", title: "Claude", detail: feedDetail) {
                            Pill(text: feed.isSet ? (feed.failed ? "Failed" : "Connected") : "Not set",
                                 color: feed.isSet ? (feed.failed ? Ink.hazard : Ink.ok) : Ink.muted)
                        }
                    }
                    .buttonStyle(.plain)
                    Hairline(inset: 58)
                    Button { sheet = .site } label: {
                        InfoRow(symbol: "globe", title: "Website", detail: site.host) {
                            sitePill
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var feedDetail: String {
        if !feed.isSet { return "Projects and lines Claude adds" }
        return feed.status.isEmpty ? "Projects and lines Claude adds" : feed.status
    }

    @ViewBuilder
    private var sitePill: some View {
        switch site.state {
        case .unknown: Pill(text: "Not set")
        case .checking: Pill(text: "Checking")
        case .up(let ms): Pill(text: "Up · \(ms) ms", color: Ink.ok)
        case .down: Pill(text: "Down", color: Ink.hazard)
        }
    }

    private var notifySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Notify me")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    notify("Payments", $notifyPayments)
                    Hairline()
                    notify("Payouts", $notifyPayouts)
                    Hairline()
                    notify("Disputes", $notifyDisputes)
                    Hairline()
                    notify("Deadlines", $notifyDeadlines)
                }
            }
            Text("Money is checked in the background, so it can arrive a while after the payment. Deadlines come at 09:00, a week before and the day before.")
                .font(.footnote)
                .foregroundStyle(Ink.muted)
                .padding(.horizontal, 4)
        }
    }

    private func notify(_ title: String, _ value: Binding<Bool>) -> some View {
        Toggle(title, isOn: value)
            .tint(Ink.ok)
            .foregroundStyle(Ink.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .onChange(of: value.wrappedValue) { _, on in
                if on { Task { await Notifier.ask() } }
            }
    }

    private var lockSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Lock")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    Toggle(isOn: $locking) {
                        HStack(spacing: 12) {
                            Image(systemName: lock.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Ink.muted)
                                .frame(width: 32, height: 32)
                                .background(Ink.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text("Ask for Face ID")
                                .foregroundStyle(Ink.body)
                        }
                    }
                    .tint(Ink.ok)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .onChange(of: locking) { _, new in AppLock.enabled = new }
                    Hairline(inset: 58)
                    Button {
                        lock.lock()
                    } label: {
                        InfoRow(symbol: "lock", title: "Lock now") { EmptyView() }
                    }
                    .buttonStyle(.plain)
                    .disabled(!locking)
                }
            }
        }
    }
}

struct DeadlineDraft: Identifiable {
    let id = UUID()
    let deadline: Deadline
    let isNew: Bool
}

struct DeadlineRow: View {
    let deadline: Deadline

    var body: some View {
        let days = Days.count(to: deadline.date)
        let color: Color = days < 0 ? Ink.hazard : days <= 30 ? Ink.amber : Ink.muted
        InfoRow(symbol: "calendar", symbolColor: color, title: deadline.title, detail: deadline.who) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(deadline.date, format: .dateTime.day().month(.abbreviated).year(.twoDigits))
                    .monospacedDigit()
                    .foregroundStyle(Ink.body)
                Text(days < 0 ? "\(-days) days late" : days == 0 ? "Today" : "\(days) days")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
        }
    }
}

struct DeadlineEditor: View {
    let draft: DeadlineDraft
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var who = ""
    @State private var date = Date.now
    @State private var every = 12

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What's due", text: $title)
                    TextField("Who it goes to", text: $who)
                    DatePicker("Due", selection: $date, displayedComponents: .date)
                    Picker("Repeats", selection: $every) {
                        Text("Never").tag(0)
                        Text("Every month").tag(1)
                        Text("Every quarter").tag(3)
                        Text("Every year").tag(12)
                    }
                }
                if !draft.isNew {
                    Section {
                        Button(every > 0 ? "Done, move to the next one" : "Done") {
                            save()
                            if !draft.deadline.markDone() { context.delete(draft.deadline) }
                            dismiss()
                        }
                        Button("Delete", role: .destructive) {
                            context.delete(draft.deadline)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(draft.isNew ? "New deadline" : "Deadline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        if draft.isNew { context.insert(draft.deadline) }
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                title = draft.deadline.title
                who = draft.deadline.who
                date = draft.deadline.date
                every = draft.deadline.everyMonths
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        draft.deadline.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.deadline.who = who.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.deadline.date = date
        draft.deadline.everyMonths = every
    }
}

/// Where the Claude feed lives. Any Claude session can add projects and lines
/// to that file; the app pulls them in on every open.
struct FeedSettings: View {
    @Environment(FeedSync.self) private var feed
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var token = ""
    @State private var hasToken = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…/feed.json", text: $address, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Address of the feed")
                } footer: {
                    Text("One JSON file of projects and their lines. Claude adds to it; the app pulls it in. It only ever adds and ticks: it never deletes a line or unticks one.")
                }
                Section {
                    SecureField(hasToken ? "Saved. Type to replace." : "Only for a private repo", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if hasToken {
                        Button("Remove the token", role: .destructive) {
                            Keychain.delete(FeedSync.tokenName)
                            hasToken = false
                        }
                    }
                } header: {
                    Text("Token")
                } footer: {
                    Text("Kept in the Keychain on this phone.")
                }
                Section {
                    Button {
                        save()
                        Task { await feed.pull(into: context) }
                    } label: {
                        HStack {
                            Text("Pull now")
                            Spacer()
                            if feed.busy { ProgressView() }
                        }
                    }
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || feed.busy)
                    if !feed.status.isEmpty {
                        Text(feed.status)
                            .font(.footnote)
                            .foregroundStyle(feed.failed ? Ink.hazard : Ink.muted)
                    }
                }
            }
            .navigationTitle("Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                address = feed.address
                hasToken = Keychain.get(FeedSync.tokenName) != nil
            }
        }
    }

    private func save() {
        feed.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            hasToken = Keychain.set(trimmed, for: FeedSync.tokenName)
            token = ""
        }
    }
}

struct SiteSettings: View {
    @Environment(SiteMonitor.self) private var site
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Address to watch")
                } footer: {
                    Text("Checked each time the app opens. If it stops answering, it shows on Today.")
                }
                Section {
                    Button("Check now") {
                        site.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task { await site.check() }
                    }
                    switch site.state {
                    case .unknown: Text("Not checked yet").foregroundStyle(Ink.muted)
                    case .checking: Text("Checking").foregroundStyle(Ink.muted)
                    case .up(let ms): Text("Up. Answered in \(ms) ms.").foregroundStyle(Ink.ok)
                    case .down(let why): Text("Down. \(why)").foregroundStyle(Ink.hazard)
                    }
                }
            }
            .navigationTitle("Website")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        site.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                }
            }
            .onAppear { address = site.address }
        }
        .presentationDetents([.medium, .large])
    }
}
