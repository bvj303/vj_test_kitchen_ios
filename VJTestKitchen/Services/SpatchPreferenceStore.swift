import Foundation

/// Whether Spatch appears at all — cameo pop-ins, surprise stunt flybys, and
/// the walkthrough replay. A client-side, per-device preference, so
/// UserDefaults-backed like `AppearanceStoring`. Defaults to shown: he's part
/// of the app's personality until the user explicitly sends him away in
/// Settings.
protocol SpatchPreferenceStoring: Sendable {
    func loadShowSpatch() -> Bool
    func saveShowSpatch(_ show: Bool)
}

struct UserDefaultsSpatchPreferenceStore: SpatchPreferenceStoring {
    private static let key = "vj_show_spatch"
    // UserDefaults is thread-safe in practice but not yet marked Sendable
    // in the SDK — safe to bypass the check here (see AppearanceStore).
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadShowSpatch() -> Bool {
        // `bool(forKey:)` returns false for a missing key, but the default
        // here is *on* — read the raw object so "never touched" stays true.
        defaults.object(forKey: Self.key) as? Bool ?? true
    }

    func saveShowSpatch(_ show: Bool) {
        defaults.set(show, forKey: Self.key)
    }
}
