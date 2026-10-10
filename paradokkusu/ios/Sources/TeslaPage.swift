import SwiftUI
import SwiftData
import Charts

struct TeslaPage: View {
    @Query(sort: \Deadline.date) private var deadlines: [Deadline]
    @Query(sort: \Charge.date, order: .reverse) private var charges: [Charge]
    @Query(filter: #Predicate<Todo> { $0.spineRaw == 1 && !$0.done }) private var open: [Todo]
    @State private var editing: Deadline?
    @State private var logging = false
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize

    static let tags = ["Fix", "Wash", "Get", "Book"]

    var body: some View {
        PageScaffold(spine: .tesla, eyebrow: "Model 3", title: "Tesla", subtitle: subtitle) {
            VStack(alignment: .leading, spacing: 22) {
                DeadlinesCard(deadlines: deadlines) { editing = $0 }
                ChargingCard(charges: charges)
                TodoCard(spine: .tesla)
            }
        } reach: {
            let pair = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
            pair {
                Button { logging = true } label: {
                    Label("Charge", systemImage: "bolt.fill")
                }
                .buttonStyle(QuietStyle())
                Button {
                    Launcher.open("tesla://", fallback: "https://www.tesla.com/teslaaccount", with: openURL)
                } label: {
                    Label("Tesla", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(QuietStyle())
            }
            ComposeBar(spine: .tesla, placeholder: "Add to Tesla", tags: Self.tags)
        }
        .sheet(item: $editing) { deadline in
            DeadlineEditor(deadline: deadline)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $logging) {
            ChargeLogger()
                .presentationDetents([.medium, .large])
        }
    }

    private var subtitle: String {
        var parts = [open.isEmpty ? "All done" : "\(open.count) to do"]
        let today = Calendar.current.startOfDay(for: .now)
        if let next = deadlines.first(where: { $0.date >= today }) ?? deadlines.first {
            parts.append(Days.phrase(next.title, next.date))
        }
        return parts.joined(separator: " · ")
    }
}

struct DeadlinesCard: View {
    let deadlines: [Deadline]
    let edit: (Deadline) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Coming up")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(deadlines.enumerated()), id: \.element.id) { index, deadline in
                        if index > 0 { Hairline(inset: 60) }
                        Button { edit(deadline) } label: {
                            DeadlineRow(deadline: deadline)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct DeadlineRow: View {
    let deadline: Deadline

    var body: some View {
        let days = Days.count(to: deadline.date)
        let span = Double(max(1, deadline.everyMonths * 30))
        let progress = 1 - min(1, max(0, Double(days) / span))
        let urgent = days < 30
        let accent: Color = urgent ? Spine.tesla.tint : Color.secondary

        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Ink.surface2, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: deadline.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(deadline.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(deadline.date, format: .dateTime.day().month(.abbreviated))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(Days.short(days))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct ChargingCard: View {
    let charges: [Charge]

    nonisolated struct Week: Identifiable {
        let start: Date
        let cost: Double
        var id: Date { start }
    }

    var body: some View {
        let cal = Calendar.current
        let month = charges.filter { cal.isDate($0.date, equalTo: .now, toGranularity: .month) }
        let spend = month.reduce(0.0) { $0 + $1.cost }
        let energy = month.reduce(0.0) { $0 + $1.kWh }
        let weeks = Self.weekly(charges)

        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Charging", trailing: Date.now.formatted(.dateTime.month(.wide)))
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(spend, format: .currency(code: "GBP"))
                            .font(.title2.bold())
                            .monospacedDigit()
                        Spacer(minLength: 4)
                        Text("\(Int(energy)) kWh")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Chart(weeks) { week in
                        BarMark(x: .value("Week", week.start, unit: .weekOfYear),
                                y: .value("Cost", week.cost),
                                width: .ratio(0.6))
                            .foregroundStyle(Spine.tesla.fill.gradient)
                            .cornerRadius(3)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 60)
                    .accessibilityLabel("Weekly charging cost, last eight weeks")
                    if let last = charges.first {
                        Text("Last: \(last.place), \(last.date.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    static func weekly(_ charges: [Charge]) -> [Week] {
        let cal = Calendar.current
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return (0..<8).reversed().compactMap { i -> Week? in
            guard let start = cal.date(byAdding: .weekOfYear, value: -i, to: thisWeek),
                  let end = cal.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let cost = charges.filter { $0.date >= start && $0.date < end }.reduce(0.0) { $0 + $1.cost }
            return Week(start: start, cost: cost)
        }
    }
}

struct ChargeLogger: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var kWh = 40.0
    @State private var rate = 7.5
    @State private var place = "Home"

    private let places = ["Home", "Supercharger", "Destination"]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Where", selection: $place) {
                    ForEach(places, id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)
                Stepper(value: $kWh, in: 1...100, step: 1) {
                    LabeledContent("Energy", value: "\(Int(kWh)) kWh")
                }
                Stepper(value: $rate, in: 1...99, step: 0.5) {
                    LabeledContent("Rate", value: String(format: "%.1fp per kWh", rate))
                }
                LabeledContent("Cost") {
                    Text(kWh * rate / 100, format: .currency(code: "GBP"))
                }
            }
            .navigationTitle("Log charge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        context.insert(Charge(date: .now, kWh: kWh, pencePerKWh: rate, place: place))
                        dismiss()
                    }
                }
            }
            .onChange(of: place) { _, newPlace in
                switch newPlace {
                case "Supercharger": rate = 52
                case "Destination": rate = 30
                default: rate = 7.5
                }
            }
        }
    }
}

struct DeadlineEditor: View {
    @Bindable var deadline: Deadline
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $deadline.title)
                DatePicker("Due", selection: $deadline.date, displayedComponents: .date)
                Stepper("Every \(deadline.everyMonths) months", value: $deadline.everyMonths, in: 1...60)
                Section {
                    Button("Done for this time") {
                        let cal = Calendar.current
                        deadline.date = cal.date(byAdding: .month, value: deadline.everyMonths, to: deadline.date) ?? deadline.date
                        dismiss()
                    }
                } footer: {
                    Text("Moves the date on by \(deadline.everyMonths) months.")
                }
            }
            .navigationTitle(deadline.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
