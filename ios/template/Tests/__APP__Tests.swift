import Testing
import SwiftData
@testable import __APP__

@MainActor
struct ItemTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Item.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func insertAndFetch() throws {
        let context = try makeContext()
        context.insert(Item(title: "First"))
        try context.save()
        let items = try context.fetch(FetchDescriptor<Item>())
        #expect(items.map(\.title) == ["First"])
        #expect(items.first?.done == false)
    }

    @Test func toggleDone() throws {
        let item = Item(title: "Toggle")
        item.done.toggle()
        #expect(item.done)
    }
}
