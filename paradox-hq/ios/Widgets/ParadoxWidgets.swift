import WidgetKit
import SwiftUI

struct TakingsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct TakingsProvider: TimelineProvider {
    func placeholder(in context: Context) -> TakingsEntry {
        TakingsEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (TakingsEntry) -> Void) {
        let snapshot = context.isPreview ? WidgetSnapshot.sample : (WidgetSnapshot.load() ?? .sample)
        completion(TakingsEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<TakingsEntry>) -> Void) {
        let now = Date()
        let entry = TakingsEntry(date: now, snapshot: WidgetSnapshot.load() ?? .sample)
        // The app reloads the widgets whenever it has new figures. This only makes
        // sure "today" goes back to nothing once the day turns.
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(min(midnight, now.addingTimeInterval(3600)))))
    }
}

struct TakingsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TakingsEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                WidgetMedium(snapshot: entry.snapshot)
            case .accessoryRectangular:
                WidgetLockRect(snapshot: entry.snapshot)
            case .accessoryCircular:
                WidgetLockCircle(snapshot: entry.snapshot)
            case .accessoryInline:
                Text("\(Money.string(entry.snapshot.todayValue(), currency: entry.snapshot.currency)) today")
            default:
                WidgetSmall(snapshot: entry.snapshot)
            }
        }
        .containerBackground(for: .widget) { Color.black }
    }
}

struct TakingsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "takings", provider: TakingsProvider()) { entry in
            TakingsView(entry: entry)
        }
        .configurationDisplayName("PARADOX")
        .description("Today's takings, the month, and what needs you.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

@main
struct ParadoxWidgets: WidgetBundle {
    var body: some Widget {
        TakingsWidget()
    }
}
