import Foundation
import Testing
@testable import VJTestKitchen

struct PrepTimeFilterTests {
    @Test func upperBoundOptionsHaveMaxOnly() {
        #expect(PrepTimeFilter.under30.minMinutes == nil)
        #expect(PrepTimeFilter.under30.maxMinutes == 30)
        #expect(PrepTimeFilter.under45.maxMinutes == 45)
        #expect(PrepTimeFilter.under60.maxMinutes == 60)
    }

    @Test func lowerBoundOptionsHaveMinOnly() {
        #expect(PrepTimeFilter.longCooks.minMinutes == 120)
        #expect(PrepTimeFilter.longCooks.maxMinutes == nil)
        #expect(PrepTimeFilter.overnight.minMinutes == 480)
        #expect(PrepTimeFilter.overnight.maxMinutes == nil)
    }

    @Test func allCasesAreOfferedInMenuOrder() {
        #expect(PrepTimeFilter.allCases == [.under30, .under45, .under60, .longCooks, .overnight])
    }

    @Test func labelsAreHumanReadable() {
        #expect(PrepTimeFilter.under60.label == "1 hr or less")
        #expect(PrepTimeFilter.longCooks.label == "Long Cooks (2 hr+)")
        #expect(PrepTimeFilter.overnight.label == "Overnight (8 hr+)")
        #expect(PrepTimeFilter.under30.chipLabel == "≤ 30 min")
        #expect(PrepTimeFilter.overnight.chipLabel == "Overnight")
    }
}
