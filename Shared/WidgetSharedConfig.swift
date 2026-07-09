import Foundation

/// Constants shared between the app and its WidgetKit extension.
///
/// The widget extension runs in a **separate process with no Supabase session**,
/// so instead of authenticating and querying, it reads small denormalized
/// snapshots the app publishes into a shared **App Group** container (see
/// `WidgetDataStore`). This type holds the two things both sides must agree on:
/// the App Group identifier and the widget `kind` strings.
///
/// Compiled into both the app targets and the widget-extension targets (via the
/// `Shared/` source glob in `project.yml`), so the two processes can never drift
/// on these values.
enum WidgetSharedConfig {
    /// App Group container both the app and the widget read/write.
    ///
    /// macOS requires the Team ID prefix on the group identifier (and therefore
    /// on the `UserDefaults(suiteName:)` name that must match the entitlement),
    /// whereas iOS uses the bare `group.` form — a genuine cross-platform gotcha,
    /// so the identifier is resolved per platform here and the two entitlement
    /// files (`VJTestKitchenWidgets-iOS`/`-macOS`) carry the matching strings.
    static var appGroupIdentifier: String {
        #if os(macOS)
        "89R449GG5Z.group.com.bvj303.vjtestkitchen"
        #else
        "group.com.bvj303.vjtestkitchen"
        #endif
    }

    /// Stable `kind` identifiers for each widget — one per `Widget` in the
    /// bundle, also used by `WidgetCenter.reloadTimelines(ofKind:)` if a future
    /// caller wants to reload a single widget rather than all of them.
    enum Kind {
        static let cooksIdea = "CooksIdeaWidget"
        static let todaysMeals = "TodaysMealsWidget"
        static let grocery = "GroceryListWidget"
    }

    /// Deep links a tapped widget opens, routed by `VJTestKitchenApp.onOpenURL`
    /// to the matching tab (see `AppTab(deepLinkHost:)`). Reuses the app's
    /// already-registered `vjtestkitchen://` scheme.
    enum DeepLink {
        static let home = URL(string: "vjtestkitchen://home")!
        static let recipes = URL(string: "vjtestkitchen://recipes")!
        static let grocery = URL(string: "vjtestkitchen://grocery")!
        static let calendar = URL(string: "vjtestkitchen://calendar")!
    }
}
