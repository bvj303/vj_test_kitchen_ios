import CoreGraphics

/// Layout math for iPhone Duo's folding display, kept pure so it's unit-tested
/// (a `ReservedRegion` can't be constructed in a test). The SwiftUI side lives in
/// `Platform/View+DuoLayout.swift`, which reads the live division regions and
/// feeds their x-ranges in here.
enum FoldLayout {
    /// A horizontal span for a readable content column: where it starts and how
    /// wide it is, in the container's coordinate space.
    struct Column: Equatable {
        var leading: CGFloat
        var width: CGFloat

        func trailingInset(in containerWidth: CGFloat) -> CGFloat {
            max(0, containerWidth - leading - width)
        }
    }

    /// A column at most `maxWidth` wide, centered in the container — unless a
    /// vertical fold (a *division* reserved region, given as its x-range) crosses
    /// where that column would sit. Then the column moves wholly onto the wider
    /// side of the fold (trailing on a tie, matching where a split view shows its
    /// detail pane), centered within that side, so no text or control lands on the
    /// crease. This is the "move only what's necessary" adjustment the HIG asks
    /// for: when fully open (no active division) nothing changes.
    static func readableColumn(
        containerWidth: CGFloat,
        maxWidth: CGFloat,
        divisions: [ClosedRange<CGFloat>]
    ) -> Column {
        let width = max(0, min(maxWidth, containerWidth))
        let centered = Column(leading: (containerWidth - width) / 2, width: width)
        let centeredSpan = centered.leading...(centered.leading + centered.width)

        // Only a division that actually cuts through the centered column matters.
        guard let fold = divisions.first(where: { strictlyOverlaps($0, centeredSpan) }) else {
            return centered
        }
        let leadingSide = 0...max(0, fold.lowerBound)
        let trailingSide = min(containerWidth, fold.upperBound)...containerWidth
        let side = sideWidth(trailingSide) >= sideWidth(leadingSide) ? trailingSide : leadingSide
        let sideWidth = sideWidth(side)
        let columnWidth = min(maxWidth, sideWidth)
        return Column(leading: side.lowerBound + (sideWidth - columnWidth) / 2, width: columnWidth)
    }

    /// The number of grid columns that fit, rounded DOWN to an even number (but
    /// never below one), so a grid on the inner display divides cleanly at a
    /// centered fold instead of putting a middle column on the crease (HIG: "In a
    /// grid-style layout, prefer an even number of columns").
    static func evenColumnCount(availableWidth: CGFloat, minimumItemWidth: CGFloat, spacing: CGFloat) -> Int {
        guard minimumItemWidth > 0 else { return 1 }
        let fitting = Int(((availableWidth + spacing) / (minimumItemWidth + spacing)).rounded(.down))
        if fitting <= 1 { return 1 }
        return fitting.isMultiple(of: 2) ? fitting : fitting - 1
    }

    /// A hero image's height for a scroll viewport of `viewportHeight`: its full
    /// 220pt on a normal screen, but no more than ~a third of the viewport, so on
    /// short layouts (iPhone Duo closed in landscape, or half the inner display in
    /// tabletop) the recipe itself stays visible under it. Never below 120pt.
    static func heroHeight(viewportHeight: CGFloat) -> CGFloat {
        min(220, max(120, (viewportHeight * 0.33).rounded(.down)))
    }

    private static func sideWidth(_ side: ClosedRange<CGFloat>) -> CGFloat {
        side.upperBound - side.lowerBound
    }

    /// Overlap with positive length — merely touching at an edge doesn't count.
    private static func strictlyOverlaps(_ a: ClosedRange<CGFloat>, _ b: ClosedRange<CGFloat>) -> Bool {
        a.lowerBound < b.upperBound && b.lowerBound < a.upperBound
    }
}
