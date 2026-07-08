import Foundation

/// The user's saved "home" for the calendar's weather outlook — a coordinate
/// (what the forecast API actually needs) plus the postal code it maps to (what
/// we show and let the user edit). Captured once via the first-login prompt or
/// Settings, then reused so the calendar never takes a live GPS fix on every
/// visit (see `MealCalendarViewModel.loadWeather` / `HomeLocationViewModel`).
///
/// Persisted device-locally as JSON in `WeatherPreferenceStoring` — it's a
/// per-device preference, not shared account data.
struct HomeLocation: Equatable, Sendable, Codable {
    /// Postal code (e.g. "02139") when known — shown in Settings and used to
    /// re-geocode if the user edits it. May be nil if reverse geocoding didn't
    /// return one but we still captured a coordinate.
    var postalCode: String?
    var coordinate: Coordinate

    /// A short human label for the saved location — the ZIP if we have one,
    /// otherwise a rounded lat/long so Settings still shows something concrete.
    var displayName: String {
        if let postalCode, !postalCode.isEmpty { return postalCode }
        return String(format: "%.2f, %.2f", coordinate.latitude, coordinate.longitude)
    }
}
