import Foundation
import Testing
@testable import VJTestKitchen

struct WeatherFormattingTests {
    @Test func formatsFahrenheitForUSLocale() {
        // 22°C == 71.6°F, rounds to 72.
        let measurement = Measurement(value: 22, unit: UnitTemperature.celsius)
        #expect(WeatherFormatting.temperatureLabel(measurement, locale: Locale(identifier: "en_US")) == "72°")
    }

    @Test func formatsCelsiusForMetricLocale() {
        // 72°F == 22.2°C, rounds to 22.
        let measurement = Measurement(value: 72, unit: UnitTemperature.fahrenheit)
        #expect(WeatherFormatting.temperatureLabel(measurement, locale: Locale(identifier: "fr_FR")) == "22°")
    }

    @Test func roundsToWholeDegreesAndHasNoUnitLetter() {
        let measurement = Measurement(value: 71.4, unit: UnitTemperature.fahrenheit)
        let label = WeatherFormatting.temperatureLabel(measurement, locale: Locale(identifier: "en_US"))
        #expect(label == "71°")
        #expect(!label.contains("F"))
        #expect(!label.contains("C"))
    }
}
