import Foundation

/// Appearance preference is a client-side, per-device setting — not shared
/// data — so it's UserDefaults-backed rather than a Postgres column, same
/// reasoning as `GroceryListStoring`.
protocol AppearanceStoring: Sendable {
    func loadAppearanceMode() -> AppearanceMode
    func saveAppearanceMode(_ mode: AppearanceMode)
}

struct UserDefaultsAppearanceStore: AppearanceStoring {
    private static let key = "vj_appearance_mode"
    // UserDefaults is thread-safe in practice but not yet marked Sendable
    // in the SDK — safe to bypass the check here.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadAppearanceMode() -> AppearanceMode {
        guard let rawValue = defaults.string(forKey: Self.key) else { return .system }
        return AppearanceMode(rawValue: rawValue) ?? .system
    }

    func saveAppearanceMode(_ mode: AppearanceMode) {
        defaults.set(mode.rawValue, forKey: Self.key)
    }
}
