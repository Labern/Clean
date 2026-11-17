import Foundation
import SwiftData

// Every stored property has a default so the store can move to CloudKit later
// without a migration. Schema changes are additive only: never lose an item.

@Model final class Project {
    /// Set when the project came from the Claude feed; empty for ones made on the phone.
    var remoteID: String = ""
    var name: String = ""
    var summary: String = ""
    var stage: String = ""
    var symbol: String = "square.stack.3d.up"
    var tint: Int = 0xA78BFA
    var link: String = ""
    var order: Int = 0
    var created: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \FocusItem.project) var items: [FocusItem] = []

    init(name: String, summary: String = "", stage: String = "", symbol: String = "square.stack.3d.up",
         tint: Int = 0xA78BFA, link: String = "", order: Int = 0) {
        self.name = name
        self.summary = summary
        self.stage = stage
        self.symbol = symbol
        self.tint = tint
        self.link = link
        self.order = order
    }
}

/// One line of a project's Focus list. Top-level lines belong to a project;
/// sub-items belong to a parent line instead.
@Model final class FocusItem {
    var remoteID: String = ""
    var title: String = ""
    var notes: String = ""
    var done: Bool = false
    var completed: Date? = nil
    var order: Int = 0
    var created: Date = Date()
    var project: Project? = nil
    var parent: FocusItem? = nil
    @Relationship(deleteRule: .cascade, inverse: \FocusItem.parent) var children: [FocusItem] = []

    init(title: String, notes: String = "", done: Bool = false, order: Int = 0) {
        self.title = title
        self.notes = notes
        self.done = done
        self.order = order
        self.completed = done ? Date() : nil
    }
}

@Model final class Deadline {
    var title: String = ""
    var who: String = ""
    var date: Date = Date()
    /// 0 means it happens once.
    var everyMonths: Int = 12

    init(title: String, who: String = "", date: Date = .now, everyMonths: Int = 12) {
        self.title = title
        self.who = who
        self.date = date
        self.everyMonths = everyMonths
    }
}

extension Project {
    var sortedItems: [FocusItem] {
        items.sorted { ($0.order, $0.created) < ($1.order, $1.created) }
    }

    var openItems: [FocusItem] { sortedItems.filter { !$0.done } }

    var doneItems: [FocusItem] {
        items.filter { $0.done }
            .sorted { ($0.completed ?? .distantPast) > ($1.completed ?? .distantPast) }
    }

    /// Counts the smallest tickable lines: a line with sub-items counts as its sub-items.
    var tally: (done: Int, total: Int) {
        var done = 0
        var total = 0
        for item in items {
            if item.children.isEmpty {
                total += 1
                if item.done { done += 1 }
            } else {
                total += item.children.count
                done += item.children.filter { $0.done || item.done }.count
            }
        }
        return (done, total)
    }

    var nextOrder: Int { (items.map(\.order).max() ?? -1) + 1 }
}

extension FocusItem {
    var sortedChildren: [FocusItem] {
        children.sorted { ($0.order, $0.created) < ($1.order, $1.created) }
    }

    var nextOrder: Int { (children.map(\.order).max() ?? -1) + 1 }

    /// Ticking a line ticks what's under it; finishing the last sub-item
    /// finishes its parent, and reopening one reopens the parent.
    func set(done value: Bool, at now: Date = .now) {
        done = value
        completed = value ? now : nil
        if value {
            for child in children where !child.done {
                child.done = true
                child.completed = now
            }
        }
        if let parent {
            if value, parent.children.allSatisfy(\.done), !parent.done {
                parent.done = true
                parent.completed = now
            } else if !value, parent.done {
                parent.done = false
                parent.completed = nil
            }
        }
    }
}

extension Deadline {
    /// A repeating deadline rolls forward; a one-off is finished.
    /// Returns false when the caller should delete it.
    func markDone(calendar: Calendar = .current) -> Bool {
        guard everyMonths > 0, let next = calendar.date(byAdding: .month, value: everyMonths, to: date) else {
            return false
        }
        date = next
        return true
    }
}
