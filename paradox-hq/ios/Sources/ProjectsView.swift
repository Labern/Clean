import SwiftUI
import SwiftData

/// Everything being built, and what each one needs next.
struct ProjectsView: View {
    @Environment(FeedSync.self) private var feed
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var adding = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Heading(title: "Projects", detail: summary)
                    ForEach(projects) { project in
                        NavigationLink(value: project) {
                            ProjectCard(project: project)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        adding = true
                    } label: {
                        Label("New project", systemImage: "plus")
                    }
                    .buttonStyle(QuietButtonStyle())
                    if feed.isSet, !feed.status.isEmpty {
                        Text("Claude: \(feed.status)")
                            .font(.footnote)
                            .foregroundStyle(feed.failed ? Ink.hazard : Ink.muted)
                            .padding(.horizontal, 4)
                    }
                }
                .page()
            }
            .scrollIndicators(.hidden)
            .background(Ink.ground)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await feed.pull(into: context) }
            .navigationDestination(for: Project.self) { ProjectDetail(project: $0) }
            .navigationDestination(for: Note.self) { NoteEditor(note: $0) }
            .sheet(isPresented: $adding) { ProjectEditor(project: nil) }
            .onAppear {
                // The cloud build opens straight into the first project to photograph it.
                if Launch.screen == "project", path.isEmpty, let first = projects.first(where: { !$0.isPersonal }) {
                    path.append(first)
                }
            }
        }
    }

    private var summary: String {
        let open = projects.reduce(0) { $0 + $1.tally.total - $1.tally.done }
        return open == 0 ? "All done" : "\(open) open"
    }
}

struct ProjectCard: View {
    let project: Project

    var body: some View {
        let tally = project.tally
        let tint = Color(hex: UInt32(project.tint))
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
                            .foregroundStyle(.white)
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
    @State private var editing: FocusItem? = nil
    @State private var editingProject = false
    @State private var parentForNew: FocusItem? = nil
    @State private var subDraft = ""
    @State private var showDone = false
    @State private var freshNote: Note? = nil

    var body: some View {
        let tint = Color(hex: UInt32(project.tint))
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
                ForEach(open) { item in
                    FocusRow(item: item, tint: tint, child: false, edit: { editing = item }, addUnder: { ask(item) })
                    ForEach(item.sortedChildren) { child in
                        FocusRow(item: child, tint: tint, child: true, edit: { editing = child }, addUnder: nil)
                    }
                }
            } header: {
                Text("Focus")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Ink.muted)
                    .textCase(nil)
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
                            FocusRow(item: item, tint: tint, child: false, edit: { editing = item }, addUnder: nil)
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
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Ink.muted)
                        .textCase(nil)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
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
        .sheet(item: $editing) { ItemEditor(item: $0, tint: tint) }
        .sheet(isPresented: $editingProject) {
            ProjectEditor(project: project) { dismiss() }
        }
        .alert("Add under \(parentForNew?.title ?? "")", isPresented: asking) {
            TextField("Sub-item", text: $subDraft)
            Button("Add") { addSub() }
            Button("Cancel", role: .cancel) { subDraft = "" }
        }
    }

    private var asking: Binding<Bool> {
        Binding(get: { parentForNew != nil }, set: { if !$0 { parentForNew = nil } })
    }

    private func ask(_ item: FocusItem) {
        subDraft = ""
        parentForNew = item
    }

    private func addSub() {
        let title = subDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            subDraft = ""
            parentForNew = nil
        }
        guard !title.isEmpty, let parent = parentForNew else { return }
        withAnimation(.snappy) {
            let child = FocusItem(title: title, order: parent.nextOrder)
            context.insert(child)
            child.parent = parent
            // A finished line with something new under it isn't finished.
            if parent.done {
                parent.done = false
                parent.completed = nil
            }
        }
    }
}

struct FocusRow: View {
    @Bindable var item: FocusItem
    let tint: Color
    let child: Bool
    let edit: () -> Void
    let addUnder: (() -> Void)?
    @Environment(\.modelContext) private var context

    var body: some View {
        let children = item.children
        HStack(spacing: 2) {
            Button {
                withAnimation(.snappy.delay(item.done ? 0 : 0.34)) { item.set(done: !item.done) }
            } label: {
                Tick(done: item.done, color: tint, size: child ? 20 : 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? "Reopen" : "Tick")

            Button(action: edit) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(child ? .subheadline : .body)
                            .strikethrough(item.done)
                            .foregroundStyle(item.done ? Ink.muted : Ink.body)
                            .multilineTextAlignment(.leading)
                        if !item.notes.isEmpty, !child {
                            Text(item.notes)
                                .font(.caption)
                                .foregroundStyle(Ink.muted)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 4)
                    if !children.isEmpty {
                        Text("\(children.filter(\.done).count)/\(children.count)")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Ink.muted)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, child ? 30 : 0)
        .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 14))
        .listRowBackground(Ink.surface)
        .listRowSeparatorTint(Ink.line)
        .sensoryFeedback(.success, trigger: item.done) { _, new in new }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                context.delete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            if let addUnder {
                Button(action: addUnder) {
                    Label("Sub-item", systemImage: "text.badge.plus")
                }
                .tint(Ink.violet)
            }
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil", action: edit)
            if let addUnder {
                Button("Add sub-item", systemImage: "text.badge.plus", action: addUnder)
            }
            Button("Move to top", systemImage: "arrow.up.to.line") { moveToTop() }
            Button("Delete", systemImage: "trash", role: .destructive) {
                withAnimation { context.delete(item) }
            }
        }
    }

    private func moveToTop() {
        let siblings = item.parent?.children ?? item.project?.items ?? []
        let lowest = siblings.map(\.order).min() ?? 0
        withAnimation(.snappy) { item.order = lowest - 1 }
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
                    .foregroundStyle(.black)
                    .frame(width: 46, height: 46)
                    .background(.white, in: Circle())
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
        guard !title.isEmpty else { return }
        withAnimation(.snappy) {
            let item = FocusItem(title: title, order: project.nextOrder)
            context.insert(item)
            item.project = project
        }
        text = ""
        focused = true
    }
}

/// Edit one line: its wording, a note, and the sub-items under it.
struct ItemEditor: View {
    @Bindable var item: FocusItem
    let tint: Color
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var addingSub: Bool

    var body: some View {
        let children = item.sortedChildren
        NavigationStack {
            Form {
                Section {
                    TextField("What needs doing", text: $item.title, axis: .vertical)
                    TextField("Note", text: $item.notes, axis: .vertical)
                        .lineLimit(1...6)
                        .foregroundStyle(Ink.muted)
                }
                if item.parent == nil {
                    Section("Sub-items") {
                        ForEach(children) { child in
                            SubItemRow(item: child, tint: tint)
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(children[index]) }
                        }
                        TextField("Add a sub-item", text: $draft)
                            .focused($addingSub)
                            .submitLabel(.done)
                            .onSubmit(addSub)
                    }
                }
                Section {
                    Toggle("Done", isOn: Binding(get: { item.done }, set: { item.set(done: $0) }))
                    Button("Delete", role: .destructive) {
                        context.delete(item)
                        dismiss()
                    }
                }
            }
            .navigationTitle(item.parent == nil ? "Line" : "Sub-item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func addSub() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let child = FocusItem(title: title, order: item.nextOrder)
        context.insert(child)
        child.parent = item
        if item.done {
            item.done = false
            item.completed = nil
        }
        draft = ""
        addingSub = true
    }
}

struct SubItemRow: View {
    @Bindable var item: FocusItem
    let tint: Color

    var body: some View {
        HStack(spacing: 2) {
            Button {
                withAnimation(.snappy) { item.set(done: !item.done) }
            } label: {
                Tick(done: item.done, color: tint, size: 20)
            }
            .buttonStyle(.plain)
            TextField("Sub-item", text: $item.title)
                .strikethrough(item.done)
                .foregroundStyle(item.done ? Ink.muted : Ink.body)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 14))
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
                                    .foregroundStyle(symbol == name ? Color.black : Ink.body)
                                    .frame(width: 44, height: 44)
                                    .background(symbol == name ? Color.white : Ink.surface2,
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
                                    .fill(Color(hex: UInt32(value)))
                                    .frame(width: 30, height: 30)
                                    .padding(4)
                                    .overlay {
                                        Circle().strokeBorder(.white, lineWidth: tint == value ? 2 : 0)
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
                    if let project { context.delete(project) }
                    dismiss()
                    deleted()
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
