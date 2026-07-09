import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Read/write bridge over the shared App Group container that carries widget
/// snapshots between the app (writer) and the widget extension (reader).
///
/// Values are stored as JSON under `UserDefaults(suiteName:)` for the App Group
/// — the simplest durable channel that both processes can reach. Injectable
/// `defaults` so unit tests can point at an in-memory/throwaway suite instead of
/// the real group container (which needs the entitlement to exist).
/// `@unchecked Sendable`: the only stored property is a `UserDefaults`, which is
/// documented thread-safe but not `Sendable`-annotated. Publishing happens from
/// `@MainActor` view models, and `UserDefaults` handles its own synchronization.
struct WidgetDataStore: @unchecked Sendable {
    /// Shared instance backed by the real App Group container.
    static let shared = WidgetDataStore()

    private let defaults: UserDefaults?

    /// - Parameter defaults: the backing store; defaults to the App Group suite.
    ///   `UserDefaults(suiteName:)` returns nil only for a malformed name, in
    ///   which case every accessor safely no-ops.
    init(defaults: UserDefaults? = UserDefaults(suiteName: WidgetSharedConfig.appGroupIdentifier)) {
        self.defaults = defaults
    }

    private enum Key {
        static let cooksIdea = "widget.cooksIdea"
        static let todaysMeals = "widget.todaysMeals"
        static let grocery = "widget.grocery"
    }

    // MARK: Typed accessors

    var cooksIdea: CooksIdeaSnapshot? {
        get { load(CooksIdeaSnapshot.self, for: Key.cooksIdea) }
        nonmutating set { save(newValue, for: Key.cooksIdea) }
    }

    var todaysMeals: TodaysMealsSnapshot? {
        get { load(TodaysMealsSnapshot.self, for: Key.todaysMeals) }
        nonmutating set { save(newValue, for: Key.todaysMeals) }
    }

    var grocery: GrocerySnapshot? {
        get { load(GrocerySnapshot.self, for: Key.grocery) }
        nonmutating set { save(newValue, for: Key.grocery) }
    }

    // MARK: Reload

    /// Ask WidgetKit to rebuild every widget's timeline — call after writing new
    /// snapshots so the change shows without waiting for the next scheduled
    /// refresh. No-op where WidgetKit isn't available.
    func reloadAllWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    // MARK: Generic storage

    private func save<T: Encodable>(_ value: T?, for key: String) {
        guard let defaults else { return }
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private func load<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        guard let defaults, let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
