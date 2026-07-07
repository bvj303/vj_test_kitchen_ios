import Foundation
import Observation

/// Backs `SettingsView`. Owned at the app root (`VJTestKitchenApp`) and
/// injected into the environment so the appearance override can be read by
/// the root scene's `.preferredColorScheme`, not just the Settings screen.
@MainActor
@Observable
final class SettingsViewModel {
    var appearanceMode: AppearanceMode {
        didSet { store.saveAppearanceMode(appearanceMode) }
    }

    /// Whether the calendar shows a location-based weather outlook. Read-only to
    /// the view — changing it goes through `setUseCurrentLocation(_:)` so the
    /// location permission prompt is handled before the toggle sticks.
    private(set) var useCurrentLocationForWeather: Bool
    /// True when the user tried to enable weather but location access is denied,
    /// so the view can point them to Settings instead of silently failing.
    private(set) var locationPermissionDenied = false

    private let store: AppearanceStoring
    private let weatherStore: WeatherPreferenceStoring
    private let locationProvider: LocationProviding

    init(
        store: AppearanceStoring = UserDefaultsAppearanceStore(),
        weatherStore: WeatherPreferenceStoring = UserDefaultsWeatherPreferenceStore(),
        locationProvider: LocationProviding = CoreLocationService()
    ) {
        self.store = store
        self.weatherStore = weatherStore
        self.locationProvider = locationProvider
        self.appearanceMode = store.loadAppearanceMode()
        self.useCurrentLocationForWeather = weatherStore.loadUseCurrentLocation()
    }

    /// Toggles the weather outlook. Turning it on first requests location
    /// permission; if the user declines (or it's already denied) the toggle stays
    /// off and `locationPermissionDenied` flips so the UI can explain why.
    func setUseCurrentLocation(_ enabled: Bool) async {
        guard enabled else {
            useCurrentLocationForWeather = false
            weatherStore.saveUseCurrentLocation(false)
            locationPermissionDenied = false
            return
        }
        let status = await locationProvider.requestAuthorization()
        switch status {
        case .authorized:
            useCurrentLocationForWeather = true
            weatherStore.saveUseCurrentLocation(true)
            locationPermissionDenied = false
        case .denied:
            useCurrentLocationForWeather = false
            weatherStore.saveUseCurrentLocation(false)
            locationPermissionDenied = true
        case .notDetermined:
            // User dismissed the prompt without deciding — leave it off, no scold.
            useCurrentLocationForWeather = false
            weatherStore.saveUseCurrentLocation(false)
            locationPermissionDenied = false
        }
    }
}
