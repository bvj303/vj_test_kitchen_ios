import Foundation
import Testing
@testable import VJTestKitchen

struct AppIconOptionTests {
    @Test func classicIsThePrimaryIcon() {
        #expect(AppIconOption.classic.alternateIconName == nil)
    }

    @Test func alternatesHaveDistinctIconSetNames() {
        let names = AppIconOption.allCases.compactMap(\.alternateIconName)
        #expect(names.count == AppIconOption.allCases.count - 1)
        #expect(Set(names).count == names.count)
    }

    @Test func alternateIconNamesMatchAssetCatalogSets() {
        #expect(AppIconOption.pizzaSurf.alternateIconName == "AppIconPizza")
        #expect(AppIconOption.rocketRide.alternateIconName == "AppIconRocket")
        #expect(AppIconOption.balloonRide.alternateIconName == "AppIconBalloon")
    }

    @Test func previewImageNamesAreUnique() {
        let names = AppIconOption.allCases.map(\.previewImageName)
        #expect(Set(names).count == names.count)
    }

    @Test func titlesAreUniqueAndNonEmpty() {
        let titles = AppIconOption.allCases.map(\.title)
        #expect(Set(titles).count == titles.count)
        #expect(titles.allSatisfy { !$0.isEmpty })
    }

    @Test func mapsSystemIconNameBackToOption() {
        #expect(AppIconOption.option(forAlternateIconName: nil) == .classic)
        #expect(AppIconOption.option(forAlternateIconName: "AppIconPizza") == .pizzaSurf)
        #expect(AppIconOption.option(forAlternateIconName: "AppIconRocket") == .rocketRide)
        #expect(AppIconOption.option(forAlternateIconName: "AppIconBalloon") == .balloonRide)
    }

    @Test func unknownSystemIconNameFallsBackToClassic() {
        #expect(AppIconOption.option(forAlternateIconName: "AppIconRetired") == .classic)
    }

    @Test func classicIsFirstInPickerOrder() {
        #expect(AppIconOption.allCases.first == .classic)
    }
}
