import Foundation
import Testing
@testable import VJTestKitchen

struct MinRatingFilterTests {
    @Test func allCasesAreOfferedHighestFirst() {
        #expect(MinRatingFilter.allCases == [.fourPointFive, .four, .threePointFive, .three])
    }

    @Test func minRatingMatchesEachThreshold() {
        #expect(MinRatingFilter.fourPointFive.minRating == 4.5)
        #expect(MinRatingFilter.four.minRating == 4.0)
        #expect(MinRatingFilter.threePointFive.minRating == 3.5)
        #expect(MinRatingFilter.three.minRating == 3.0)
    }

    @Test func labelsAreHumanReadable() {
        #expect(MinRatingFilter.fourPointFive.label == "4.5+ Stars")
        #expect(MinRatingFilter.three.chipLabel == "3.0+ ★")
    }
}
