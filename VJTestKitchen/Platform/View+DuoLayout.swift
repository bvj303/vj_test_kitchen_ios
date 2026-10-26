import SwiftUI

// iPhone Duo (iOS 27.1) adaptations, confined here per the Platform/ convention so
// feature code never branches on OS versions or platforms. The deployment target
// is iOS 27.0 / macOS 26.0, so every iOS-27.1 API sits behind `#available`, and the
// iOS-only ones behind `#if os(iOS)`, each with a no-op fallback. See
// DECISIONS.md (2026-09-28) and Apple's "Preparing your app for iPhone Duo".

// MARK: - Folding region (reserved regions)

/// The x-ranges of every active *vertical* division reserved region (the fold of
/// a partially folded inner display held like a book) in `proxy`'s own
/// coordinate space. A horizontal fold (tabletop) is excluded: a scrolling column
/// that runs across it stays readable, and it doesn't cut a column in half
/// side-to-side. Empty before iOS 27.1, on macOS, and whenever the device isn't
/// partially folded.
@MainActor
func activeVerticalFolds(in proxy: GeometryProxy) -> [ClosedRange<CGFloat>] {
    #if os(iOS)
    if #available(iOS 27.1, *) {
        return proxy.reservedRegions(kind: .division)
            .filter { $0.isActive && $0.frame.height >= $0.frame.width }
            .map { $0.frame.minX...$0.frame.maxX }
    }
    #endif
    return []
}

/// Whether any division (fold) is active in `proxy`'s space, in either direction.
@MainActor
func hasActiveFold(in proxy: GeometryProxy) -> Bool {
    #if os(iOS)
    if #available(iOS 27.1, *) {
        return proxy.reservedRegions(kind: .division).contains { $0.isActive }
    }
    #endif
    return false
}

private struct ReadableColumnKey: Equatable {
    var width: CGFloat
    var folds: [ClosedRange<CGFloat>]
}

/// Keeps a scroll view's content in a readable column — at most `maxWidth` wide,
/// centered — that moves wholly onto one side of the fold when a partially folded
/// iPhone Duo would otherwise put it on the crease. Applied to the ScrollView
/// itself; content keeps its own padding. Replaces the old
/// `.frame(maxWidth:).frame(maxWidth: .infinity)` centering.
private struct FoldAwareScrollColumn: ViewModifier {
    let maxWidth: CGFloat
    @State private var column: FoldLayout.Column?
    @State private var containerWidth: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .contentMargins(
                .horizontal,
                EdgeInsets(
                    top: 0,
                    leading: column?.leading ?? 0,
                    bottom: 0,
                    trailing: column?.trailingInset(in: containerWidth) ?? 0
                ),
                for: .scrollContent
            )
            .background {
                GeometryReader { proxy in
                    let key = ReadableColumnKey(width: proxy.size.width, folds: activeVerticalFolds(in: proxy))
                    Color.clear.onChange(of: key, initial: true) { _, key in
                        containerWidth = key.width
                        column = FoldLayout.readableColumn(containerWidth: key.width, maxWidth: maxWidth, divisions: key.folds)
                    }
                }
            }
    }
}

/// The non-scrolling counterpart: sizes and places `content` in the same
/// fold-aware readable column within the full width it's given (forms, cards,
/// empty states).
private struct FoldAwareColumn: ViewModifier {
    let maxWidth: CGFloat
    @State private var column: FoldLayout.Column?

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: column?.width ?? maxWidth)
            .padding(.leading, column?.leading ?? 0)
            .frame(maxWidth: .infinity, alignment: column == nil ? .center : .leading)
            .background {
                GeometryReader { proxy in
                    let key = ReadableColumnKey(width: proxy.size.width, folds: activeVerticalFolds(in: proxy))
                    Color.clear.onChange(of: key, initial: true) { _, key in
                        column = FoldLayout.readableColumn(containerWidth: key.width, maxWidth: maxWidth, divisions: key.folds)
                    }
                }
            }
    }
}

extension View {
    /// See `FoldAwareScrollColumn`. Apply to a ScrollView.
    func foldAwareScrollColumn(maxWidth: CGFloat) -> some View {
        modifier(FoldAwareScrollColumn(maxWidth: maxWidth))
    }

    /// See `FoldAwareColumn`. Apply to a non-scrolling view.
    func foldAwareColumn(maxWidth: CGFloat) -> some View {
        modifier(FoldAwareColumn(maxWidth: maxWidth))
    }

    /// Reports whether a fold (division reserved region) is active — e.g. so
    /// Spatch's decorative flybys can sit out while the display is folded rather
    /// than flying through the crease.
    func onFoldActiveChange(_ action: @escaping (Bool) -> Void) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.onChange(of: hasActiveFold(in: proxy), initial: true) { _, active in
                    action(active)
                }
            }
        }
    }
}

// MARK: - Arrangement views

/// Two panes side by side (or stacked when the space is taller than wide) that
/// adapt to iPhone Duo's fold: iOS 27.1's `ArrangementView` with a split
/// arrangement, which places each pane wholly on one side of an active fold. The
/// HIG's recommendation for any layout that's already an HStack of two panes.
/// Before 27.1 and on macOS it falls back to the plain side-by-side layout with a
/// fixed-width primary pane. Keep navigation containers outside it (HIG).
struct PlatformSplitArrangement<Primary: View, Secondary: View>: View {
    var fallbackPrimaryWidth: CGFloat
    var fallbackSpacing: CGFloat = 24
    @ViewBuilder var primary: Primary
    @ViewBuilder var secondary: Secondary

    var body: some View {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            ArrangementView {
                primary
            } secondary: {
                secondary
            }
            .arrangementViewStyle(.split)
        } else {
            sideBySide
        }
        #else
        // The macOS SDK has no ArrangementView (a Mac window has no fold).
        sideBySide
        #endif
    }

    private var sideBySide: some View {
        HStack(alignment: .top, spacing: fallbackSpacing) {
            primary.frame(width: fallbackPrimaryWidth)
            secondary
        }
    }
}

// MARK: - Bars (vertical controls)

/// Which bar survives when a vertical controls column runs out of room.
enum PlatformBarCompression {
    /// Navigation screens: keep the tab bar, overflow toolbar items (the system
    /// default).
    case prefersTabBar
    /// Task screens: minimize the tab bar to keep the toolbar actions.
    case prefersToolbarItems
}

extension View {
    /// `toolbarVerticalCompressionBehavior(_:)` (iOS 27.1) — no-op before 27.1 and
    /// on macOS, which has no vertical bars.
    @ViewBuilder
    func platformBarCompression(_ behavior: PlatformBarCompression) -> some View {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            switch behavior {
            case .prefersTabBar: toolbarVerticalCompressionBehavior(.prefersTabBar)
            case .prefersToolbarItems: toolbarVerticalCompressionBehavior(.prefersToolbarItems)
            }
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// A toolbar item's priority for staying visible when a vertical bar runs out of
/// room (lower-priority items move to the overflow menu first).
enum PlatformToolbarPriority {
    case high, standard, low
}

extension ToolbarContent {
    /// `visibilityPriority(_:)` on iOS (27.0+). macOS toolbars don't overflow into
    /// a vertical column, so it's a no-op there (and the Mac target's 26.0
    /// deployment predates the API).
    @ToolbarContentBuilder
    func platformVisibilityPriority(_ priority: PlatformToolbarPriority) -> some ToolbarContent {
        #if os(iOS)
        switch priority {
        case .high: visibilityPriority(.high)
        case .standard: visibilityPriority(.automatic)
        case .low: visibilityPriority(.low)
        }
        #else
        self
        #endif
    }
}

/// Actions that belong in the system overflow menu. On iOS that's
/// `ToolbarOverflowMenu` — so on iPhone Duo, when a vertical bar overflows, these
/// share one menu with the items the system moved there. macOS has no system
/// overflow menu, so it gets an explicit menu button.
struct PlatformOverflowMenu<Content: View>: ToolbarContent {
    @ViewBuilder var content: Content

    var body: some ToolbarContent {
        #if os(iOS)
        ToolbarOverflowMenu { content }
        #else
        ToolbarItem(placement: .automatic) {
            Menu { content } label: { Label("More", systemImage: "ellipsis.circle") }
        }
        #endif
    }
}
