import SwiftUI

// Shared by the app and the widget extension. The app works the figures out and
// leaves this one small snapshot in the App Group; the widgets only draw it.
// The Stripe key never leaves the app.

nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    var today = 0
    var month = 0
    var monthChange: Double? = nil
    /// Everything waiting on a decision.
    var needs = 0
    /// The part of `needs` that isn't money (deadlines, the site), which a
    /// background refresh can't recount and so carries over.
    var otherNeeds = 0
    /// Thirty days of revenue, smoothed, oldest first.
    var trend: [Int] = []
    var currency = "gbp"
    var example = true
    var updated = Date()

    static let group = "group.com.labern.paradox.hq"
    static let key = "widget-snapshot"

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: group)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.group)?.set(data, forKey: Self.key)
    }

    /// Today's figure only holds on the day it was taken.
    func todayValue(now: Date = .now, calendar: Calendar = .current) -> Int {
        calendar.isDate(updated, inSameDayAs: now) ? today : 0
    }

    static let sample = WidgetSnapshot(
        today: 18_400, month: 184_200, monthChange: 0.23, needs: 3, otherNeeds: 1,
        trend: [40, 44, 52, 61, 58, 49, 43, 41, 47, 55, 62, 60, 57, 63, 70, 66, 59, 52, 50, 56,
                64, 71, 69, 62, 58, 61, 68, 76, 80, 84],
        currency: "gbp", example: true, updated: Date())
}

extension Money {
    /// "£1.8k" for the places a full figure won't fit.
    nonisolated static func compact(_ minor: Int, currency: String = "gbp", locale: Locale = .current) -> String {
        let pounds = Double(minor) / 100
        guard pounds >= 1000 else { return string(minor, currency: currency, locale: locale) }
        let symbol = string(0, currency: currency, locale: locale).filter { !$0.isNumber }
            .trimmingCharacters(in: .whitespaces)
        let thousands = pounds / 1000
        let figure = thousands >= 100 ? String(format: "%.0fk", thousands) : String(format: "%.1fk", thousands)
        return symbol + figure
    }
}

/// A line with a soft fill under it. Drawn by hand so the widget needs no chart library.
struct Sparkline: View {
    let values: [Int]
    var color: Color = Ink.violet

    var body: some View {
        GeometryReader { proxy in
            let points = Self.points(values, in: proxy.size)
            if points.count > 1 {
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: proxy.size.height))
                        for point in points { path.addLine(to: point) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)],
                                         startPoint: .top, endPoint: .bottom))
                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    nonisolated static func points(_ values: [Int], in size: CGSize) -> [CGPoint] {
        guard values.count > 1, let low = values.min(), let high = values.max() else { return [] }
        let span = CGFloat(max(1, high - low))
        let step = size.width / CGFloat(values.count - 1)
        let inset: CGFloat = 2
        return values.enumerated().map { index, value in
            let fraction = CGFloat(value - low) / span
            return CGPoint(x: CGFloat(index) * step, y: inset + (1 - fraction) * (size.height - inset * 2))
        }
    }
}

struct WidgetMark: View {
    var width: CGFloat

    var body: some View {
        Image("Mark")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width)
            .foregroundStyle(.white)
            .accessibilityLabel("PARADOX")
    }
}

struct WidgetChange: View {
    let change: Double?

    var body: some View {
        if let change {
            let up = change >= 0
            Text("\(up ? "▲" : "▼") \(abs(change).formatted(.percent.precision(.fractionLength(0))))")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(up ? Ink.ok : Ink.hazard)
        }
    }
}

/// Home Screen, small: today's takings and the month.
struct WidgetSmall: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetMark(width: 92)
            Spacer(minLength: 4)
            Text("Today")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ink.muted)
            Text(Money.string(snapshot.todayValue(), currency: snapshot.currency))
                .font(.system(size: 30, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            HStack(spacing: 5) {
                Text("\(snapshot.updated.formatted(.dateTime.month(.abbreviated))) \(Money.compact(snapshot.month, currency: snapshot.currency))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Ink.muted)
                    .lineLimit(1)
                WidgetChange(change: snapshot.monthChange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Home Screen, medium: the month, its trend, and what's waiting.
struct WidgetMedium: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                WidgetMark(width: 100)
                Spacer(minLength: 8)
                WidgetChange(change: snapshot.monthChange)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(snapshot.updated.formatted(.dateTime.month(.wide))) so far")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Ink.muted)
                    Text(Money.string(snapshot.month, currency: snapshot.currency))
                        .font(.system(size: 26, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Today")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Ink.muted)
                    Text(Money.string(snapshot.todayValue(), currency: snapshot.currency))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Needs you")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Ink.muted)
                    Text("\(snapshot.needs)")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(snapshot.needs > 0 ? Ink.amber : Ink.muted)
                }
                .padding(.leading, 6)
            }
            Sparkline(values: snapshot.trend)
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Lock Screen, rectangular.
struct WidgetLockRect: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Today")
                .font(.caption2.weight(.semibold))
                .opacity(0.75)
            Text(Money.string(snapshot.todayValue(), currency: snapshot.currency))
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(snapshot.updated.formatted(.dateTime.month(.abbreviated))) \(Money.compact(snapshot.month, currency: snapshot.currency))\(Self.arrow(snapshot.monthChange))")
                .font(.caption2)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    nonisolated static func arrow(_ change: Double?) -> String {
        guard let change else { return "" }
        return " \(change >= 0 ? "▲" : "▼")\(abs(change).formatted(.percent.precision(.fractionLength(0))))"
    }
}

/// Lock Screen, circular.
struct WidgetLockCircle: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "star.fill")
                .font(.system(size: 9, weight: .bold))
            Text(Money.compact(snapshot.todayValue(), currency: snapshot.currency))
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("today")
                .font(.system(size: 9, weight: .semibold))
                .opacity(0.75)
        }
        .padding(4)
    }
}
