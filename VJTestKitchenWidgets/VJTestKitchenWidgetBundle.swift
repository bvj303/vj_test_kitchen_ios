import WidgetKit
import SwiftUI

/// Entry point for the VJ Test Kitchen widget extension — the three home-screen
/// / desktop widgets, all reading snapshots the app publishes to the shared App
/// Group container (see `WidgetDataStore` / `WidgetPublisher`).
@main
struct VJTestKitchenWidgetBundle: WidgetBundle {
    var body: some Widget {
        CooksIdeaWidget()
        TodaysMealsWidget()
        GroceryListWidget()
    }
}
