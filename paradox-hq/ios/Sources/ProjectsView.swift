import SwiftUI
import SwiftData

/// The To-do tab: your own list, and beside it every project being built.
struct ProjectsView: View {
    @Environment(FeedSync.self) private var feed
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var adding = false
    @State private var path = NavigationPath()
    @AppStorage("lists-pane") private var pane: Pane = .todo

    enum Pane: String, CaseIterable, Identifiable {
        case todo = "To-do", projects = "Projects"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if pane == .todo, let mine = projects.first(where: \.isPersonal) {
                    ProjectDetail(project: mine)
                } else {
                    projectList
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Show", selection: $pane.animation(.snappy)) {
                    ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .background(Ink.ground)
                .sensoryFeedback(.selection, trigger: pane)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Project.self) { ProjectDetail(project: $0) }
            .navigationDestination(for: Note.self) { NoteEditor(note: $0) }
            .sheet(isPresented: $adding) { ProjectEditor(project: nil) }
            .onAppear {
                // The cloud build opens straight into the first project to photograph it.
                if Launch.screen == "project", path.isEmpty, let first = projects.first(where: { !$0.isPersonal }) {
                    pane = .projects
                    path.append(first)
                }
            }
        }
    }

    /// A list, so a project can be held and dragged to a new place like any line.
    private var projectList: some View {
        let shown = projects.filter { !$0.isPersonal }
        return List {
            Heading(title: "Projects", detail: summary)
                .bareRow(top: 8)
            ForEach(shown) { project in
                Button {
                    path.append(project)
                } label: {
                    ProjectCard(project: project)
                }
                .buttonStyle(.plain)
                .bareRow()
            }
            .onMove { from, to in
                var row = shown
                row.move(fromOffsets: from, toOffset: to)
                // "My list" keeps its place ahead of them all (its order is below zero).
                for (index, project) in row.enumerated() where project.order != index { project.order = index }
                Thud.play()
            }
            Button {
                adding = true
            } label: {
                Label("New project", systemImage: "plus")
            }
            .buttonStyle(QuietButtonStyle())
            .bareRow()
            if feed.isSet, !feed.status.isEmpty {
                Text("Claude: \(feed.status)")
                    .font(.footnote)
                    .foregroundStyle(feed.failed ? Ink.hazard : Ink.muted)
                    .padding(.horizontal, 4)
                    .bareRow(bottom: 28)
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .statusBarFade()
        .background(Ink.ground)
        .refreshable { await feed.pull(into: context) }
    }

    private var summary: String {
        let open = projects.filter { !$0.isPersonal }.reduce(0) { $0 + $1.tally.total - $1.tally.done }
        return open == 0 ? "All done" : "\(open) open"
    }
}

private extension View {
    /// A list row with nothing of the list's own showing: the page's gutters, no fill, no line.
    func bareRow(top: CGFloat = 8, bottom: CGFloat = 8) -> some View {
        self
            .listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

struct ProjectCard: View {
    let project: Project

    var body: some View {
        let tally = project.tally
        let tint = Ink.tint(project.tint)
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: project.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 40, height: 40)
                        .background(Ink.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Ink.head)
                            .lineLimit(1)
                        if !project.summary.isEmpty {
                            Text(project.summary)
                                .font(.caption)
                                .foregroundStyle(Ink.muted)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 4)
                    if !project.stage.isEmpty {
                        Pill(text: project.stage, color: tint)
                    }
                }
                Meter(done: tally.done, total: tally.total, color: tint)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let next = project.openItems.first {
                        Text("Next")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Ink.muted)
                        Text(next.title)
                            .font(.subheadline)
                            .foregroundStyle(Ink.body)
                            .lineLimit(1)
                    } else {
                        Text(tally.total == 0 ? "Nothing listed yet" : "All done")
                            .font(.subheadline)
                            .foregroundStyle(Ink.muted)
                    }
                    Spacer(minLength: 4)
                    Text("\(tally.done)/\(tally.total)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Ink.muted)
                }
            }
        }
    }
}

/// One project: its Focus list, tickable, editable, with sub-items under any line.
struct ProjectDetail: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var opened: FocusItem? = nil
    @State private var editingProject = false
    @State private var drafting: FocusItem? = nil
    @State private var showDone = false
    @State private var freshNote: Note? = nil

    var body: some View {
        let tint = Ink.tint(project.tint)
        let open = project.openItems
        let done = project.doneItems
        let tally = project.tally

        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Heading(title: project.name, detail: "\(tally.done)/\(tally.total)")
                    if !project.summary.isEmpty {
                        Text(project.summary)
                            .font(.subheadline)
                            .foregroundStyle(Ink.muted)
                    }
                    Meter(done: tally.done, total: tally.total, color: tint)
                    HStack(spacing: 8) {
                        if !project.stage.isEmpty {
                            Pill(text: project.stage, color: tint)
                        }
                        if let url = URL(string: project.link), !project.link.isEmpty {
                            Button {
                                openURL(url)
                            } label: {
                                Pill(text: "\(url.host() ?? "Open") ↗", color: Ink.body)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 8, trailing: 4))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                if open.isEmpty {
                    Text(done.isEmpty ? "Nothing here yet. Add the first line below." : "All done.")
                        .foregroundStyle(Ink.muted)
                        .listRowBackground(Ink.surface)
                }
                OutlineSection(lines: open, tint: tint, drafting: $drafting) { opened = $0 }
            } header: {
                Text(project.isPersonal ? "To do" : "Focus")
                    .font(.system(size: 12, weight: .semibold)).textCase(.uppercase).tracking(0.9)
                    .foregroundStyle(Ink.muted)
            }

            ProjectNotes(project: project) {
                let note = Note(project: project)
                context.insert(note)
                freshNote = note
            }

            if !done.isEmpty {
                Section {
                    if showDone {
                        ForEach(done) { item in
                            OutlineLine(item: item, tint: tint, showsFold: false) { opened = item }
                                .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 10))
                                .listRowBackground(Ink.surface)
                                .listRowSeparatorTint(Ink.line)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        withAnimation { item.remove(from: context) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                } header: {
                    Button {
                        withAnimation(.snappy) { showDone.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Done")
                            Text("\(done.count)")
                                .monospacedDigit()
                            Image(systemName: showDone ? "chevron.down" : "chevron.right")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.system(size: 12, weight: .semibold)).textCase(.uppercase).tracking(0.9)
                        .foregroundStyle(Ink.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Ink.ground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editingProject = true }
            }
        }
        .safeAreaInset(edge: .bottom) {
            AddBar(project: project, tint: tint)
        }
        .navigationDestination(item: $freshNote) { NoteEditor(note: $0) }
        .navigationDestination(item: $opened) { ItemPage(item: $0, tint: tint) }
        .sheet(isPresented: $editingProject) {
            ProjectEditor(project: project) { dismiss() }
        }
    }
}

/// The entry bar under a project: type, return, type the next one.
struct AddBar: View {
    let project: Project
    let tint: Color
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(spacing: 8) {
            TextField("Add to \(project.name)", text: $text)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(add)
                .padding(.horizontal, 16)
                .frame(minHeight: 46)
                .background(Ink.surface2, in: Capsule())
            Button(action: add) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Ink.buttonInk)
                    .frame(width: 46, height: 46)
                    .background(Ink.button, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Ink.ground.opacity(0.92))
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
    }
}

/// Make a project, or change one.
struct ProjectEditor: View {
    let project: Project?
    var deleted: () -> Void = {}
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var all: [Project]
    @State private var name = ""
    @State private var summary = ""
    @State private var stage = ""
    @State private var link = ""
    @State private var symbol = "square.stack.3d.up"
    @State private var tint = 0xA78BFA
    @State private var confirming = false

    private static let symbols = ["square.stack.3d.up", "scope", "star", "building.columns", "macwindow", "iphone",
                                  "globe", "film", "pencil.and.outline", "cart", "music.note", "bolt"]
    private static let tints = [0xFFFFFF, 0xA78BFA, 0x5FD7AF, 0xFFD27A, 0xED4E3B, 0x6FB1FF]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("What it is", text: $summary, axis: .vertical)
                    TextField("Stage or version", text: $stage)
                    TextField("Link", text: $link)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section("Symbol") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Self.symbols, id: \.self) { name in
                            Button {
                                symbol = name
                            } label: {
                                Image(systemName: name)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(symbol == name ? Ink.buttonInk : Ink.body)
                                    .frame(width: 44, height: 44)
                                    .background(symbol == name ? Ink.button : Ink.surface2,
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(name)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Colour") {
                    HStack(spacing: 14) {
                        ForEach(Self.tints, id: \.self) { value in
                            Button {
                                tint = value
                            } label: {
                                Circle()
                                    .fill(Ink.tint(value))
                                    .frame(width: 30, height: 30)
                                    .padding(4)
                                    .overlay {
                                        Circle().strokeBorder(Ink.head, lineWidth: tint == value ? 2 : 0)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Colour")
                        }
                    }
                    .padding(.vertical, 4)
                }
                if let project, !project.isPersonal {
                    Section {
                        Button("Delete project", role: .destructive) { confirming = true }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(project == nil ? "New project" : "Project")
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
            .confirmationDialog("Delete this project and everything in it?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    // Close the editor and leave the project's page before it goes.
                    let doomed = project
                    dismiss()
                    deleted()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        doomed?.remove(from: context)
                    }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let project else { return }
        name = project.name
        summary = project.summary
        stage = project.stage
        link = project.link
        symbol = project.symbol
        tint = project.tint
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
        target.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        target.stage = stage.trimmingCharacters(in: .whitespacesAndNewlines)
        target.link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        target.symbol = symbol
        target.tint = tint
        dismiss()
    }
}
