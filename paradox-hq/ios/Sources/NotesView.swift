import SwiftUI
import SwiftData
import Charts

// MARK: - The words in a note

nonisolated enum NoteText {
    /// A note's title is its first line with something in it.
    /// The words alone: a heading's #, a bullet and a link's address are not part of a title.
    static func title(_ text: String) -> String {
        for line in text.split(whereSeparator: \.isNewline) {
            let words = NoteMarkup.plain(String(line))
            if !words.isEmpty { return words }
        }
        return "New note"
    }

    /// What follows the title, run together on one line.
    static func snippet(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { NoteMarkup.plain(String($0)) }
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
    /// Whether the Done list at the bottom is open. Remembered.
    @AppStorage("notes-show-done") private var showDone = true
    /// The section being made or changed.
    @State private var section: SectionDraft? = nil

    var body: some View {
        let shown = notes.filter { note in
            NoteText.matches(note.text, search) && (only == nil || note.project === only)
        }
        let pinned = shown.filter { $0.pinned && !$0.done }
        let rest = shown.filter { !$0.pinned && !$0.done }
        let done = Note.doneOrder(shown)

        NavigationStack(path: $path) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Heading(title: "Notes", detail: notes.isEmpty ? "" : "\(notes.count)")
                        if !notes.isEmpty {
                            NotesChart(dates: notes.map(\.created))
                            SearchField(text: $search)
                        }
                        // Every section, with or without notes, so a new one can be written into.
                        ProjectChips(projects: projects, only: $only,
                                     add: { section = SectionDraft(project: nil) },
                                     edit: { section = SectionDraft(project: $0) })
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
                        Text(only != nil && search.isEmpty ? "Nothing here yet." : "Nothing matches.")
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
                if !done.isEmpty {
                    Section {
                        if showDone {
                            ForEach(done) { NoteRow(note: $0) }
                        }
                    } header: {
                        // Tap to fold the whole Done list away, and again to bring it back.
                        Button {
                            withAnimation(.snappy) { showDone.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Text("Done")
                                Text("\(done.count)")
                                    .monospacedDigit()
                                Image(systemName: showDone ? "chevron.down" : "chevron.right")
                                    .font(Face.style(.caption2, .bold))
                                Spacer()
                            }
                            .font(Face.at(12, .semibold)).textCase(.uppercase).tracking(0.9)
                            .foregroundStyle(Ink.muted)
                            .frame(minHeight: 30)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showDone ? "Hide done notes" : "Show done notes")
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: showDone)
            .listStyle(.insetGrouped)
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .statusBarFade()
            .background(Ink.ground)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Note.self) { NoteEditor(note: $0) }
            .safeAreaInset(edge: .bottom, alignment: .trailing) {
                Button(action: write) {
                    Image(systemName: "square.and.pencil")
                        .font(Face.at(20, .semibold))
                        .foregroundStyle(Ink.buttonInk)
                        .frame(width: 58, height: 58)
                        .background(Ink.button, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New note")
                .padding(.trailing, 18)
                .padding(.bottom, 10)
            }
            .onChange(of: projects.map(\.persistentModelID)) { _, ids in
                // A chosen section that has been deleted lets go.
                if let chosen = only, !ids.contains(chosen.persistentModelID) { only = nil }
            }
            .sheet(item: $section) { draft in
                SectionEditor(project: draft.project) { made in
                    withAnimation(.snappy) { only = made }
                }
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
            .font(Face.at(12, .semibold)).textCase(.uppercase).tracking(0.9)
            .foregroundStyle(Ink.muted)
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

/// A section being made (no project yet) or changed.
struct SectionDraft: Identifiable {
    let id = UUID()
    var project: Project?
}

/// All notes, or one section's. A section is a project: it has a name, a colour, and
/// (in To-do) a list of its own. The plus makes one; the pencil changes the chosen one.
struct ProjectChips: View {
    let projects: [Project]
    @Binding var only: Project?
    var add: () -> Void = {}
    var edit: (Project) -> Void = { _ in }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip("All", color: Ink.head, on: only == nil) { only = nil }
                ForEach(projects) { project in
                    chip(project.name, color: Ink.tint(project.tint), on: only === project) {
                        only = only === project ? nil : project
                    }
                    .contextMenu {
                        Button("Rename or recolour", systemImage: "pencil") { edit(project) }
                    }
                }
                if let chosen = only {
                    round("pencil", "Change \(chosen.name)") { edit(chosen) }
                }
                round("plus", "New section", action: add)
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
            .font(Face.style(.subheadline, .medium))
            .foregroundStyle(on ? Ink.buttonInk : Ink.body)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(on ? Ink.button : Ink.surface2, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func round(_ symbol: String, _ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Face.style(.subheadline, .semibold))
                .foregroundStyle(Ink.body)
                .frame(width: 34, height: 34)
                .background(Ink.surface2, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }
}

/// A section's name and colour. Making one makes a project, so it has a to-do list as well.
struct SectionEditor: View {
    let project: Project?
    var made: (Project) -> Void = { _ in }
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var all: [Project]
    @State private var name = ""
    @State private var tint = 0xA78BFA
    @State private var confirming = false
    @FocusState private var naming: Bool

    static let tints = [0xFFFFFF, 0xA78BFA, 0x5FD7AF, 0xFFD27A, 0xED4E3B, 0x6FB1FF,
                        0xF472B6, 0xFF9F5A, 0x5EEAD4, 0xC4B5FD, 0xE5E54B, 0x9CA3AF]

    /// A picked colour as the six-figure number a project keeps.
    static func hex(_ color: Color) -> Int {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func part(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return part(red) << 16 | part(green) << 8 | part(blue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($naming)
                }
                Section("Colour") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                        ForEach(Self.tints, id: \.self) { value in
                            Button {
                                tint = value
                            } label: {
                                Circle()
                                    .fill(Ink.tint(value))
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Circle().strokeBorder(Ink.head, lineWidth: tint == value ? 2 : 0).padding(-5)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Colour")
                            .accessibilityAddTraits(tint == value ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 8)
                    ColorPicker("Any colour", selection: Binding(get: { Ink.tint(tint) }, set: { tint = Self.hex($0) }),
                                supportsOpacity: false)
                }
                if let project, !project.isPersonal {
                    Section {
                        Button("Delete section", role: .destructive) { confirming = true }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(project == nil ? "New section" : "Section")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Delete \(name) and its to-do list? Its notes are kept.",
                                isPresented: $confirming, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    let doomed = project
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        doomed?.remove(from: context)
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: tint)
            .onAppear {
                if let project {
                    name = project.name
                    tint = project.tint
                } else {
                    naming = true
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let target: Project
        if let project {
            target = project
        } else {
            target = Project(name: "", order: (all.map(\.order).max() ?? -1) + 1)
            context.insert(target)
        }
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.tint = tint
        if project == nil { made(target) }
        dismiss()
    }
}

struct NoteRow: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hits = 0

    /// The note just marked done. Its row is drawn afresh in the Done list, and
    /// that row is the one whose tick should land.
    static var landing: PersistentIdentifier? = nil

    var body: some View {
        let snippet = NoteText.snippet(note.text)
        NavigationLink(value: note) {
            HStack(spacing: 10) {
                if note.done {
                    // The tick undoes it: tap and the note goes back where it was.
                    Button(action: toggleDone) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(Face.at(22, .semibold))
                            .foregroundStyle(Ink.ok)
                            // Hit stop: it swells, holds for a few frames, then settles.
                            .keyframeAnimator(initialValue: CGFloat(1), trigger: hits) { view, scale in
                                view.scaleEffect(scale)
                            } keyframes: { _ in
                                KeyframeTrack {
                                    LinearKeyframe(1.42, duration: 0.06)
                                    LinearKeyframe(1.42, duration: 0.10)
                                    SpringKeyframe(1.0, duration: 0.32, spring: .bouncy)
                                }
                            }
                            .frame(minWidth: 30, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Not done")
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if note.pinned {
                            Image(systemName: "pin.fill")
                                .font(Face.style(.caption2))
                                .foregroundStyle(Ink.violet)
                        }
                        Text(NoteText.title(note.text))
                            .font(Face.style(.body, .semibold))
                            .strikethrough(note.done)
                            .foregroundStyle(note.done ? Ink.muted : Ink.body)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Text(note.edited, format: Self.stamp(note.edited))
                            .foregroundStyle(Ink.muted)
                        if let project = note.project {
                            Text(project.name)
                                .foregroundStyle(Ink.tint(project.tint))
                        }
                        if !snippet.isEmpty {
                            Text(snippet)
                                .foregroundStyle(Ink.muted)
                                .lineLimit(1)
                        }
                    }
                    .font(Face.style(.subheadline))
                    .lineLimit(1)
                }
                .padding(.vertical, 3)
            }
        }
        .listRowBackground(Ink.surface)
        .listRowSeparatorTint(Ink.line)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                withAnimation {
                    context.delete(note)
                    try? context.save()
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        // Swipe right for what can be done with a note. A full swipe is Done (or its undoing).
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: toggleDone) {
                Label(note.done ? "Not done" : "Done", systemImage: note.done ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(Ink.ok)
            Button {
                withAnimation(.snappy) { note.pinned.toggle() }
            } label: {
                Label(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin")
            }
            .tint(Ink.violet)
        }
        .onAppear {
            guard Self.landing == note.persistentModelID else { return }
            Self.landing = nil
            guard !reduceMotion else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(280))
                hits += 1
            }
        }
    }

    private func toggleDone() {
        let finishing = !note.done
        if finishing {
            Self.landing = note.persistentModelID
            Thud.success()
        } else {
            Thud.play()
        }
        withAnimation(.snappy) { note.set(done: finishing) }
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
                    .font(Face.style(.footnote, .semibold))
                    .foregroundStyle(picked == nil ? Ink.muted : Ink.head)
                    .monospacedDigit()
                Spacer(minLength: 8)
                if let picked {
                    Text(picked.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(Face.style(.footnote))
                        .foregroundStyle(Ink.head)
                }
            }
            Chart(bars) { bar in
                BarMark(x: .value("Day", bar.date, unit: .day),
                        y: .value("Notes", max(Double(bar.amount), 0.12)))
                    .cornerRadius(2)
                    .foregroundStyle(bar.date == lit ? Ink.head : Ink.violet.opacity(bar.amount == 0 ? 0.25 : 0.7))
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
    @State private var typing = false
    @State private var deleting = false
    @State private var madeToDo: String? = nil

    private var isEmpty: Bool { note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// My list first, then the projects in their own order.
    private var lists: [Project] { projects.filter(\.isPersonal) + projects.filter { !$0.isPersonal } }

    /// The note's title becomes a to-do on that list, and the rest of it the to-do's note.
    private func makeToDo(on target: Project) {
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
        MarkupEditor(text: $note.text, typing: $typing)
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
                    .font(Face.style(.caption2))
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
                        Button(note.done ? "Not done" : "Done", systemImage: note.done ? "arrow.uturn.backward" : "checkmark") {
                            note.set(done: !note.done)
                        }
                        // Onto a to-do list: yours, or any project's.
                        Menu {
                            ForEach(lists) { list in
                                Button(list.name, systemImage: list.isPersonal ? "person" : "folder") { makeToDo(on: list) }
                            }
                        } label: {
                            Label("Add to a to-do list", systemImage: "checklist")
                        }
                        .disabled(isEmpty)
                        // Under a project: the note shows on that project's page.
                        Menu {
                            Picker("Project", selection: $note.project) {
                                Text("No project").tag(nil as Project?)
                                ForEach(projects) { project in
                                    Text(project.name).tag(project as Project?)
                                }
                            }
                        } label: {
                            Label(note.project.map { "Project: \($0.name)" } ?? "Add to a project", systemImage: "folder")
                        }
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
                        .font(Face.style(.subheadline, .semibold))
                        .foregroundStyle(Ink.buttonInk)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 40)
                        .background(Ink.button, in: Capsule())
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sensoryFeedback(.success, trigger: madeToDo) { _, new in new != nil }
            .confirmationDialog("Delete this note?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    // Leave the note first, so the editor never draws one that's gone.
                    let doomed = note
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        context.delete(doomed)
                        try? context.save()
                    }
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
        let notes = project.notes.filter { !$0.done }.sorted { $0.edited > $1.edited } + Note.doneOrder(project.notes)
        Section {
            ForEach(notes) { NoteRow(note: $0) }
            Button(action: write) {
                Label("New note", systemImage: "square.and.pencil")
                    .foregroundStyle(Ink.head)
            }
            .listRowBackground(Ink.surface)
            .listRowSeparatorTint(Ink.line)
        } header: {
            Text("Notes")
                .font(Face.at(12, .semibold)).textCase(.uppercase).tracking(0.9)
                .foregroundStyle(Ink.muted)
        }
    }
}
