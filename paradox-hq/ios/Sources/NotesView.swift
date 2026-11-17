import SwiftUI
import SwiftData
import Charts

// MARK: - The words in a note

nonisolated enum NoteText {
    /// A note's title is its first line with something in it.
    static func title(_ text: String) -> String {
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return "New note"
    }

    /// What follows the title, run together on one line.
    static func snippet(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.dropFirst().joined(separator: " ")
    }

    /// Every word typed in the search has to appear, in any order, in any case.
    static func matches(_ text: String, _ query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        return words.allSatisfy { text.localizedCaseInsensitiveContains($0) }
    }

    static func words(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    /// How many notes were started on each of the last `days` days, oldest first.
    static func perDay(_ dates: [Date], days: Int, now: Date, calendar: Calendar) -> [Bucket] {
        let today = calendar.startOfDay(for: now)
        var counts: [Date: Int] = [:]
        for date in dates { counts[calendar.startOfDay(for: date), default: 0] += 1 }
        return (0..<days).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: today).map { Bucket(date: $0, amount: counts[$0] ?? 0) }
        }
    }
}

// MARK: - The list

struct NotesView: View {
    @Query(sort: \Note.edited, order: .reverse) private var notes: [Note]
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var search = ""
    @State private var path: [Note] = []
    /// Only this project's notes, when one is chosen.
    @State private var only: Project? = nil

    var body: some View {
        let filed = projects.filter { project in notes.contains { $0.project === project } }
        let shown = notes.filter { note in
            NoteText.matches(note.text, search) && (only == nil || note.project === only)
        }
        let pinned = shown.filter(\.pinned)
        let rest = shown.filter { !$0.pinned }

        NavigationStack(path: $path) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Heading(title: "Notes", detail: notes.isEmpty ? "" : "\(notes.count)")
                        if !notes.isEmpty {
                            NotesChart(dates: notes.map(\.created))
                            SearchField(text: $search)
                            if !filed.isEmpty {
                                ProjectChips(projects: filed, only: $only)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 6, trailing: 4))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if notes.isEmpty {
                    Section {
                        Text("Nothing written yet.")
                            .foregroundStyle(Ink.muted)
                            .listRowBackground(Ink.surface)
                    }
                } else if shown.isEmpty {
                    Section {
                        Text("Nothing matches.")
                            .foregroundStyle(Ink.muted)
                            .listRowBackground(Ink.surface)
                    }
                }

                if !pinned.isEmpty {
                    Section {
                        ForEach(pinned) { NoteRow(note: $0) }
                    } header: {
                        label("Pinned")
                    }
                }
                if !rest.isEmpty {
                    Section {
                        ForEach(rest) { NoteRow(note: $0) }
                    } header: {
                        if !pinned.isEmpty { label("Everything else") }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(Ink.ground)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Note.self) { NoteEditor(note: $0) }
            .safeAreaInset(edge: .bottom, alignment: .trailing) {
                Button(action: write) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 58, height: 58)
                        .background(.white, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New note")
                .padding(.trailing, 18)
                .padding(.bottom, 10)
            }
            .onAppear {
                // The cloud build opens straight into a note to photograph the editor.
                if Launch.screen == "note", path.isEmpty, let first = notes.first {
                    path = [first]
                }
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Ink.muted)
            .textCase(nil)
    }

    private func write() {
        let note = Note(project: only)
        context.insert(note)
        search = ""
        path = [note]
    }
}

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Ink.muted)
            TextField("Search", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Ink.idle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background(Ink.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// All notes, or one project's.
struct ProjectChips: View {
    let projects: [Project]
    @Binding var only: Project?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip("All", color: .white, on: only == nil) { only = nil }
                ForEach(projects) { project in
                    chip(project.name, color: Color(hex: UInt32(project.tint)), on: only === project) {
                        only = only === project ? nil : project
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: only?.persistentModelID)
    }

    private func chip(_ title: String, color: Color, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).lineLimit(1)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(on ? Color.black : Ink.body)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(on ? Color.white : Ink.surface2, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct NoteRow: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var context

    var body: some View {
        let snippet = NoteText.snippet(note.text)
        NavigationLink(value: note) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if note.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(Ink.violet)
                    }
                    Text(NoteText.title(note.text))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Ink.body)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(note.edited, format: Self.stamp(note.edited))
                        .foregroundStyle(Ink.muted)
                    if let project = note.project {
                        Text(project.name)
                            .foregroundStyle(Color(hex: UInt32(project.tint)))
                    }
                    if !snippet.isEmpty {
                        Text(snippet)
                            .foregroundStyle(Ink.muted)
                            .lineLimit(1)
                    }
                }
                .font(.subheadline)
                .lineLimit(1)
            }
            .padding(.vertical, 3)
        }
        .listRowBackground(Ink.surface)
        .listRowSeparatorTint(Ink.line)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                context.delete(note)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                withAnimation(.snappy) { note.pinned.toggle() }
            } label: {
                Label(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin")
            }
            .tint(Ink.violet)
        }
    }

    /// The time for a note touched today, the date for anything older.
    static func stamp(_ date: Date) -> Date.FormatStyle {
        Calendar.current.isDateInToday(date)
            ? .dateTime.hour().minute()
            : .dateTime.day().month(.abbreviated)
    }
}

/// Notes started per day over the last 30. Drag along it to read each day off.
struct NotesChart: View {
    let dates: [Date]
    @State private var touched: Date? = nil

    var body: some View {
        let bars = NoteText.perDay(dates, days: 30, now: .now, calendar: .current)
        let picked = touched.flatMap { Ledger.pick(bars, at: $0) }
        let total = bars.reduce(0) { $0 + $1.amount }
        let lit = picked?.date ?? bars.last?.date

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(picked.map { Self.count($0.amount) } ?? "\(Self.count(total)) in 30 days")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(picked == nil ? Ink.muted : Color.white)
                    .monospacedDigit()
                Spacer(minLength: 8)
                if let picked {
                    Text(picked.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.footnote)
                        .foregroundStyle(.white)
                }
            }
            Chart(bars) { bar in
                BarMark(x: .value("Day", bar.date, unit: .day),
                        y: .value("Notes", max(Double(bar.amount), 0.12)))
                    .cornerRadius(2)
                    .foregroundStyle(bar.date == lit ? Color.white : Ink.violet.opacity(bar.amount == 0 ? 0.25 : 0.7))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartXSelection(value: $touched)
            .sensoryFeedback(.selection, trigger: picked?.date)
            .frame(height: 44)
            .accessibilityLabel("Notes written per day")
        }
    }

    nonisolated static func count(_ n: Int) -> String {
        n == 1 ? "1 note" : "\(n) notes"
    }
}

// MARK: - Writing

/// One note, the whole screen. The first line is its title. It saves as you type.
struct NoteEditor: View {
    @Bindable var note: Note
    @Query(sort: \Project.order) private var projects: [Project]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FocusState private var typing: Bool
    @State private var deleting = false
    @State private var madeToDo: String? = nil

    /// A note filed under a project makes its to-do there; any other goes on your own list.
    private var toDoTarget: Project? { note.project ?? projects.first(where: \.isPersonal) }

    private var toDoLabel: String {
        "Add to \(toDoTarget?.name ?? "my list")"
    }

    /// The note's title becomes a to-do, and the rest of it the to-do's note.
    private func makeToDo() {
        guard let target = toDoTarget else { return }
        let item = FocusItem(title: NoteText.title(note.text), notes: NoteText.snippet(note.text),
                             order: target.nextOrder)
        context.insert(item)
        item.project = target
        withAnimation(.snappy) { madeToDo = target.name }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.snappy) { madeToDo = nil }
        }
    }

    var body: some View {
        TextEditor(text: $note.text)
            .focused($typing)
            .font(.body)
            .foregroundStyle(Ink.body)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 12)
            .background(Ink.ground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(note.edited, format: .dateTime.day().month(.abbreviated).hour().minute())
                        Text(NoteText.words(note.text) == 1 ? "1 word" : "\(NoteText.words(note.text)) words")
                    }
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Ink.muted)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        note.pinned.toggle()
                    } label: {
                        Image(systemName: note.pinned ? "pin.fill" : "pin")
                    }
                    .accessibilityLabel(note.pinned ? "Unpin" : "Pin")
                    Menu {
                        Picker("Project", selection: $note.project) {
                            Text("No project").tag(nil as Project?)
                            ForEach(projects) { project in
                                Text(project.name).tag(project as Project?)
                            }
                        }
                        Button(toDoLabel, systemImage: "checklist") { makeToDo() }
                            .disabled(note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        ShareLink(item: note.text) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = true }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More")
                    if typing {
                        Button("Done") { typing = false }
                            .fontWeight(.semibold)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let madeToDo {
                    Text("Added to \(madeToDo)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 40)
                        .background(.white, in: Capsule())
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sensoryFeedback(.success, trigger: madeToDo) { _, new in new != nil }
            .confirmationDialog("Delete this note?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    context.delete(note)
                    dismiss()
                }
            }
            .onChange(of: note.text) { _, _ in
                note.edited = .now
            }
            .onAppear {
                if note.text.isEmpty { typing = true }
            }
            .onDisappear {
                // A note that was opened and never written in doesn't stay.
                if !note.isDeleted, note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    context.delete(note)
                }
            }
    }
}

/// The notes filed under one project, shown at the foot of its page.
struct ProjectNotes: View {
    let project: Project
    let write: () -> Void

    var body: some View {
        let notes = project.notes.sorted { $0.edited > $1.edited }
        Section {
            ForEach(notes) { NoteRow(note: $0) }
            Button(action: write) {
                Label("New note", systemImage: "square.and.pencil")
                    .foregroundStyle(.white)
            }
            .listRowBackground(Ink.surface)
            .listRowSeparatorTint(Ink.line)
        } header: {
            Text("Notes")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Ink.muted)
                .textCase(nil)
        }
    }
}
