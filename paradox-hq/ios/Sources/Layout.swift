import SwiftUI

/// The order of the cards on a tab. Each tab has a default order; hold a card
/// and drag it onto another and it takes that card's place. The order is kept.
nonisolated enum Layout {
    /// The tabs whose cards can be arranged, with the order they ship in.
    static let work = (key: "layout-work", cards: ["work", "mylist", "focus", "needs", "balance"])
    static let money = (key: "layout-money", cards: ["takings", "revenue", "subscribers", "payouts", "customers", "payments", "charge"])
    static let company = (key: "layout-company", cards: ["links", "deadlines", "connections", "notifications", "settings", "lock", "backup"])
    static let all = [work.key, money.key, company.key]

    /// What a dragged card carries, so a card is never mistaken for a to-do line.
    static let tag = "card:"

    /// The order to draw: what was saved, minus cards that no longer exist, plus
    /// any new ones in their default place at the end.
    static func order(_ saved: String, _ cards: [String]) -> [String] {
        var seen = Set<String>()
        let kept = saved.split(separator: ",").map(String.init).filter { cards.contains($0) && seen.insert($0).inserted }
        return kept + cards.filter { !kept.contains($0) }
    }

    /// `card` dropped on `target`: it takes the target's place, the target and
    /// everything between shifting one along, the way a list reorders.
    static func moved(_ order: [String], _ card: String, onto target: String) -> [String] {
        guard card != target, let from = order.firstIndex(of: card), let to = order.firstIndex(of: target) else { return order }
        var next = order
        next.remove(at: from)
        next.insert(card, at: to)
        return next
    }

    /// Handles a drop from anywhere on a card. False when what was dropped is not a card.
    @discardableResult
    static func drop(_ payload: String, onto target: String, key: String, cards: [String]) -> Bool {
        guard payload.hasPrefix(tag) else { return false }
        let card = String(payload.dropFirst(tag.count))
        let now = order(UserDefaults.standard.string(forKey: key) ?? "", cards)
        let next = moved(now, card, onto: target)
        guard next != now else { return false }
        UserDefaults.standard.set(next.joined(separator: ","), forKey: key)
        return true
    }

    static func reset() {
        for key in all { UserDefaults.standard.removeObject(forKey: key) }
    }
}

/// A card that can be picked up and dropped on another to change the tab's order.
struct Arranged<Content: View>: View {
    let card: String
    let name: String
    let tab: (key: String, cards: [String])
    @ViewBuilder var content: () -> Content
    @State private var over = false

    var body: some View {
        content()
            // Where it would land: a line across the top of the card under the finger.
            .overlay(alignment: .top) {
                if over {
                    Capsule()
                        .fill(Ink.head)
                        .frame(height: 3)
                        .offset(y: -12)
                        .transition(.opacity)
                }
            }
            .draggable(Layout.tag + card) {
                Text(name)
                    .font(Face.style(.subheadline, .semibold))
                    .foregroundStyle(Ink.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Ink.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .dropDestination(for: String.self) { dropped, _ in
                over = false
                guard let payload = dropped.first else { return false }
                let landed = withAnimation(.snappy) { Layout.drop(payload, onto: card, key: tab.key, cards: tab.cards) }
                if landed { Thud.play() }
                return landed
            } isTargeted: { inside in
                withAnimation(.easeOut(duration: 0.12)) { over = inside }
            }
    }
}
