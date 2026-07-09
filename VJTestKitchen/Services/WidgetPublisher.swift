import Foundation

/// Publishes widget snapshots from the view-model layer. Abstracted behind a
/// protocol (same DI pattern as the rest of the Services layer) so view models
/// stay unit-testable — tests inject a spy instead of writing to the real App
/// Group container and poking `WidgetCenter`.
///
/// Publishing is intentionally **fire-and-forget and best-effort**: a home
/// screen without the widget installed, or a missing App Group, must never
/// affect the in-app experience, so nothing here throws or reports errors.
protocol WidgetPublishing: Sendable {
    func publishTodaysMeals(plans: [MealPlanWithRecipe], today: String)
    func publishCooksIdea(suggestion: RecipeSuggestion, recipes: [Recipe])
    func publishGrocery(items: [GroceryItem])
}

/// Real implementation: builds the snapshot via `WidgetSnapshotBuilder`, writes
/// it to the shared container, and asks WidgetKit to refresh.
struct WidgetPublisher: WidgetPublishing {
    private let store: WidgetDataStore

    init(store: WidgetDataStore = .shared) {
        self.store = store
    }

    func publishTodaysMeals(plans: [MealPlanWithRecipe], today: String) {
        store.todaysMeals = WidgetSnapshotBuilder.todaysMeals(from: plans, today: today)
        store.reloadAllWidgets()
    }

    func publishCooksIdea(suggestion: RecipeSuggestion, recipes: [Recipe]) {
        store.cooksIdea = WidgetSnapshotBuilder.cooksIdea(suggestion: suggestion, recipes: recipes)
        store.reloadAllWidgets()
    }

    func publishGrocery(items: [GroceryItem]) {
        store.grocery = WidgetSnapshotBuilder.grocery(from: items)
        store.reloadAllWidgets()
    }
}
