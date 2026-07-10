import Foundation

/// Whether the first-launch Spatch walkthrough has been shown — client-side,
/// per-device, so UserDefaults-backed like the weather prompt's "did prompt"
/// flag (`WeatherPreferenceStoring`). There's no separate "was skipped" bit:
/// whether the user finished the tour or sent Spatch away early, it shouldn't
/// replay automatically either way — replaying on demand is available from
/// Settings via `SpatchTutorialViewModel.restart()`.
protocol SpatchTutorialStoring: Sendable {
    func hasCompletedTutorial() -> Bool
    func setHasCompletedTutorial(_ completed: Bool)
}

struct UserDefaultsSpatchTutorialStore: SpatchTutorialStoring {
    private static let key = "vj_spatch_did_complete_tutorial"
    // UserDefaults is thread-safe in practice but not yet marked Sendable in
    // the SDK — safe to bypass the check here (see AppearanceStore).
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hasCompletedTutorial() -> Bool {
        defaults.bool(forKey: Self.key)
    }

    func setHasCompletedTutorial(_ completed: Bool) {
        defaults.set(completed, forKey: Self.key)
    }
}
