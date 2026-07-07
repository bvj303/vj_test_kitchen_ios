import Foundation

/// Whether the calendar's weather outlook is enabled — i.e. the user opted into
/// using their current location. A per-device preference (not shared data), so
/// UserDefaults-backed behind a protocol, same shape as `AppearanceStoring`.
/// Defaults to off, keeping the location prompt strictly opt-in.
protocol WeatherPreferenceStoring: Sendable {
    func loadUseCurrentLocation() -> Bool
    func saveUseCurrentLocation(_ enabled: Bool)
}

struct UserDefaultsWeatherPreferenceStore: WeatherPreferenceStoring {
    private static let key = "vj_weather_use_current_location"
    // UserDefaults is thread-safe in practice but not yet marked Sendable in the
    // SDK — safe to bypass the check here, same as UserDefaultsAppearanceStore.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadUseCurrentLocation() -> Bool {
        defaults.bool(forKey: Self.key)
    }

    func saveUseCurrentLocation(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.key)
    }
}
