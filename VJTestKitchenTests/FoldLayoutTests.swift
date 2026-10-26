import Foundation
import Testing
@testable import VJTestKitchen

/// iPhone Duo: when partially folded, a folding region (a *division* reserved
/// region) splits the inner display. A centered reading column would land on the
/// crease, so it moves wholly onto one side. Grids use an even column count so
/// no column straddles a centered fold. Pure math — ReservedRegion itself can't be
/// constructed in tests, so callers pass the division's x-range.
struct FoldLayoutTests {
    // MARK: - Readable column

    @Test func centersTheColumnWhenThereIsNoFold() {
        let column = FoldLayout.readableColumn(containerWidth: 1000, maxWidth: 700, divisions: [])
        #expect(column == .init(leading: 150, width: 700))
    }

    @Test func usesTheFullWidthWhenTheContainerIsNarrowerThanTheCap() {
        let column = FoldLayout.readableColumn(containerWidth: 400, maxWidth: 700, divisions: [])
        #expect(column == .init(leading: 0, width: 400))
    }

    @Test func movesTheColumnOffACenteredFoldOntoTheTrailingSideOnATie() {
        // 800pt wide, fold occupies 390...410 → two 390pt halves.
        let column = FoldLayout.readableColumn(containerWidth: 800, maxWidth: 700, divisions: [390...410])
        #expect(column == .init(leading: 410, width: 390))
    }

    @Test func prefersTheWiderSideOfAnOffCenterFold() {
        // Leading side 300pt, trailing side 480pt.
        let column = FoldLayout.readableColumn(containerWidth: 800, maxWidth: 400, divisions: [300...320])
        #expect(column == .init(leading: 360, width: 400)) // centered within 320...800
        let leadingHeavy = FoldLayout.readableColumn(containerWidth: 800, maxWidth: 1000, divisions: [500...520])
        #expect(leadingHeavy == .init(leading: 0, width: 500))
    }

    @Test func leavesTheColumnAloneWhenItDoesNotTouchTheFold() {
        // A fold near the leading edge doesn't intersect a narrow centered column.
        let column = FoldLayout.readableColumn(containerWidth: 1000, maxWidth: 300, divisions: [100...120])
        #expect(column == .init(leading: 350, width: 300))
    }

    @Test func columnNeverOverlapsAnyDivision() {
        for width in stride(from: CGFloat(600), through: 1200, by: 50) {
            let mid = width / 2
            let fold = (mid - 12)...(mid + 12)
            let column = FoldLayout.readableColumn(containerWidth: width, maxWidth: 700, divisions: [fold])
            let range = column.leading...(column.leading + column.width)
            #expect(!range.overlaps(fold) || range.upperBound == fold.lowerBound || range.lowerBound == fold.upperBound,
                    "width \(width): column \(range) overlaps fold \(fold)")
            #expect(column.leading >= 0 && column.leading + column.width <= width)
        }
    }

    @Test func trailingInsetComplementsTheColumn() {
        let column = FoldLayout.readableColumn(containerWidth: 800, maxWidth: 700, divisions: [390...410])
        #expect(column.trailingInset(in: 800) == 0)
        #expect(FoldLayout.readableColumn(containerWidth: 1000, maxWidth: 700, divisions: []).trailingInset(in: 1000) == 150)
    }

    // MARK: - Hero image height

    @Test func heroKeepsItsFullHeightOnATallScreen() {
        #expect(FoldLayout.heroHeight(viewportHeight: 800) == 220)
    }

    @Test func heroShrinksOnShortViewportsSoContentStaysVisible() {
        // iPhone Duo closed in landscape, or one half of the inner display in
        // tabletop: a fixed 220pt image would fill most of the visible height.
        let short = FoldLayout.heroHeight(viewportHeight: 360)
        #expect(short < 220)
        #expect(short <= 360 * 0.35)
    }

    @Test func heroNeverCollapsesBelowItsFloor() {
        #expect(FoldLayout.heroHeight(viewportHeight: 200) == 120)
        #expect(FoldLayout.heroHeight(viewportHeight: 0) == 120)
    }

    // MARK: - Even grid columns

    @Test func gridColumnCountIsEvenSoNoColumnSitsOnACenteredFold() {
        // 3 would fit (3*150 + 2*16 = 482 <= 500); round down to 2.
        #expect(FoldLayout.evenColumnCount(availableWidth: 500, minimumItemWidth: 150, spacing: 16) == 2)
        // 5 would fit in 1100 at 200 min; round down to 4.
        #expect(FoldLayout.evenColumnCount(availableWidth: 1100, minimumItemWidth: 200, spacing: 20) == 4)
        #expect(FoldLayout.evenColumnCount(availableWidth: 900, minimumItemWidth: 200, spacing: 20) == 4)
    }

    @Test func gridNeverDropsBelowOneColumn() {
        #expect(FoldLayout.evenColumnCount(availableWidth: 120, minimumItemWidth: 150, spacing: 16) == 1)
        #expect(FoldLayout.evenColumnCount(availableWidth: 0, minimumItemWidth: 150, spacing: 16) == 1)
        // A single column that fits stays a single column rather than becoming 0.
        #expect(FoldLayout.evenColumnCount(availableWidth: 200, minimumItemWidth: 150, spacing: 16) == 1)
    }
}
