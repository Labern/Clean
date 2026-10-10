import SwiftUI
import SwiftData

/// Every page: a read-only header up top, content that settles low,
/// and a reach area pinned to the bottom for everything you touch.
struct PageScaffold<Content: View, Reach: View>: View {
    let spine: Spine
    let eyebrow: String
    let title: String
    let subtitle: String
    let content: () -> Content
    let reach: () -> Reach

    init(spine: Spine, eyebrow: String, title: String, subtitle: String,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder reach: @escaping () -> Reach) {
        self.spine = spine
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.content = content
        self.reach = reach
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        Spacer(minLength: 24)
                        content()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.bottom)
            }
            VStack(spacing: 10) {
                reach()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(alignment: .top) {
                LinearGradient(colors: [Ink.ground.opacity(0), Ink.ground], startPoint: .top, endPoint: .bottom)
                    .frame(height: 28)
                    .offset(y: -28)
                    .allowsHitTesting(false)
            }
        }
        .background { PageAtmosphere(spine: spine) }
        .tint(spine.tint)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(spine.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(spine.pigment)
                    .font(Mark.mincho(13))
                    .foregroundStyle(spine.tint.opacity(0.7))
                    .accessibilityHidden(true)
            }
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A slow wash of the spine's pigment at the top of the page,
/// and its name in katakana running down the trailing edge.
struct PageAtmosphere: View {
    let spine: Spine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Ink.ground
            VStack(spacing: 0) {
                TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { context in
                    glow(at: context.date.timeIntervalSinceReferenceDate)
                }
                .frame(height: 280)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                .opacity(scheme == .dark ? 0.6 : 0.4)
                Spacer(minLength: 0)
            }
            VerticalKana(text: spine.katakana, size: 92, spacing: 0.02)
                .foregroundStyle(spine.tint.opacity(scheme == .dark ? 0.07 : 0.06))
                .padding(.top, 96)
                .padding(.trailing, -6)
                .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }

    private func glow(at t: TimeInterval) -> some View {
        let drift = Float(sin(t / 3.2) * 0.14)
        let lift = Float(cos(t / 4.1) * 0.06)
        let points: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
            SIMD2(0, 0.5), SIMD2(0.5 + drift, 0.45 + lift), SIMD2(1, 0.5),
            SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1),
        ]
        let c = spine.tint
        let colors: [Color] = [
            c.opacity(0.55), c.opacity(0.22), c.opacity(0.45),
            c.opacity(0.10), c.opacity(0.20), c.opacity(0.06),
            .clear, .clear, .clear,
        ]
        return MeshGradient(width: 3, height: 3, points: points, colors: colors)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.2)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

struct Hairline: View {
    var inset: CGFloat = 14
    var body: some View {
        Rectangle().fill(Ink.hairline).frame(height: 0.5).padding(.leading, inset)
    }
}

// MARK: - Button styles

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.08 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// The one filled button on a page. It sits lowest, nearest the thumb.
struct ProminentStyle: ButtonStyle {
    let spine: Spine
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(spine.onFill)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 12)
            .background(spine.fill.gradient, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
            .opacity(isEnabled ? 1 : 0.4)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct QuietStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.horizontal, 8)
            .background(Ink.surface, in: Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - To-dos, shared by every spine

struct TodoCard: View {
    let spine: Spine
    var inlineAdd: Bool = false
    @Query private var todos: [Todo]

    init(spine: Spine, inlineAdd: Bool = false) {
        self.spine = spine
        self.inlineAdd = inlineAdd
        let raw = spine.rawValue
        _todos = Query(filter: #Predicate<Todo> { $0.spineRaw == raw }, sort: [SortDescriptor(\Todo.created)])
    }

    var body: some View {
        let open = todos.filter { !$0.done }
        let recent = todos
            .filter { $0.done }
            .sorted { ($0.completed ?? .distantPast) > ($1.completed ?? .distantPast) }
            .prefix(2)
        let rows = open + Array(recent)

        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "To do", trailing: open.isEmpty ? "All done" : "\(open.count)")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, todo in
                        if index > 0 { Hairline(inset: 48) }
                        TodoRow(todo: todo, spine: spine)
                    }
                    if inlineAdd {
                        if !rows.isEmpty { Hairline(inset: 48) }
                        InlineAdd(spine: spine)
                    } else if rows.isEmpty {
                        Text("Nothing to do.")
                            .foregroundStyle(.secondary)
                            .padding(14)
                    }
                }
            }
        }
    }
}

struct TodoRow: View {
    @Bindable var todo: Todo
    let spine: Spine
    @Environment(\.modelContext) private var context

    var body: some View {
        Button {
            withAnimation(.snappy) {
                todo.done.toggle()
                todo.completed = todo.done ? .now : nil
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(todo.done ? Color.clear : Color.secondary.opacity(0.5), lineWidth: 1.5)
                    if todo.done {
                        Circle().fill(spine.fill)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(spine.onFill)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(todo.title)
                        .strikethrough(todo.done)
                        .foregroundStyle(todo.done ? HierarchicalShapeStyle.tertiary : HierarchicalShapeStyle.primary)
                    if !todo.tag.isEmpty {
                        Text(todo.tag)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(spine.tint)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: todo.done) { _, new in new }
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) {
                withAnimation { context.delete(todo) }
            }
        }
        .accessibilityAddTraits(todo.done ? .isSelected : [])
    }
}

struct InlineAdd: View {
    let spine: Spine
    @State private var text = ""
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(spine.tint)
                .frame(width: 22, height: 22)
            TextField("Add", text: $text)
                .submitLabel(.done)
                .onSubmit(add)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func add() {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        withAnimation(.snappy) { context.insert(Todo(spine: spine, title: title)) }
        text = ""
    }
}

/// Messages-style entry bar for the Tesla list, at the very bottom.
struct ComposeBar: View {
    let spine: Spine
    let placeholder: String
    let tags: [String]
    @State private var text = ""
    @State private var tag = ""
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Tag", selection: $tag) {
                    Text("No tag").tag("")
                    ForEach(tags, id: \.self) { Text($0).tag($0) }
                }
            } label: {
                Text(tag.isEmpty ? "Tag" : tag)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tag.isEmpty ? Color.secondary : spine.tint)
                    .frame(minWidth: 30)
                    .frame(height: 44)
                    .padding(.horizontal, 12)
                    .background(Ink.surface, in: Capsule())
            }
            TextField(placeholder, text: $text)
                .submitLabel(.done)
                .onSubmit(add)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Ink.surface, in: Capsule())
            Button(action: add) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(spine.onFill)
                    .frame(width: 44, height: 44)
                    .background(spine.fill.gradient, in: Circle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Add")
        }
    }

    private func add() {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        withAnimation(.snappy) { context.insert(Todo(spine: spine, title: title, tag: tag)) }
        text = ""
        tag = ""
    }
}
