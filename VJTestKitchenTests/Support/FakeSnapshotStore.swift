import Foundation
@testable import VJTestKitchen

/// In-memory `LocalSnapshotStoring` so view-model tests never touch the real
/// Application Support directory (which would leak state between tests and
/// across runs). Also records clears so auth tests can assert the wipe.
final class FakeSnapshotStore: LocalSnapshotStoring, @unchecked Sendable {
    private var storage: [SnapshotKey: Data] = [:]
    private(set) var clearAllCallCount = 0

    func load<T: Decodable>(_ type: T.Type, key: SnapshotKey) -> T? {
        guard let data = storage[key] else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, key: SnapshotKey) {
        storage[key] = try? JSONEncoder().encode(value)
    }

    func clearAll() {
        clearAllCallCount += 1
        storage = [:]
    }

    /// Test conveniences.
    var isEmpty: Bool { storage.isEmpty }
    func hasValue(for key: SnapshotKey) -> Bool { storage[key] != nil }
}
