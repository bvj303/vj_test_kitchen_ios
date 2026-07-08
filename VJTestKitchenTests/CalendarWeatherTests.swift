import Foundation
import Testing
@testable import VJTestKitchen

// MARK: - Shared weather test doubles (also used by SettingsViewModelTests)

final class FakeWeatherForecaster: WeatherForecasting, @unchecked Sendable {
    var forecasts: [DailyForecast] = []
    var errorToThrow: Error?
    private(set) var requestedCoordinates: [Coordinate] = []

    func dailyForecast(for coordinate: Coordinate) async throws -> [DailyForecast] {
        requestedCoordinates.append(coordinate)
        if let errorToThrow { throw errorToThrow }
        return forecasts
    }
}

final class FakeLocationProvider: LocationProviding, @unchecked Sendable {
    var authorization: LocationAuthorization = .notDetermined
    /// If set, the status the provider "resolves" to after a permission prompt.
    var resolvedAuthorizationAfterRequest: LocationAuthorization?
    var coordinateToReturn = Coordinate(latitude: 30.27, longitude: -97.74)
    var errorToThrow: Error?
    private(set) var requestAuthorizationCallCount = 0

    func currentAuthorization() async -> LocationAuthorization { authorization }

    func requestAuthorization() async -> LocationAuthorization {
        requestAuthorizationCallCount += 1
        if let resolved = resolvedAuthorizationAfterRequest { authorization = resolved }
        return authorization
    }

    func currentLocation() async throws -> Coordinate {
        if let errorToThrow { throw errorToThrow }
        return coordinateToReturn
    }
}

final class FakeWeatherPreferenceStore: WeatherPreferenceStoring, @unchecked Sendable {
    var homeLocation: HomeLocation?
    var didPrompt = false
    func loadHomeLocation() -> HomeLocation? { homeLocation }
    func saveHomeLocation(_ location: HomeLocation?) { homeLocation = location }
    func loadDidPromptForLocation() -> Bool { didPrompt }
    func saveDidPromptForLocation(_ didPrompt: Bool) { self.didPrompt = didPrompt }
}

final class FakeGeocoder: GeocodingProviding, @unchecked Sendable {
    var postalCodeToReturn: String? = "02139"
    var coordinateToReturn = Coordinate(latitude: 42.36, longitude: -71.10)
    var forwardError: Error?
    private(set) var reverseGeocodedCoordinates: [Coordinate] = []
    private(set) var forwardGeocodedCodes: [String] = []

    func postalCode(for coordinate: Coordinate) async -> String? {
        reverseGeocodedCoordinates.append(coordinate)
        return postalCodeToReturn
    }

    func coordinate(for postalCode: String) async throws -> Coordinate {
        forwardGeocodedCodes.append(postalCode)
        if let forwardError { throw forwardError }
        return coordinateToReturn
    }
}

func makeHomeLocation(zip: String? = "02139", lat: Double = 42.36, lon: Double = -71.10) -> HomeLocation {
    HomeLocation(postalCode: zip, coordinate: Coordinate(latitude: lat, longitude: lon))
}

func makeForecast(
    date: String,
    symbol: String = "sun.max.fill",
    condition: String = "Clear",
    category: WeatherCategory = .clear,
    high: Double = 80,
    low: Double = 60,
    unit: UnitTemperature = .fahrenheit
) -> DailyForecast {
    DailyForecast(
        date: date,
        symbolName: symbol,
        condition: condition,
        category: category,
        highTemperature: Measurement(value: high, unit: unit),
        lowTemperature: Measurement(value: low, unit: unit)
    )
}

// MARK: - MealCalendarViewModel weather behavior

@MainActor
struct CalendarWeatherTests {
    private func makeViewModel(
        forecaster: FakeWeatherForecaster,
        store: FakeWeatherPreferenceStore
    ) -> MealCalendarViewModel {
        MealCalendarViewModel(
            mealPlanService: FakeMealPlanService(),
            recipeService: FakeMealPlanRecipeService(),
            weatherForecaster: forecaster,
            weatherPreferenceStore: store
        )
    }

    @Test func loadWeatherPopulatesForecastForSavedHomeLocation() async {
        let store = FakeWeatherPreferenceStore()
        store.homeLocation = makeHomeLocation(lat: 42.36, lon: -71.10)
        let forecaster = FakeWeatherForecaster()
        forecaster.forecasts = [makeForecast(date: "2026-07-05"), makeForecast(date: "2026-07-06")]

        let viewModel = makeViewModel(forecaster: forecaster, store: store)
        await viewModel.loadWeather()

        #expect(viewModel.forecast(for: "2026-07-05")?.symbolName == "sun.max.fill")
        #expect(viewModel.forecast(for: "2026-07-06") != nil)
        #expect(viewModel.forecast(for: "2026-07-07") == nil)
        // Uses the stored home coordinate — no live GPS fix.
        #expect(forecaster.requestedCoordinates.first == store.homeLocation?.coordinate)
    }

    @Test func loadWeatherClearsAndSkipsFetchWhenNoHomeLocation() async {
        let store = FakeWeatherPreferenceStore()
        store.homeLocation = nil
        let forecaster = FakeWeatherForecaster()
        forecaster.forecasts = [makeForecast(date: "2026-07-05")]

        let viewModel = makeViewModel(forecaster: forecaster, store: store)
        await viewModel.loadWeather()

        #expect(viewModel.forecast(for: "2026-07-05") == nil)
        #expect(forecaster.requestedCoordinates.isEmpty)
    }

    @Test func loadWeatherPopulatesAfterHomeLocationIsSet() async {
        // Mirrors the real flow: the calendar first loads with no home location
        // (empty forecast), then the user sets one in Settings / the prompt. The
        // view's `.onChange(of: homeLocationViewModel.homeLocation)` calls
        // `loadWeather()` again — which must now populate, not stay empty.
        let store = FakeWeatherPreferenceStore()
        let forecaster = FakeWeatherForecaster()
        forecaster.forecasts = [makeForecast(date: "2026-07-05")]

        let viewModel = makeViewModel(forecaster: forecaster, store: store)
        await viewModel.loadWeather()
        #expect(viewModel.forecastByDate.isEmpty)

        store.homeLocation = makeHomeLocation()
        await viewModel.loadWeather()

        #expect(viewModel.forecast(for: "2026-07-05") != nil)
    }

    @Test func loadWeatherSwallowsErrorsWithoutRaisingTheMealPlanAlert() async {
        let store = FakeWeatherPreferenceStore()
        store.homeLocation = makeHomeLocation()
        let forecaster = FakeWeatherForecaster()
        forecaster.errorToThrow = WeatherError.badResponse

        let viewModel = makeViewModel(forecaster: forecaster, store: store)
        await viewModel.loadWeather()

        #expect(viewModel.forecast(for: "2026-07-05") == nil)
        #expect(viewModel.errorMessage == nil)
    }
}
