import Testing
@testable import VJTestKitchen

struct SpatchCornerTests {
    @Test func allCasesHaveDistinctAlignments() {
        let alignments = Set(SpatchCorner.allCases.map { "\($0.alignment)" })
        #expect(alignments.count == SpatchCorner.allCases.count)
    }

    @Test func topCornersInsetMoreThanBottomCorners() {
        #expect(SpatchCorner.topLeading.edgeInsets.top > SpatchCorner.bottomLeading.edgeInsets.top)
        #expect(SpatchCorner.topTrailing.edgeInsets.top > SpatchCorner.bottomTrailing.edgeInsets.top)
    }

    @Test func randomExcludingCurrentNeverReturnsTheSameCorner() {
        for corner in SpatchCorner.allCases {
            for _ in 0..<20 {
                #expect(SpatchCorner.random(excluding: corner) != corner)
            }
        }
    }

    @Test func randomWithoutExclusionReturnsAValidCorner() {
        #expect(SpatchCorner.allCases.contains(SpatchCorner.random()))
    }
}
