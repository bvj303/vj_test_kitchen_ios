import Foundation
import Observation

/// Owns the calendar weather outlook's home location — shared by the first-login
/// prompt (`HomeLocationPromptView`) and the Settings screen so both read and
/// write the same saved location. Weather is "on" exactly when a home location
/// is set; there's no separate toggle.
///
/// Two ways to set it: capture the device's current location once and
/// reverse-geocode it to a ZIP, or type a ZIP and forward-geocode it. Either
/// way we store both the coordinate (what the forecast API needs) and the ZIP
/// (what we display), so the calendar never takes a live GPS fix again.
@MainActor
@Observable
final class HomeLocationViewModel {
    private(set) var homeLocation: HomeLocation?
    /// Bound to the Settings/prompt ZIP text field.
    var zipInput = ""
    private(set) var isWorking = false
    var errorMessage: String?
    /// True when the user tried to use their current location but access is
    /// denied — the UI points them to Settings instead of failing silently.
    private(set) var locationPermissionDenied = false

    private let store: WeatherPreferenceStoring
    private let locationProvider: LocationProviding
    private let geocoder: GeocodingProviding

    init(
        store: WeatherPreferenceStoring = UserDefaultsWeatherPreferenceStore(),
        locationProvider: LocationProviding = CoreLocationService(),
        geocoder: GeocodingProviding = CLGeocoderService()
    ) {
        self.store = store
        self.locationProvider = locationProvider
        self.geocoder = geocoder
        self.homeLocation = store.loadHomeLocation()
    }

    var hasHomeLocation: Bool { homeLocation != nil }

    /// Whether the one-time first-login prompt should be shown: only when it
    /// hasn't been shown before and no home location is set yet.
    var shouldPromptForLocation: Bool {
        !store.loadDidPromptForLocation() && homeLocation == nil
    }

    /// Record that the first-login prompt has been presented, so it won't show
    /// again whether the user set a location, typed a ZIP, or dismissed it.
    func markPrompted() {
        store.saveDidPromptForLocation(true)
    }

    /// Request location permission, take one fix, reverse-geocode it to a ZIP,
    /// and save it as the home location. On denial, flips
    /// `locationPermissionDenied` and leaves any existing home location intact.
    func useCurrentLocation() async {
        errorMessage = nil
        locationPermissionDenied = false
        isWorking = true
        defer { isWorking = false }

        let status = await locationProvider.requestAuthorization()
        guard status == .authorized else {
            // .denied → point to Settings; .notDetermined (dismissed) → no scold.
            locationPermissionDenied = status == .denied
            return
        }
        do {
            let coordinate = try await locationProvider.currentLocation()
            let zip = await geocoder.postalCode(for: coordinate)
            save(HomeLocation(postalCode: zip, coordinate: coordinate))
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Forward-geocode the typed ZIP and save it as the home location. A blank
    /// or unresolvable ZIP surfaces a message and leaves the current one intact.
    func setFromZipInput() async {
        let zip = zipInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !zip.isEmpty else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let coordinate = try await geocoder.coordinate(for: zip)
            save(HomeLocation(postalCode: zip, coordinate: coordinate))
            zipInput = ""
        } catch {
            errorMessage = "Couldn't find that ZIP code. Check it and try again."
        }
    }

    /// Turn the weather outlook off by clearing the saved home location.
    func clearHomeLocation() {
        store.saveHomeLocation(nil)
        homeLocation = nil
    }

    private func save(_ location: HomeLocation) {
        store.saveHomeLocation(location)
        homeLocation = location
        locationPermissionDenied = false
    }
}
