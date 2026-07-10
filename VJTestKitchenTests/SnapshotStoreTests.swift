import Foundation
import Testing
@testable import VJTestKitchen

/// `FileSnapshotStore` against a throwaway temp directory (never the real
/// Application Support container).
struct SnapshotStoreTests {
    private func makeStore() -> (FileSnapshotStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapshotStoreTests-\(UUID().uuidString)", isDirectory: true)
        return (FileSnapshotStore(directory: directory), directory)
    }

    @Test func roundTripsACodableValue() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let recipes = [Recipe(id: 1, userId: nil, title: "Carbonara", description: nil, instructions: nil, imagePath: nil, prepTime: 20, servings: 2, createdAt: Date())]
        store.save(recipes, key: .recipesFirstPage)

        let loaded = store.load([Recipe].self, key: .recipesFirstPage)
        #expect(loaded?.map(\.title) == ["Carbonara"])
        #expect(loaded?.first?.prepTime == 20)
    }

    @Test func loadReturnsNilWhenNothingSaved() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(store.load([Recipe].self, key: .homeShelf) == nil)
    }

    @Test func loadReturnsNilForCorruptData() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("homeShelf.json"))

        #expect(store.load([Recipe].self, key: .homeShelf) == nil)
    }

    @Test func savingOverwritesThePreviousValue() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.save(["a"], key: .homeShelf)
        store.save(["b", "c"], key: .homeShelf)

        #expect(store.load([String].self, key: .homeShelf) == ["b", "c"])
    }

    @Test func clearAllRemovesEveryKey() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.save(["a"], key: .homeShelf)
        store.save(["b"], key: .groceryItems)

        store.clearAll()

        #expect(store.load([String].self, key: .homeShelf) == nil)
        #expect(store.load([String].self, key: .groceryItems) == nil)
    }
}
