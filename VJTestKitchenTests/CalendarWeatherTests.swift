import Foundation
import Testing
@testable import VJTestKitchen

// MARK: - Shared weather test doubles (also used by SettingsViewModelTests)

final class FakeWeatherForecaster: WeatherForecasting, @unchecked Sendable {
    var forecasts: [DailyForecast] = []
    var attributionToReturn: WeatherAttributionInfo?
    var errorToThrow: Error?
    private(set) var requestedCoordinates: [Coordinate] = []

    func dailyForecast(for coordinate: Coordinate) async throws -> [DailyForecast] {
        requestedCoordinates.append(coordinate)
        if let errorToThrow { throw errorToThrow }
        return forecasts
    }

    func attribution() async throws -> WeatherAttributionInfo {
        if let attributionToReturn { return attributionToReturn }
        throw FakeWeatherError()
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
    var enabled = false
    func loadUseCurrentLocation() -> Bool { enabled }
    func saveUseCurrentLocation(_ enabled: Bool) { self.enabled = enabled }
}

struct FakeWeatherError: Error {}

func makeForecast(date: String, symbol: String = "sun.max.fill", high: Double = 80, low: Double = 60) -> DailyForecast {
    DailyForecast(
        date: date,
        symbolName: symbol,
        condition: "Clear",
        highTemperature: Measurement(value: high, unit: .fahrenheit),
        lowTemperature: Measurement(value: low, unit: .fahrenheit)
    )
}

// MARK: - MealCalendarViewModel weather behavior

@MainActor
struct CalendarWeatherTests {
    @Test func loadWeatherPopulatesForecastAndAttributionWhenEnabled() async {
        let store = FakeWeatherPreferenceStore()
        store.enabled = true
        let location = FakeLocationProvider()
        location.authorization = .authorized
        let forecaster = FakeWeatherForecaster()
        forecaster.forecasts = [makeForecast(date: "2026-07-05"), makeForecast(date: "2026-07-06")]
        forecaster.attributionToReturn = WeatherAttributionInfo(
            markLightURL: URL(string: "https://weatherkit.apple.com/light.png")!,
            markDarkURL: URL(string: "https://weatherkit.apple.com/dark.png")!,
            legalPageURL: URL(string: "https://weatherkit.apple.com/legal")!
        )

        let viewModel = MealCalendarViewModel(
            mealPlanService: FakeMealPlanService(),
            recipeService: FakeMealPlanRecipeService(),
            weatherForecaster: forecaster,
            locationProvider: location,
            weatherPreferenceStore: store
        )

        await viewModel.loadWeather()

        #expect(viewModel.forecast(for: "2026-07-05")?.symbolName == "sun.max.fill")
        #expect(viewModel.forecast(for: "2026-07-06") != nil)
        #expect(viewModel.forecast(for: "2026-07-07") == nil)
        #expect(viewModel.weatherAttribution?.legalPageURL.absoluteString == "https://weatherkit.apple.com/legal")
        #expect(forecaster.requestedCoordinates.first == location.coordinateToReturn)
    }

    @Test func loadWeatherClearsAndSkipsFetchWhenDisabled() async {
        let store = FakeWeatherPreferenceStore()
        store.enabled = false
        let forecaster = FakeWeatherForecaster()
        forecaster.forecasts = [makeForecast(date: "2026-07-05")]

        let viewModel = MealCalendarViewModel(
            mealPlanService: FakeMealPlanService(),
            recipeService: FakeMealPlanRecipeService(),
            weatherForecaster: forecaster,
            locationProvider: FakeLocationProvider(),
            weatherPreferenceStore: store
        )

        await viewModel.loadWeather()

        #expect(viewModel.forecast(for: "2026-07-05") == nil)
        #expect(viewModel.weatherAttribution == nil)
        #expect(forecaster.requestedCoordinates.isEmpty)
    }

    @Test func loadWeatherSwallowsErrorsWithoutRaisingTheMealPlanAlert() async {
        let store = FakeWeatherPreferenceStore()
        store.enabled = true
        let location = FakeLocationProvider()
        location.authorization = .authorized
        location.errorToThrow = LocationError.denied

        let viewModel = MealCalendarViewModel(
            mealPlanService: FakeMealPlanService(),
            recipeService: FakeMealPlanRecipeService(),
            weatherForecaster: FakeWeatherForecaster(),
            locationProvider: location,
            weatherPreferenceStore: store
        )

        await viewModel.loadWeather()

        #expect(viewModel.forecast(for: "2026-07-05") == nil)
        #expect(viewModel.errorMessage == nil)
    }
}
