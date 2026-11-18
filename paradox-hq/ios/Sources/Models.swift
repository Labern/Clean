import Foundation
import SwiftData

// Every stored property has a default so the store can move to CloudKit later
// without a migration. Schema changes are additive only: never lose an item.

@Model final class Project {
    /// The record's permanent id in the canonical copy (a uuid, made here). Empty
    /// until the first sync gives it one. See `CloudSync`.
    var uid: String = ""
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
    /// The one list that is Labern's own rather than a project's. It never
    /// goes to the feed and can't be deleted.
    var isPersonal: Bool = false
    /// The name the feed last sent. The feed only renames a project when its
    /// own wording changes, so a rename on the phone sticks.
    var remoteName: String = ""
    @Relationship(deleteRule: .cascade, inverse: \FocusItem.project) var items: [FocusItem] = []
    /// Deleting a project keeps its notes; they just stop belonging to it.
    @Relationship(deleteRule: .nullify, inverse: \Note.project) var notes: [Note] = []

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
    /// The record's permanent id in the canonical copy (a uuid, made here). Empty
    /// until the first sync gives it one. See `CloudSync`.
    var uid: String = ""
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
    /// Its sub-items are folded away in the list.
    var collapsed: Bool = false
    /// When it's due, if it has a day.
    var due: Date? = nil
    /// The wording the feed last sent (see `Project.remoteName`).
    var remoteTitle: String = ""

    init(title: String, notes: String = "", done: Bool = false, order: Int = 0) {
        self.title = title
        self.notes = notes
        self.done = done
        self.order = order
        self.completed = done ? Date() : nil
    }
}

/// A note. Plain text; the first line is its title.
@Model final class Note {
    /// The record's permanent id in the canonical copy (a uuid, made here). Empty
    /// until the first sync gives it one. See `CloudSync`.
    var uid: String = ""
    var text: String = ""
    var created: Date = Date()
    /// When the words last changed. Not called `updated`: the store underneath
    /// already has an `isUpdated` of its own, and a property by that name reads
    /// back as nothing (every note dated 1 January 2001).
    var edited: Date = Date()
    var pinned: Bool = false
    /// Dealt with: ticked, crossed out, and kept in the Done list at the bottom.
    var done: Bool = false
    /// When it was marked done, so the Done list shows the latest first.
    var finished: Date? = nil
    var project: Project? = nil

    init(text: String = "", project: Project? = nil, created: Date = .now) {
        self.text = text
        self.project = project
        self.created = created
        self.edited = created
    }
}

@Model final class Deadline {
    /// The record's permanent id in the canonical copy (a uuid, made here). Empty
    /// until the first sync gives it one. See `CloudSync`.
    var uid: String = ""
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

    /// Counts the smallest tickable lines, at any depth: a line with
    /// sub-items counts as its sub-items.
    var tally: (done: Int, total: Int) {
        items.reduce((0, 0)) { sum, item in
            let leaves = item.leaves(forced: false)
            return (sum.0 + leaves.done, sum.1 + leaves.total)
        }
    }

    var nextOrder: Int { (items.map(\.order).max() ?? -1) + 1 }
}

extension FocusItem {
    var sortedChildren: [FocusItem] {
        children.sorted { ($0.order, $0.created) < ($1.order, $1.created) }
    }

    var nextOrder: Int { (children.map(\.order).max() ?? -1) + 1 }

    /// The smallest tickable lines under this one (itself, if it has none).
    /// Everything under a finished line counts as finished.
    func leaves(forced: Bool = false) -> (done: Int, total: Int) {
        let finished = forced || done
        if children.isEmpty { return (finished ? 1 : 0, 1) }
        return children.reduce((0, 0)) { sum, child in
            let leaves = child.leaves(forced: finished)
            return (sum.0 + leaves.done, sum.1 + leaves.total)
        }
    }

    /// How many lines up to the project: 0 for a top-level line.
    var depth: Int {
        var depth = 0
        var walk = parent
        while let above = walk {
            depth += 1
            walk = above.parent
        }
        return depth
    }

    /// The project this line belongs to, however deep it sits.
    var owner: Project? {
        var walk: FocusItem? = self
        while let line = walk {
            if let project = line.project { return project }
            walk = line.parent
        }
        return nil
    }

    /// The lines above this one, top first.
    var ancestors: [FocusItem] {
        var chain: [FocusItem] = []
        var walk = parent
        while let above = walk {
            chain.insert(above, at: 0)
            walk = above.parent
        }
        return chain
    }

    /// True when `other` sits somewhere under this line.
    func contains(_ other: FocusItem) -> Bool {
        var walk = other.parent
        while let above = walk {
            if above === self { return true }
            walk = above.parent
        }
        return false
    }

    var overdue: Bool {
        guard let due, !done else { return false }
        return due < Calendar.current.startOfDay(for: .now)
    }

    /// Ticking a line ticks everything under it. Finishing the last open line
    /// under a parent finishes the parent, all the way up; reopening a line
    /// reopens every line above it.
    func set(done value: Bool, at now: Date = .now) {
        done = value
        completed = value ? now : nil
        if value { finishAll(at: now) }
        var walk = parent
        while let above = walk {
            if value {
                guard above.children.allSatisfy(\.done), !above.done else { break }
                above.done = true
                above.completed = now
            } else {
                guard above.done else { break }
                above.done = false
                above.completed = nil
            }
            walk = above.parent
        }
    }

    private func finishAll(at now: Date) {
        for child in children {
            if !child.done {
                child.done = true
                child.completed = now
            }
            child.finishAll(at: now)
        }
    }

    /// Something new under a finished line means it isn't finished, nor is anything above it.
    func reopenForNewChild() {
        var walk: FocusItem? = self
        while let line = walk, line.done {
            line.done = false
            line.completed = nil
            walk = line.parent
        }
    }

    /// Adds a sub-item at the end of this line's sub-items, and unfolds it so it shows.
    @discardableResult
    func add(_ title: String, in context: ModelContext) -> FocusItem {
        let child = FocusItem(title: title, order: nextOrder)
        context.insert(child)
        child.parent = self
        collapsed = false
        reopenForNewChild()
        return child
    }

    /// The lines beside this one as they're shown: a parent's sub-items, or the
    /// project's open lines (finished ones sit apart, under Done).
    var siblings: [FocusItem] {
        if let parent { return parent.sortedChildren }
        return project?.openItems ?? []
    }

    /// This line and everything under it.
    var family: [FocusItem] { [self] + children.flatMap(\.family) }

    /// Deletes the line and everything under it, for good: lines that came from
    /// the Claude feed are remembered so the next pull doesn't bring them back.
    func remove(from context: ModelContext) {
        Tombstones.bury(family.map(\.remoteID))
        context.delete(self)
        try? context.save()
    }

    /// Makes this line a sub-item of the line just above it.
    /// Returns false when there's no line above to go under.
    @discardableResult
    func indent() -> Bool {
        let row = siblings
        guard let index = row.firstIndex(where: { $0 === self }), index > 0 else { return false }
        let above = row[index - 1]
        order = above.nextOrder
        project = nil
        parent = above
        above.collapsed = false
        if above.done && !done { above.reopenForNewChild() }
        return true
    }

    /// Lifts a sub-item out to sit just after its parent.
    @discardableResult
    func outdent() -> Bool {
        guard let above = parent else { return false }
        let row = above.siblings
        let place = above.order
        for sibling in row where sibling.order > place { sibling.order += 1 }
        order = place + 1
        if let grand = above.parent {
            parent = grand
        } else {
            parent = nil
            project = above.project
        }
        return true
    }
}

/// The rows of a to-do list as they're drawn: each line at its depth, with
/// folded lines hiding what's under them.
enum Outline {
    enum Row: Identifiable {
        case line(FocusItem, depth: Int)
        /// Where a new sub-item is being typed.
        case draft(under: FocusItem, depth: Int)

        var id: String {
            switch self {
            case .line(let item, _): "line-\(ObjectIdentifier(item).hashValue)"
            case .draft(let parent, _): "draft-\(ObjectIdentifier(parent).hashValue)"
            }
        }

        var depth: Int {
            switch self {
            case .line(_, let depth), .draft(_, let depth): depth
            }
        }

        /// The lines this row sits under, then the row's own line: one per level.
        /// A row being typed has no line of its own yet, so its chain stops at its parent.
        var chain: [FocusItem] {
            switch self {
            case .line(let item, _): item.ancestors + [item]
            case .draft(let parent, _): parent.ancestors + [parent]
            }
        }
    }

    /// Drops the row at `source` into the gap at `destination`, both counted in
    /// `rows` as drawn (the way a list reports a drag). The line takes everything
    /// under it along, and ends up exactly where it was let go:
    ///
    /// - between two lines of the same level, it joins that level;
    /// - just under a line whose sub-items are showing, it becomes the first of them;
    /// - where a gap could belong to more than one level (after the last sub-item
    ///   of something), it keeps the level it had, as near as the gap allows.
    ///
    /// Returns false when that is where it already was.
    @discardableResult
    static func move(_ rows: [Row], from source: Int, to destination: Int) -> Bool {
        guard rows.indices.contains(source), case .line(let item, let depth) = rows[source],
              let project = item.owner else { return false }
        let end = end(of: source, in: rows)
        // Let go on itself, or among its own sub-items: nothing to do.
        guard destination < source || destination > end else { return false }

        let rest = Array(rows[..<source]) + Array(rows[end...])
        let gap = min(max(destination < source ? destination : destination - (end - source), 0), rest.count)
        let above = gap > 0 ? rest[gap - 1] : nil
        let below = gap < rest.count ? rest[gap] : nil

        // The levels this gap can hold run from the line below up to the line above.
        let lowest = below?.depth ?? 0
        let highest = max(above?.depth ?? 0, lowest)
        let level = min(max(depth, lowest), highest)

        // The lines above the gap, one per level: [top line, its sub-item, …].
        let chain = above?.chain ?? []
        let parent = level == 0 ? nil : chain.indices.contains(level - 1) ? chain[level - 1] : nil
        guard level == 0 || parent != nil else { return false }

        var row = (parent?.sortedChildren ?? project.sortedItems).filter { $0 !== item }
        let home = item.parent
        let homeRow = home?.sortedChildren ?? project.sortedItems
        if case .line(let next, let nextDepth)? = below, nextDepth == level,
           let index = row.firstIndex(where: { $0 === next }) {
            row.insert(item, at: index)
        } else if chain.indices.contains(level), let index = row.firstIndex(where: { $0 === chain[level] }) {
            row.insert(item, at: index + 1)
        } else if above == nil {
            row.insert(item, at: 0)
        } else {
            row.append(item)
        }
        if home === parent, homeRow.elementsEqual(row, by: { $0 === $1 }) { return false }

        if let parent {
            item.project = nil
            item.parent = parent
            parent.collapsed = false
            if parent.done && !item.done { parent.reopenForNewChild() }
        } else {
            item.parent = nil
            item.project = project
        }
        for (index, line) in row.enumerated() where line.order != index { line.order = index }
        return true
    }

    /// The index just past a row and everything drawn under it.
    static func end(of index: Int, in rows: [Row]) -> Int {
        var end = index + 1
        while end < rows.count, rows[end].depth > rows[index].depth { end += 1 }
        return end
    }

    static func rows(_ top: [FocusItem], drafting: FocusItem? = nil) -> [Row] {
        var rows: [Row] = []
        func walk(_ item: FocusItem, _ depth: Int) {
            rows.append(.line(item, depth: depth))
            let open = !item.collapsed || item === drafting
            if open {
                for child in item.sortedChildren { walk(child, depth + 1) }
            }
            if item === drafting { rows.append(.draft(under: item, depth: depth + 1)) }
        }
        for item in top { walk(item, 0) }
        return rows
    }
}

/// Feed ids deleted on the phone, so the feed never adds them again.
nonisolated enum Tombstones {
    static let key = "feed-deleted"

    static var all: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func bury(_ ids: [String]) {
        let ids = ids.filter { !$0.isEmpty }
        guard !ids.isEmpty else { return }
        UserDefaults.standard.set(Array(all.union(ids)).sorted(), forKey: key)
    }
}

extension Project {
    /// Deletes the project and its lines (its notes stay), remembering feed ids.
    func remove(from context: ModelContext) {
        Tombstones.bury([remoteID] + items.flatMap(\.family).map(\.remoteID))
        context.delete(self)
        try? context.save()
    }
}

extension Note {
    /// Marks the note done, or brings it back. Its words and its date are left alone.
    func set(done value: Bool, at now: Date = .now) {
        done = value
        finished = value ? now : nil
    }

    /// Notes in the order the Done list shows them: the latest finished first.
    static func doneOrder(_ notes: [Note]) -> [Note] {
        notes.filter(\.done).sorted { ($0.finished ?? $0.edited) > ($1.finished ?? $1.edited) }
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
