import SwiftUI
import SwiftData
import EventKit
import EventKitUI

/// Reads every calendar on the phone through EventKit. Access is asked for
/// only when the Show calendar button is tapped, never at launch.
@Observable final class CalendarStore {
    enum Access { case unknown, granted, denied }

    let store = EKEventStore()
    var access: Access = .unknown
    var events: [EKEvent] = []
    var busyDays: Set<Date> = []
    var today: [EKEvent] = []

    init() { refreshStatus() }

    func refreshStatus() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted
        case .notDetermined: access = .unknown
        default: access = .denied
        }
    }

    func request(then day: Date) {
        store.requestFullAccessToEvents { granted, _ in
            Task { @MainActor in
                self.access = granted ? .granted : .denied
                self.load(day: day)
            }
        }
    }

    func load(day: Date) {
        guard access == .granted else {
            events = []
            busyDays = []
            today = []
            return
        }
        let cal = Calendar.current
        events = fetch(on: day)
        today = fetch(on: .now)
        let weekStart = cal.dateInterval(of: .weekOfYear, for: day)?.start ?? cal.startOfDay(for: day)
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let predicate = store.predicateForEvents(withStart: weekStart, end: weekEnd, calendars: nil)
        busyDays = Set(store.events(matching: predicate).map { cal.startOfDay(for: $0.startDate) })
    }

    private func fetch(on day: Date) -> [EKEvent] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    var nextToday: EKEvent? {
        today.first { !$0.isAllDay && $0.startDate > .now }
    }
}

struct DiaryPage: View {
    @Environment(CalendarStore.self) private var calendar
    @Environment(\.openURL) private var openURL
    @Query(sort: \Entry.day, order: .reverse) private var entries: [Entry]
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var creating = false

    var body: some View {
        let cal = Calendar.current
        let entry = entries.first { cal.isDate($0.day, inSameDayAs: day) }

        PageScaffold(spine: .diary,
                     eyebrow: day.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                     title: "Diary",
                     subtitle: streakText) {
            VStack(alignment: .leading, spacing: 22) {
                WeekStrip(selected: $day,
                          busy: calendar.busyDays,
                          written: Set(entries.filter { !$0.text.isEmpty || $0.stars > 0 }.map { cal.startOfDay(for: $0.day) }))
                AgendaCard(access: calendar.access, events: calendar.events) {
                    calendar.request(then: day)
                }
                JournalCard(day: day, entry: entry)
                TodoCard(spine: .diary, inlineAdd: true)
            }
        } reach: {
            Button { creating = true } label: {
                Label("New event", systemImage: "plus")
            }
            .buttonStyle(QuietStyle())
            .disabled(calendar.access != .granted)
            Button {
                if let url = URL(string: "calshow:\(day.timeIntervalSinceReferenceDate)") { openURL(url) }
            } label: {
                Label("Open Calendar", systemImage: "calendar")
            }
            .buttonStyle(ProminentStyle(spine: .diary))
        }
        .onAppear { calendar.load(day: day) }
        .onChange(of: day) { _, newDay in calendar.load(day: newDay) }
        .sheet(isPresented: $creating, onDismiss: { calendar.load(day: day) }) {
            EventEditor(store: calendar.store, day: day, isPresented: $creating)
                .ignoresSafeArea()
        }
    }

    /// Consecutive days written, counting back from today (or yesterday).
    private var streakText: String {
        let cal = Calendar.current
        let written = Set(entries.filter { !$0.text.isEmpty || $0.stars > 0 }.map { cal.startOfDay(for: $0.day) })
        var cursor = cal.startOfDay(for: .now)
        if !written.contains(cursor) {
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        var streak = 0
        while written.contains(cursor) {
            streak += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        switch streak {
        case 0: return "Nothing written yet"
        case 1: return "Written 1 day running"
        default: return "Written \(streak) days running"
        }
    }
}

struct WeekStrip: View {
    @Binding var selected: Date
    let busy: Set<Date>
    let written: Set<Date>

    var body: some View {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: selected)?.start ?? selected
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }

        HStack(spacing: 0) {
            ForEach(days, id: \.self) { d in
                let isSelected = cal.isDate(d, inSameDayAs: selected)
                let isToday = cal.isDateInToday(d)
                let key = cal.startOfDay(for: d)
                let numberColour: Color = isSelected ? Spine.diary.onFill : (isToday ? Spine.diary.tint : Color.primary)

                Button { selected = key } label: {
                    VStack(spacing: 4) {
                        Text(d.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(d.formatted(.dateTime.day()))
                            .font(.subheadline.weight(isSelected || isToday ? .bold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(numberColour)
                            .frame(width: 26, height: 26)
                            .background {
                                if isSelected { Circle().fill(Spine.diary.fill) }
                            }
                        HStack(spacing: 2) {
                            Circle().fill(busy.contains(key) ? Spine.diary.tint : Color.clear).frame(width: 4, height: 4)
                            Circle().fill(written.contains(key) ? Ink.fuji : Color.clear).frame(width: 4, height: 4)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(d.formatted(date: .complete, time: .omitted))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 8)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .sensoryFeedback(.selection, trigger: selected)
    }
}

struct AgendaCard: View {
    let access: CalendarStore.Access
    let events: [EKEvent]
    let request: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Agenda", trailing: access == .granted ? (events.isEmpty ? "Clear" : "\(events.count)") : nil)
            switch access {
            case .granted:
                Card {
                    if events.isEmpty {
                        Text("Nothing in the calendar.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(events, id: \.self) { event in
                                EventRow(event: event)
                            }
                        }
                    }
                }
            case .unknown:
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your day from every calendar on this iPhone.")
                            .font(.subheadline)
                        Button("Show calendar", action: request)
                            .buttonStyle(ProminentStyle(spine: .diary))
                    }
                }
            case .denied:
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Calendar access is off for パラドックス.")
                            .font(.subheadline)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .buttonStyle(QuietStyle())
                    }
                }
            }
        }
    }
}

struct EventRow: View {
    let event: EKEvent

    var body: some View {
        let finished = event.endDate < .now

        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title ?? "Untitled")
                    .font(.subheadline.weight(.semibold))
                Text(timeLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .opacity(finished ? 0.45 : 1)
    }

    private var timeLine: String {
        let time = event.isAllDay ? "All day" : event.startDate.formatted(date: .omitted, time: .shortened)
        if let place = event.location, !place.isEmpty { return "\(time) · \(place)" }
        return time
    }
}

struct JournalCard: View {
    let day: Date
    let entry: Entry?
    @Environment(\.modelContext) private var context
    @State private var text = ""
    @State private var made: Entry?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Journal")
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    StarRating(stars: Binding(
                        get: { (entry ?? made)?.stars ?? 0 },
                        set: { current().stars = $0 }
                    ))
                    TextField("How was it?", text: $text, axis: .vertical)
                        .lineLimit(2...8)
                        .onChange(of: text) { _, newText in
                            if newText != ((entry ?? made)?.text ?? "") { current().text = newText }
                        }
                }
            }
        }
        .task(id: day) {
            made = nil
            text = entry?.text ?? ""
        }
    }

    private func current() -> Entry {
        if let existing = entry ?? made { return existing }
        let fresh = Entry(day: Calendar.current.startOfDay(for: day))
        context.insert(fresh)
        made = fresh
        return fresh
    }
}

/// Five stars from the mark, used as the day's rating.
struct StarRating: View {
    @Binding var stars: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    stars = (stars == i ? 0 : i)
                } label: {
                    Text("★")
                        .font(Mark.mincho(24))
                        .foregroundStyle(i <= stars ? Spine.diary.tint : Color.secondary.opacity(0.3))
                        .scaleEffect(i <= stars ? 1 : 0.86)
                        .frame(width: 34, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(i) of 5")
                .accessibilityAddTraits(i == stars ? .isSelected : [])
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.5), value: stars)
        .sensoryFeedback(.selection, trigger: stars)
    }
}

struct EventEditor: UIViewControllerRepresentable {
    let store: EKEventStore
    let day: Date
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = store
        let event = EKEvent(eventStore: store)
        let start = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        event.startDate = start
        event.endDate = start.addingTimeInterval(3600)
        event.calendar = store.defaultCalendarForNewEvents
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, @preconcurrency EKEventEditViewDelegate {
        var isPresented: Binding<Bool>

        init(isPresented: Binding<Bool>) { self.isPresented = isPresented }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            isPresented.wrappedValue = false
        }
    }
}
