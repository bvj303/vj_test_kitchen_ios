import Foundation

/// The data each screen persists for instant paint (see `LocalSnapshotStoring`).
/// One key per screen; the raw value doubles as the on-disk filename.
enum SnapshotKey: String, CaseIterable, Sendable {
    case recipesFirstPage
    case groceryItems
    case mealPlansWindow
    case homeShelf
}

/// A tiny last-known-good cache for each screen's loaded data, so launches
/// paint instantly from disk while the network refresh runs — and an offline
/// open still shows the user's recipes/groceries/meal plans instead of a wall
/// of error alerts. Same denormalized-snapshot idea the widgets use
/// (`WidgetDataStore`), pointed at the app's own screens.
///
/// Deliberately best-effort: reads fall back to nil and writes fail silently —
/// a missing or corrupt snapshot must never break a screen that can just load
/// from the network as before. Cleared wholesale on sign-out/account-deletion
/// so one account's data can't flash on screen for the next (see
/// `AuthViewModel`).
protocol LocalSnapshotStoring: Sendable {
    func load<T: Decodable>(_ type: T.Type, key: SnapshotKey) -> T?
    func save<T: Encodable>(_ value: T, key: SnapshotKey)
    func clearAll()
}

/// File-backed implementation: one JSON file per key under Application
/// Support/Snapshots. Injectable directory so tests write to a temp dir.
struct FileSnapshotStore: LocalSnapshotStoring {
    static let shared = FileSnapshotStore()

    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Snapshots", isDirectory: true)
    }

    func load<T: Decodable>(_ type: T.Type, key: SnapshotKey) -> T? {
        guard let data = try? Data(contentsOf: fileURL(for: key)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, key: SnapshotKey) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    func clearAll() {
        for key in SnapshotKey.allCases {
            try? FileManager.default.removeItem(at: fileURL(for: key))
        }
    }

    private func fileURL(for key: SnapshotKey) -> URL {
        directory.appendingPathComponent("\(key.rawValue).json")
    }
}
