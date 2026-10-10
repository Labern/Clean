import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Item.created, order: .reverse) private var items: [Item]
    @State private var draft = ""
    @FocusState private var composing: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("New Item", text: $draft)
                        .focused($composing)
                        .submitLabel(.done)
                        .onSubmit(add)
                }
                Section {
                    ForEach(items) { item in
                        ItemRow(item: item)
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Items")
            .overlay {
                if items.isEmpty && !composing {
                    ContentUnavailableView("No Items", systemImage: "tray")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", systemImage: "plus") { composing = true }
                }
            }
        }
    }

    private func add() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        withAnimation { context.insert(Item(title: title)) }
        draft = ""
    }

    private func delete(at offsets: IndexSet) {
        withAnimation {
            for index in offsets { context.delete(items[index]) }
        }
    }
}

struct ItemRow: View {
    @Bindable var item: Item

    var body: some View {
        Button {
            withAnimation(.snappy) { item.done.toggle() }
        } label: {
            Label {
                Text(item.title)
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? .secondary : .primary)
            } icon: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.done ? Color.accentColor : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: item.done)
        .accessibilityAddTraits(item.done ? .isSelected : [])
    }
}

#Preview {
    RootView()
        .modelContainer(for: Item.self, inMemory: true)
}
