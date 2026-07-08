import Foundation

/// Persists the calendar weather outlook's home location (see `HomeLocation`)
/// plus whether the one-time first-login location prompt has been shown. A
/// per-device preference (not shared account data), so UserDefaults-backed
/// behind a protocol, same shape as `AppearanceStoring`. Weather is considered
/// enabled exactly when a home location is set; there's no separate on/off flag.
protocol WeatherPreferenceStoring: Sendable {
    /// The saved home location for the weather outlook, or nil if the user
    /// hasn't set one (weather off).
    func loadHomeLocation() -> HomeLocation?
    func saveHomeLocation(_ location: HomeLocation?)
    /// Whether the first-login "set your home location" prompt has already been
    /// presented, so it's shown at most once regardless of the user's answer.
    func loadDidPromptForLocation() -> Bool
    func saveDidPromptForLocation(_ didPrompt: Bool)
}

struct UserDefaultsWeatherPreferenceStore: WeatherPreferenceStoring {
    private static let homeLocationKey = "vj_weather_home_location"
    private static let didPromptKey = "vj_weather_did_prompt_for_location"
    // UserDefaults is thread-safe in practice but not yet marked Sendable in the
    // SDK — safe to bypass the check here, same as UserDefaultsAppearanceStore.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadHomeLocation() -> HomeLocation? {
        guard let data = defaults.data(forKey: Self.homeLocationKey) else { return nil }
        return try? JSONDecoder().decode(HomeLocation.self, from: data)
    }

    func saveHomeLocation(_ location: HomeLocation?) {
        guard let location, let data = try? JSONEncoder().encode(location) else {
            defaults.removeObject(forKey: Self.homeLocationKey)
            return
        }
        defaults.set(data, forKey: Self.homeLocationKey)
    }

    func loadDidPromptForLocation() -> Bool {
        defaults.bool(forKey: Self.didPromptKey)
    }

    func saveDidPromptForLocation(_ didPrompt: Bool) {
        defaults.set(didPrompt, forKey: Self.didPromptKey)
    }
}
