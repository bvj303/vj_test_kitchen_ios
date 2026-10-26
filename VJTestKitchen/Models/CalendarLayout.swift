import CoreGraphics

/// Which shape the Calendar takes, decided from the space it actually has. Pure
/// so it's unit-tested; `MealCalendarView` feeds it the size class, its measured
/// width and whether a vertical fold is active (see `activeVerticalFolds`).
enum CalendarLayout: Equatable {
    /// Quick Planner above the agenda, one scroll — a portrait phone.
    case stacked
    /// Planner beside the agenda (`PlatformSplitArrangement`), which on iPhone Duo
    /// puts each pane wholly on one side of the fold.
    case split

    /// Below this a planner pane and a readable agenda pane don't both fit side by
    /// side. iPhone Duo's inner display in landscape (~578pt beside its controls
    /// column) clears it; a portrait phone doesn't.
    static let minimumSplitWidth: CGFloat = 560

    static func resolve(isRegularWidth: Bool, containerWidth: CGFloat, hasVerticalFold: Bool) -> CalendarLayout {
        // A size-class-only rule ran the stacked column straight across a
        // book-style fold (the inner display is compact-width) and let the planner
        // fill a whole landscape screen.
        if isRegularWidth || hasVerticalFold || containerWidth >= minimumSplitWidth {
            return .split
        }
        return .stacked
    }

    // MARK: - Pane placement (compact-width split)

    /// Where the two panes sit when the split comes from a compact width (iPhone
    /// Duo's inner display). `ArrangementView` keeps to the size class and won't
    /// put two panes side by side in compact width, so the Calendar places them
    /// itself: the planner at its preferred width beside the agenda — or, with a
    /// vertical fold, the planner ending just before the crease and the agenda
    /// starting just after it.
    struct Panes: Equatable {
        var plannerWidth: CGFloat
        var spacing: CGFloat
    }

    static let paneSpacing: CGFloat = 16
    /// Clearance kept between each pane and the crease.
    static let foldGutter: CGFloat = 8
    /// Below this the Quick Planner's controls stop fitting.
    static let minimumPlannerWidth: CGFloat = 180

    /// `verticalFolds` are the active vertical folds' x-ranges in the panes'
    /// own coordinate space (see `activeVerticalFolds`).
    static func panes(
        containerWidth: CGFloat,
        verticalFolds: [ClosedRange<CGFloat>],
        preferredPlannerWidth: CGFloat
    ) -> Panes {
        guard let fold = verticalFolds.first(where: { $0.lowerBound > 0 && $0.upperBound < containerWidth }) else {
            return Panes(plannerWidth: preferredPlannerWidth, spacing: paneSpacing)
        }
        let plannerWidth = fold.lowerBound - foldGutter
        guard plannerWidth >= minimumPlannerWidth else {
            return Panes(plannerWidth: minimumPlannerWidth, spacing: paneSpacing)
        }
        let crease = fold.upperBound - fold.lowerBound
        return Panes(plannerWidth: plannerWidth, spacing: crease + 2 * foldGutter)
    }
}

