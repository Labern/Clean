import SwiftUI
import SwiftData
import UIKit

// The to-do list: lines that tick, open into a page of their own, and hold
// sub-items to any depth, each of which can be folded away.

/// The thud of something dragged being let go in its new place.
enum Thud {
    static func play() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Something finished.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - One line

/// One line of a list, drawn at its depth: tick, words, and (when it has
/// sub-items) a count that folds and unfolds them.
struct OutlineLine: View {
    @Bindable var item: FocusItem
    let tint: Color
    var depth: Int = 0
    /// Off where a line's sub-items aren't listed under it (the Done section).
    var showsFold = true
    let open: () -> Void

    var body: some View {
        let children = item.children
        let small = depth > 0
        HStack(spacing: 2) {
            Button {
                withAnimation(.snappy.delay(item.done || depth > 0 ? 0 : 0.34)) { item.set(done: !item.done) }
            } label: {
                Tick(done: item.done, color: tint, size: small ? 20 : 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? "Reopen \(item.title)" : "Tick \(item.title)")

            Button(action: open) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title.isEmpty ? "Untitled" : item.title)
                        .font(Face.style(small ? .subheadline : .body))
                        .strikethrough(item.done)
                        .foregroundStyle(item.done || item.title.isEmpty ? Ink.muted : Ink.body)
                        .multilineTextAlignment(.leading)
                    if item.due != nil || !item.notes.isEmpty {
                        HStack(spacing: 6) {
                            if let due = item.due {
                                DueLabel(date: due, late: item.overdue)
                            }
                            if !item.notes.isEmpty {
                                Text(item.notes)
                                    .foregroundStyle(Ink.muted)
                                    .lineLimit(1)
                            }
                        }
                        .font(Face.style(.caption))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens it")

            if showsFold, !children.isEmpty {
                Fold(item: item)
            }
        }
        .padding(.leading, CGFloat(depth) * 24)
        .sensoryFeedback(.success, trigger: item.done) { _, new in new }
    }
}

/// The count of a line's sub-items, which folds them away and back.
struct Fold: View {
    @Bindable var item: FocusItem

    var body: some View {
        let leaves = item.leaves()
        Button {
            withAnimation(.snappy) { item.collapsed.toggle() }
        } label: {
            HStack(spacing: 5) {
                Text("\(leaves.done)/\(leaves.total)")
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(Face.style(.caption2, .bold))
                    .rotationEffect(.degrees(item.collapsed ? -90 : 0))
            }
            .font(Face.style(.caption))
            .foregroundStyle(item.collapsed ? Ink.body : Ink.muted)
            .padding(.horizontal, 10)
            .frame(minWidth: 44, minHeight: 30)
            .background(item.collapsed ? Ink.surface2 : .clear, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: item.collapsed)
        .accessibilityLabel(item.collapsed ? "Show sub-items" : "Hide sub-items")
        .accessibilityValue("\(leaves.done) of \(leaves.total) done")
    }
}

struct DueLabel: View {
    let date: Date
    var late: Bool = false

    var body: some View {
        let days = Days.count(to: date)
        let text = switch days {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        case 2...6: date.formatted(.dateTime.weekday(.wide))
        default: date.formatted(.dateTime.day().month(.abbreviated))
        }
        Label(text, systemImage: "calendar")
            .labelStyle(.titleAndIcon)
            .foregroundStyle(late ? Ink.hazard : days == 0 ? Ink.amber : Ink.muted)
    }
}

// MARK: - The list

/// A project's open lines as a list section: every sub-item under its line,
/// foldable, with a row to type new sub-items straight in.
struct OutlineSection: View {
    let lines: [FocusItem]
    let tint: Color
    @Binding var drafting: FocusItem?
    let open: (FocusItem) -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        let rows = Outline.rows(lines, drafting: drafting)
        ForEach(rows) { row in
            switch row {
            case .line(let item, let depth):
                OutlineLine(item: item, tint: tint, depth: depth) { open(item) }
                    .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 10))
                    .listRowBackground(Ink.surface)
                    .listRowSeparatorTint(Ink.line)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            startDraft(under: item)
                        } label: {
                            Label("Sub-item", systemImage: "text.badge.plus")
                        }
                        .tint(Ink.violet)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            withAnimation { remove(item) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu { LineMenu(item: item, open: { open(item) }, addUnder: { startDraft(under: item) }) }
            case .draft(let parent, let depth):
                DraftLine(parent: parent, depth: depth, tint: tint) { drafting = nil }
                    .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 10))
                    .listRowBackground(Ink.surface)
                    .listRowSeparatorTint(Ink.line)
                    .moveDisabled(true)
            }
        }
        // Hold a line, then drag: it lands where it's let go, sub-items and all.
        .onMove { from, to in
            guard let source = from.first else { return }
            if Outline.move(rows, from: source, to: to) { Thud.play() }
        }
    }

    private func startDraft(under item: FocusItem) {
        withAnimation(.snappy) {
            item.collapsed = false
            drafting = item
        }
    }

    private func remove(_ item: FocusItem) {
        if let drafting, drafting === item || item.contains(drafting) { self.drafting = nil }
        item.remove(from: context)
    }
}

/// What a long press on a line offers.
struct LineMenu: View {
    let item: FocusItem
    let open: () -> Void
    let addUnder: () -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        Button("Open", systemImage: "arrow.up.right", action: open)
        Button("Add sub-item", systemImage: "text.badge.plus", action: addUnder)
        if !item.children.isEmpty {
            Button(item.collapsed ? "Show sub-items" : "Hide sub-items",
                   systemImage: item.collapsed ? "chevron.down" : "chevron.up") {
                withAnimation(.snappy) { item.collapsed.toggle() }
            }
        }
        Divider()
        let row = item.siblings
        if let index = row.firstIndex(where: { $0 === item }), index > 0 {
            Button("Put under \u{201C}\(row[index - 1].title)\u{201D}", systemImage: "increase.indent") {
                withAnimation(.snappy) { _ = item.indent() }
            }
        }
        if item.parent != nil {
            Button("Move out a level", systemImage: "decrease.indent") {
                withAnimation(.snappy) { _ = item.outdent() }
            }
        }
        Button("Move to top", systemImage: "arrow.up.to.line") {
            let lowest = item.siblings.map(\.order).min() ?? 0
            withAnimation(.snappy) { item.order = lowest - 1 }
        }
        Menu("Due", systemImage: "calendar") {
            Button("Today") { item.due = Calendar.current.startOfDay(for: .now) }
            Button("Tomorrow") {
                item.due = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))
            }
            Button("Next week") {
                item.due = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: .now))
            }
            if item.due != nil {
                Button("No date", role: .destructive) { item.due = nil }
            }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            withAnimation { item.remove(from: context) }
        }
    }
}

/// A row for typing sub-items under a line. Return adds one and stays for the
/// next; return on an empty row, or tapping away, closes it.
struct DraftLine: View {
    let parent: FocusItem
    let depth: Int
    let tint: Color
    let finish: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(spacing: 2) {
            Circle()
                .strokeBorder(tint.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .frame(width: 20, height: 20)
                .frame(width: 44, height: 44)
            TextField("Under \(parent.title)", text: $text)
                .font(Face.style(.subheadline))
                .focused($focused)
                .submitLabel(.next)
                .onSubmit(add)
                .frame(minHeight: 44)
        }
        .padding(.leading, CGFloat(depth) * 24)
        .onAppear { focused = true }
        .onDisappear {
            // Swiping to type under another line mustn't lose what was half typed here.
            let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, !parent.isDeleted { _ = parent.add(title, in: context) }
        }
        .onChange(of: focused) { _, now in
            if !now {
                add()
                finish()
            }
        }
    }

    private func add() {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            if focused { finish() }
            return
        }
        text = ""
        withAnimation(.snappy) { _ = parent.add(title, in: context) }
        focused = true
    }
}

// MARK: - A line's own page

/// One line, the whole page: its words, a note, a due date, and its sub-items,
/// each of which opens into a page of its own.
struct ItemPage: View {
    @Bindable var item: FocusItem
    let tint: Color
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var next: FocusItem? = nil
    @State private var draft = ""
    @State private var deleting = false
    @FocusState private var field: Field?

    enum Field { case title, note, adding }

    var body: some View {
        let children = item.sortedChildren
        let leaves = item.leaves()
        Form {
            Section {
                TextField("Title", text: $item.title, axis: .vertical)
                    .font(Face.style(.title3, .semibold))
                    .strikethrough(item.done)
                    .focused($field, equals: .title)
                    .submitLabel(.next)
                    .onChange(of: item.title) { _, new in
                        // Return in a title goes on to the note, rather than breaking the line.
                        guard new.contains("\n") else { return }
                        item.title = new.replacingOccurrences(of: "\n", with: "")
                        field = .note
                    }
                TextField("Note", text: $item.notes, axis: .vertical)
                    .lineLimit(1...8)
                    .foregroundStyle(Ink.muted)
                    .focused($field, equals: .note)
            } header: {
                Trail(item: item)
            }

            Section {
                ForEach(children) { child in
                    ChildLine(item: child, tint: tint) { next = child }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                withAnimation { child.remove(from: context) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            LineMenu(item: child, open: { next = child }, addUnder: { next = child })
                        }
                }
                .onMove { from, to in
                    var row = children
                    row.move(fromOffsets: from, toOffset: to)
                    for (index, line) in row.enumerated() { line.order = index }
                    Thud.play()
                }
                HStack(spacing: 2) {
                    Image(systemName: "plus")
                        .font(Face.at(15, .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 44, height: 44)
                    TextField("Add a sub-item", text: $draft)
                        .focused($field, equals: .adding)
                        .submitLabel(.next)
                        .onSubmit(add)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 14))
            } header: {
                HStack {
                    Text("Sub-items")
                    Spacer()
                    if !children.isEmpty {
                        Text("\(leaves.done)/\(leaves.total)").monospacedDigit()
                    }
                }
            }

            Section {
                Toggle("Due date", isOn: Binding(
                    get: { item.due != nil },
                    set: { item.due = $0 ? Calendar.current.startOfDay(for: .now) : nil }))
                if let due = item.due {
                    DatePicker("Due", selection: Binding(get: { due }, set: { item.due = $0 }),
                               displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(tint)
                }
            }

            Section {
                Toggle("Done", isOn: Binding(get: { item.done }, set: { value in
                    withAnimation(.snappy) { item.set(done: value) }
                }))
                .tint(tint)
                if let completed = item.completed, item.done {
                    LabeledContent("Finished", value: completed.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                }
                LabeledContent("Added", value: item.created.formatted(.dateTime.day().month(.abbreviated).year()))
            }

            Section {
                Button("Delete", role: .destructive) { deleting = true }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Ink.ground)
        .navigationTitle(item.parent == nil ? "To-do" : "Sub-item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if field != nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { field = nil }
                        .fontWeight(.semibold)
                }
            }
        }
        .navigationDestination(item: $next) { ItemPage(item: $0, tint: tint) }
        .sensoryFeedback(.success, trigger: item.done) { _, new in new }
        .confirmationDialog(children.isEmpty ? "Delete this?" : "Delete this and everything under it?",
                            isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                // Leave the page first, so it never draws a line that's gone.
                let doomed = item
                dismiss()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    doomed.remove(from: context)
                }
            }
        }
    }

    private func add() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            field = nil
            return
        }
        withAnimation(.snappy) { _ = item.add(title, in: context) }
        draft = ""
        field = .adding
    }
}

/// Where a line sits: its project, then each line above it.
struct Trail: View {
    let item: FocusItem

    var body: some View {
        let names = [item.owner?.name].compactMap { $0 } + item.ancestors.map(\.title)
        if !names.isEmpty {
            Text(names.joined(separator: "  ›  "))
                .lineLimit(1)
                .truncationMode(.head)
                .textCase(nil)
        }
    }
}

/// A sub-item on its parent's page: tick it here, or open it to go deeper.
struct ChildLine: View {
    @Bindable var item: FocusItem
    let tint: Color
    let open: () -> Void

    var body: some View {
        let leaves = item.leaves()
        HStack(spacing: 2) {
            Button {
                withAnimation(.snappy) { item.set(done: !item.done) }
            } label: {
                Tick(done: item.done, color: tint, size: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? "Reopen \(item.title)" : "Tick \(item.title)")
            Button(action: open) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title.isEmpty ? "Untitled" : item.title)
                            .strikethrough(item.done)
                            .foregroundStyle(item.done ? Ink.muted : Ink.body)
                            .multilineTextAlignment(.leading)
                        if let due = item.due {
                            DueLabel(date: due, late: item.overdue)
                                .font(Face.style(.caption))
                        }
                    }
                    Spacer(minLength: 4)
                    if !item.children.isEmpty {
                        Text("\(leaves.done)/\(leaves.total)")
                            .font(Face.style(.caption))
                            .monospacedDigit()
                            .foregroundStyle(Ink.muted)
                    }
                    Image(systemName: "chevron.right")
                        .font(Face.style(.caption, .semibold))
                        .foregroundStyle(Ink.idle)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 14))
        .sensoryFeedback(.success, trigger: item.done) { _, new in new }
    }
}

// MARK: - My list, on Today

/// Your own list on the front page: type to add, tick, fold, open.
struct MyListCard: View {
    static let fieldID = "my-list-field"

    let project: Project
    let open: (FocusItem) -> Void
    let openAll: () -> Void
    var reveal: () -> Void = {}
    @State private var text = ""
    /// The row a dragged line is over.
    @State private var target: String? = nil
    @FocusState private var focused: Bool
    @Environment(\.modelContext) private var context

    var body: some View {
        let lines = project.openItems
        let rows = Outline.rows(lines)
        let tally = project.tally
        let tint = Ink.tint(project.tint)

        VStack(alignment: .leading, spacing: 8) {
            Button(action: openAll) {
                HStack(alignment: .firstTextBaseline) {
                    Text("My list")
                        .font(Face.at(12, .semibold))
                        .textCase(.uppercase)
                        .tracking(0.9)
                    Spacer()
                    Text(tally.total - tally.done == 0 ? "" : "\(tally.total - tally.done) open")
                        .font(Face.style(.footnote))
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(Face.style(.caption2, .bold))
                }
                .foregroundStyle(Ink.muted)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if case .line(let item, let depth) = row {
                            if index > 0 { Hairline(inset: 50 + CGFloat(depth) * 24) }
                            OutlineLine(item: item, tint: tint, depth: depth) { open(item) }
                                .padding(.leading, 6)
                                .padding(.trailing, 8)
                                // Lit while a dragged line is over it.
                                .background(target == row.id ? Ink.surface2 : Color.clear)
                                .contentShape(Rectangle())
                                .contextMenu {
                                    LineMenu(item: item, open: { open(item) }, addUnder: { open(item) })
                                }
                                .draggable(row.id) {
                                    Text(item.title)
                                        .font(Face.style(.body))
                                        .foregroundStyle(Ink.body)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(Ink.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .dropDestination(for: String.self) { dropped, _ in
                                    target = nil
                                    guard let id = dropped.first, let source = rows.firstIndex(where: { $0.id == id }),
                                          source != index else { return false }
                                    // Dropped on a line, it takes that line's place: above it
                                    // when dragged up, below it (and its sub-items) when dragged down.
                                    let gap = source < index ? Outline.end(of: index, in: rows) : index
                                    let moved = withAnimation(.snappy) { Outline.move(rows, from: source, to: gap) }
                                    if moved { Thud.play() }
                                    return moved
                                } isTargeted: { over in
                                    if over { target = row.id } else if target == row.id { target = nil }
                                }
                        }
                    }
                    if !rows.isEmpty { Hairline(inset: 50) }
                    HStack(spacing: 2) {
                        Button(action: add) {
                            Image(systemName: "plus")
                                .font(Face.at(17, .semibold))
                                .foregroundStyle(Ink.head)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add")
                        TextField("Add to my list", text: $text)
                            .focused($focused)
                            .submitLabel(.next)
                            .onSubmit(add)
                            .frame(minHeight: 48)
                    }
                    .padding(.leading, 6)
                    .padding(.trailing, 14)
                    .id(Self.fieldID)
                    .onChange(of: focused) { _, now in
                        guard now else { return }
                        Task {
                            try? await Task.sleep(for: .milliseconds(350))
                            reveal()
                        }
                    }
                }
            }
        }
    }

    private func add() {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            focused = false
            return
        }
        withAnimation(.snappy) {
            let item = FocusItem(title: title, order: project.nextOrder)
            context.insert(item)
            item.project = project
        }
        text = ""
        focused = true
        reveal()
    }
}
