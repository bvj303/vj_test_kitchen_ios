import Foundation
import Testing
@testable import VJTestKitchen

/// The Calendar picks between one stacked column (Quick Planner above the
/// agenda) and two panes side by side (planner beside the agenda) from the space
/// it actually has — not just the size class. On iPhone Duo the inner display is
/// compact-width, so a size-class-only rule ran the stacked column straight
/// across a book-style fold and let the planner fill a whole landscape screen.
struct CalendarLayoutTests {
    @Test func stacksOnAPortraitPhoneWidth() {
        let layout = CalendarLayout.resolve(isRegularWidth: false, containerWidth: 366, hasVerticalFold: false)
        #expect(layout == .stacked)
    }

    @Test func splitsOnRegularWidthRegardlessOfSize() {
        let layout = CalendarLayout.resolve(isRegularWidth: true, containerWidth: 500, hasVerticalFold: false)
        #expect(layout == .split)
    }

    @Test func splitsAcrossAnActiveVerticalFoldSoNeitherPaneSitsOnTheCrease() {
        // Even at a narrow compact width: each pane goes wholly to one side.
        let layout = CalendarLayout.resolve(isRegularWidth: false, containerWidth: 366, hasVerticalFold: true)
        #expect(layout == .split)
    }

    @Test func splitsOnAWideCompactScreenSoThePlannerDoesNotFillIt() {
        // iPhone Duo's inner display in landscape: ~578pt beside the controls column.
        let layout = CalendarLayout.resolve(isRegularWidth: false, containerWidth: 578, hasVerticalFold: false)
        #expect(layout == .split)
    }

    @Test func theSplitThresholdIsInclusive() {
        let atThreshold = CalendarLayout.resolve(
            isRegularWidth: false,
            containerWidth: CalendarLayout.minimumSplitWidth,
            hasVerticalFold: false
        )
        let justUnder = CalendarLayout.resolve(
            isRegularWidth: false,
            containerWidth: CalendarLayout.minimumSplitWidth - 1,
            hasVerticalFold: false
        )
        #expect(atThreshold == .split)
        #expect(justUnder == .stacked)
    }

    @Test func anUnmeasuredContainerStacks() {
        // Before the first layout pass the width reads 0 — never split on that.
        let layout = CalendarLayout.resolve(isRegularWidth: false, containerWidth: 0, hasVerticalFold: false)
        #expect(layout == .stacked)
    }

    // MARK: - Pane placement (compact-width split)

    @Test func withoutAFoldThePlannerTakesItsPreferredWidth() {
        let panes = CalendarLayout.panes(containerWidth: 578, verticalFolds: [], preferredPlannerWidth: 260)
        #expect(panes == .init(plannerWidth: 260, spacing: CalendarLayout.paneSpacing))
    }

    @Test func aFoldPutsThePlannerWhollyBeforeTheCreaseAndTheAgendaAfterIt() {
        // 466pt wide, crease at 223...243.
        let panes = CalendarLayout.panes(containerWidth: 466, verticalFolds: [223...243], preferredPlannerWidth: 260)
        let gutter = CalendarLayout.foldGutter
        #expect(panes == .init(plannerWidth: 223 - gutter, spacing: 20 + 2 * gutter))
        // The agenda then starts past the crease.
        #expect(panes.plannerWidth + panes.spacing == 243 + gutter)
    }

    @Test func aFoldOutsideTheContainerIsIgnored() {
        let panes = CalendarLayout.panes(containerWidth: 578, verticalFolds: [700...720], preferredPlannerWidth: 260)
        #expect(panes == .init(plannerWidth: 260, spacing: CalendarLayout.paneSpacing))
    }

    @Test func thePlannerNeverCollapsesBelowItsMinimumBesideAFoldNearTheEdge() {
        let panes = CalendarLayout.panes(containerWidth: 466, verticalFolds: [40...60], preferredPlannerWidth: 260)
        #expect(panes.plannerWidth == CalendarLayout.minimumPlannerWidth)
    }
}
