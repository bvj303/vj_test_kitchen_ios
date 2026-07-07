import Foundation
import Testing
@testable import VJTestKitchen

final class FakeAppearanceStore: AppearanceStoring, @unchecked Sendable {
    var mode: AppearanceMode = .system

    func loadAppearanceMode() -> AppearanceMode { mode }
    func saveAppearanceMode(_ mode: AppearanceMode) { self.mode = mode }
}

@MainActor
struct SettingsViewModelTests {
    @Test func loadsInitialModeFromStore() {
        let store = FakeAppearanceStore()
        store.mode = .dark

        let viewModel = SettingsViewModel(store: store)

        #expect(viewModel.appearanceMode == .dark)
    }

    @Test func defaultsToSystemWhenNothingStored() {
        let viewModel = SettingsViewModel(store: FakeAppearanceStore())

        #expect(viewModel.appearanceMode == .system)
    }

    @Test func settingAppearanceModePersistsToStore() {
        let store = FakeAppearanceStore()
        let viewModel = SettingsViewModel(store: store)

        viewModel.appearanceMode = .light

        #expect(store.mode == .light)
    }

    // MARK: - Weather / location

    @Test func loadsInitialWeatherPreferenceFromStore() {
        let weatherStore = FakeWeatherPreferenceStore()
        weatherStore.enabled = true

        let viewModel = SettingsViewModel(
            store: FakeAppearanceStore(),
            weatherStore: weatherStore,
            locationProvider: FakeLocationProvider()
        )

        #expect(viewModel.useCurrentLocationForWeather)
    }

    @Test func enablingWeatherRequestsPermissionAndPersistsWhenAuthorized() async {
        let weatherStore = FakeWeatherPreferenceStore()
        let location = FakeLocationProvider()
        location.resolvedAuthorizationAfterRequest = .authorized
        let viewModel = SettingsViewModel(
            store: FakeAppearanceStore(),
            weatherStore: weatherStore,
            locationProvider: location
        )

        await viewModel.setUseCurrentLocation(true)

        #expect(viewModel.useCurrentLocationForWeather)
        #expect(weatherStore.enabled)
        #expect(!viewModel.locationPermissionDenied)
        #expect(location.requestAuthorizationCallCount == 1)
    }

    @Test func enablingWeatherWhenDeniedRevertsAndFlagsDenied() async {
        let weatherStore = FakeWeatherPreferenceStore()
        let location = FakeLocationProvider()
        location.resolvedAuthorizationAfterRequest = .denied
        let viewModel = SettingsViewModel(
            store: FakeAppearanceStore(),
            weatherStore: weatherStore,
            locationProvider: location
        )

        await viewModel.setUseCurrentLocation(true)

        #expect(!viewModel.useCurrentLocationForWeather)
        #expect(!weatherStore.enabled)
        #expect(viewModel.locationPermissionDenied)
    }

    @Test func disablingWeatherPersistsOffAndClearsDeniedFlag() async {
        let weatherStore = FakeWeatherPreferenceStore()
        weatherStore.enabled = true
        let viewModel = SettingsViewModel(
            store: FakeAppearanceStore(),
            weatherStore: weatherStore,
            locationProvider: FakeLocationProvider()
        )
        #expect(viewModel.useCurrentLocationForWeather)

        await viewModel.setUseCurrentLocation(false)

        #expect(!viewModel.useCurrentLocationForWeather)
        #expect(!weatherStore.enabled)
        #expect(!viewModel.locationPermissionDenied)
    }
}

struct AppearanceModeTests {
    @Test func colorSchemeMapsCorrectly() {
        #expect(AppearanceMode.system.colorScheme == nil)
        #expect(AppearanceMode.light.colorScheme == .light)
        #expect(AppearanceMode.dark.colorScheme == .dark)
    }
}
