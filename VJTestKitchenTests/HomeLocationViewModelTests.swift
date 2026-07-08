import Foundation
import Testing
@testable import VJTestKitchen

// Reuses FakeWeatherPreferenceStore, FakeLocationProvider, FakeGeocoder, and
// makeHomeLocation from CalendarWeatherTests (same test module).

@MainActor
struct HomeLocationViewModelTests {
    private func makeViewModel(
        store: FakeWeatherPreferenceStore = FakeWeatherPreferenceStore(),
        location: FakeLocationProvider = FakeLocationProvider(),
        geocoder: FakeGeocoder = FakeGeocoder()
    ) -> HomeLocationViewModel {
        HomeLocationViewModel(store: store, locationProvider: location, geocoder: geocoder)
    }

    @Test func loadsExistingHomeLocationFromStore() {
        let store = FakeWeatherPreferenceStore()
        store.homeLocation = makeHomeLocation(zip: "10001")

        let viewModel = makeViewModel(store: store)

        #expect(viewModel.homeLocation?.postalCode == "10001")
        #expect(viewModel.hasHomeLocation)
    }

    @Test func useCurrentLocationReverseGeocodesAndSaves() async {
        let store = FakeWeatherPreferenceStore()
        let location = FakeLocationProvider()
        location.resolvedAuthorizationAfterRequest = .authorized
        location.coordinateToReturn = Coordinate(latitude: 42.36, longitude: -71.10)
        let geocoder = FakeGeocoder()
        geocoder.postalCodeToReturn = "02139"

        let viewModel = makeViewModel(store: store, location: location, geocoder: geocoder)
        await viewModel.useCurrentLocation()

        #expect(viewModel.homeLocation?.postalCode == "02139")
        #expect(viewModel.homeLocation?.coordinate == location.coordinateToReturn)
        #expect(store.homeLocation?.postalCode == "02139")   // persisted
        #expect(geocoder.reverseGeocodedCoordinates.first == location.coordinateToReturn)
        #expect(!viewModel.locationPermissionDenied)
    }

    @Test func useCurrentLocationSavesCoordinateEvenWithoutAZip() async {
        let store = FakeWeatherPreferenceStore()
        let location = FakeLocationProvider()
        location.resolvedAuthorizationAfterRequest = .authorized
        let geocoder = FakeGeocoder()
        geocoder.postalCodeToReturn = nil   // reverse geocode found no ZIP

        let viewModel = makeViewModel(store: store, location: location, geocoder: geocoder)
        await viewModel.useCurrentLocation()

        #expect(viewModel.hasHomeLocation)
        #expect(viewModel.homeLocation?.postalCode == nil)
    }

    @Test func useCurrentLocationWhenDeniedFlagsDeniedAndDoesNotSave() async {
        let store = FakeWeatherPreferenceStore()
        let location = FakeLocationProvider()
        location.resolvedAuthorizationAfterRequest = .denied

        let viewModel = makeViewModel(store: store, location: location)
        await viewModel.useCurrentLocation()

        #expect(viewModel.locationPermissionDenied)
        #expect(!viewModel.hasHomeLocation)
        #expect(store.homeLocation == nil)
    }

    @Test func useCurrentLocationWhenDismissedDoesNotScoldOrSave() async {
        let store = FakeWeatherPreferenceStore()
        let location = FakeLocationProvider()
        location.resolvedAuthorizationAfterRequest = .notDetermined

        let viewModel = makeViewModel(store: store, location: location)
        await viewModel.useCurrentLocation()

        #expect(!viewModel.locationPermissionDenied)
        #expect(!viewModel.hasHomeLocation)
    }

    @Test func setFromZipInputForwardGeocodesSavesAndClearsInput() async {
        let store = FakeWeatherPreferenceStore()
        let geocoder = FakeGeocoder()
        geocoder.coordinateToReturn = Coordinate(latitude: 40.75, longitude: -73.99)

        let viewModel = makeViewModel(store: store, geocoder: geocoder)
        viewModel.zipInput = "10001"
        await viewModel.setFromZipInput()

        #expect(viewModel.homeLocation?.postalCode == "10001")
        #expect(viewModel.homeLocation?.coordinate == geocoder.coordinateToReturn)
        #expect(store.homeLocation?.postalCode == "10001")
        #expect(viewModel.zipInput.isEmpty)
        #expect(geocoder.forwardGeocodedCodes == ["10001"])
    }

    @Test func setFromZipInputSurfacesErrorAndKeepsExistingLocation() async {
        let store = FakeWeatherPreferenceStore()
        store.homeLocation = makeHomeLocation(zip: "02139")
        let geocoder = FakeGeocoder()
        geocoder.forwardError = GeocodingError.notFound

        let viewModel = makeViewModel(store: store, geocoder: geocoder)
        viewModel.zipInput = "00000"
        await viewModel.setFromZipInput()

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.homeLocation?.postalCode == "02139")   // unchanged
    }

    @Test func setFromZipInputIgnoresBlankInput() async {
        let geocoder = FakeGeocoder()
        let viewModel = makeViewModel(geocoder: geocoder)
        viewModel.zipInput = "   "

        await viewModel.setFromZipInput()

        #expect(geocoder.forwardGeocodedCodes.isEmpty)
        #expect(!viewModel.hasHomeLocation)
    }

    @Test func clearHomeLocationRemovesItFromStore() {
        let store = FakeWeatherPreferenceStore()
        store.homeLocation = makeHomeLocation()
        let viewModel = makeViewModel(store: store)
        #expect(viewModel.hasHomeLocation)

        viewModel.clearHomeLocation()

        #expect(!viewModel.hasHomeLocation)
        #expect(store.homeLocation == nil)
    }

    @Test func shouldPromptOnlyWhenNotPromptedAndNoHomeLocation() {
        let store = FakeWeatherPreferenceStore()
        let viewModel = makeViewModel(store: store)
        #expect(viewModel.shouldPromptForLocation)   // fresh: prompt

        store.didPrompt = true
        #expect(!makeViewModel(store: store).shouldPromptForLocation)   // already prompted

        let withHome = FakeWeatherPreferenceStore()
        withHome.homeLocation = makeHomeLocation()
        #expect(!makeViewModel(store: withHome).shouldPromptForLocation)   // already has one
    }

    @Test func markPromptedPersists() {
        let store = FakeWeatherPreferenceStore()
        let viewModel = makeViewModel(store: store)

        viewModel.markPrompted()

        #expect(store.didPrompt)
    }
}
