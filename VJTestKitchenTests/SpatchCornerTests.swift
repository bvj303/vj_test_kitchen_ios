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

    @Test func onlyTrailingCornersReportIsTrailing() {
        #expect(SpatchCorner.topTrailing.isTrailing)
        #expect(SpatchCorner.bottomTrailing.isTrailing)
        #expect(SpatchCorner.midTrailing.isTrailing)
        #expect(!SpatchCorner.topLeading.isTrailing)
        #expect(!SpatchCorner.bottomLeading.isTrailing)
        #expect(!SpatchCorner.midLeading.isTrailing)
    }

    @Test func slideEdgeMatchesTheScreenSideEachPositionHugs() {
        #expect(SpatchCorner.topLeading.slideEdge == .top)
        #expect(SpatchCorner.topTrailing.slideEdge == .top)
        #expect(SpatchCorner.bottomLeading.slideEdge == .bottom)
        #expect(SpatchCorner.bottomTrailing.slideEdge == .bottom)
        #expect(SpatchCorner.midLeading.slideEdge == .leading)
        #expect(SpatchCorner.midTrailing.slideEdge == .trailing)
    }

    @Test func popPositionsCoverAllFourScreenSides() {
        // The whole point of the mid-edge positions: Spatch can emerge from
        // any of the four sides of the screen, not just top/bottom corners.
        let edges = Set(SpatchCorner.allCases.map(\.slideEdge))
        #expect(edges.count == 4)
    }

    @Test func cameoPositionsAreBottomOnlySoTheyClearTopContent() {
        // Cameos must never sit over titles or the top stat cards — they're
        // pinned to the bottom margin.
        #expect(SpatchCorner.cameoPositions == [.bottomLeading, .bottomTrailing])
        for _ in 0..<40 {
            #expect(SpatchCorner.cameoPositions.contains(SpatchCorner.randomCameo()))
        }
    }

    @Test func randomCameoExcludingCurrentRelocatesToTheOtherBottomCorner() {
        #expect(SpatchCorner.randomCameo(excluding: .bottomLeading) == .bottomTrailing)
        #expect(SpatchCorner.randomCameo(excluding: .bottomTrailing) == .bottomLeading)
    }
}
