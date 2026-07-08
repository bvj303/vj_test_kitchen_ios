import Foundation

/// Maps the app's domain models to the primitive `…Snapshot` payloads the
/// widgets read. Kept app-side (not in `Shared/`) precisely because it depends
/// on app types like `MealTypeStyle` and `RecipeSuggester`'s output — the
/// snapshots themselves stay dependency-free so they can compile into the widget
/// module. Pure and static, so the mapping is unit-testable without the store,
/// a session, or a running widget.
enum WidgetSnapshotBuilder {
    /// How many meals / recipes / grocery names a snapshot carries — a small cap
    /// since even the large widget only shows a handful, and it keeps the shared
    /// container tiny.
    static let mealLimit = 4
    static let ideaRecipeLimit = 3
    static let groceryPreviewLimit = 5

    /// Today's meals, ordered as they'd be eaten (Breakfast→Lunch→Dinner→Snack
    /// via `MealTypeStyle`, ties broken by id for stable ordering) and capped.
    /// Each meal carries its resolved SF Symbol so the widget stays dumb.
    static func todaysMeals(
        from plans: [MealPlanWithRecipe],
        today: String,
        limit: Int = mealLimit
    ) -> TodaysMealsSnapshot {
        let meals = plans
            .filter { $0.date == today }
            .sorted { lhs, rhs in
                let l = MealTypeStyle.sortOrder(for: lhs.mealType)
                let r = MealTypeStyle.sortOrder(for: rhs.mealType)
                if l != r { return l < r }
                return lhs.id < rhs.id
            }
            .prefix(limit)
            .map {
                TodaysMealsSnapshot.Meal(
                    mealType: $0.mealType,
                    recipeTitle: $0.recipeTitle,
                    recipeId: $0.recipeId,
                    iconSymbol: MealTypeStyle.icon(for: $0.mealType)
                )
            }
        return TodaysMealsSnapshot(date: today, meals: Array(meals))
    }

    /// The current cooking suggestion plus a few matching recipes to feature.
    static func cooksIdea(
        suggestion: RecipeSuggestion,
        recipes: [Recipe],
        limit: Int = ideaRecipeLimit
    ) -> CooksIdeaSnapshot {
        CooksIdeaSnapshot(
            title: suggestion.title,
            subtitle: suggestion.subtitle,
            symbol: suggestion.symbol,
            recipes: recipes.prefix(limit).map {
                CooksIdeaSnapshot.Recipe(id: $0.id, title: $0.title)
            }
        )
    }

    /// The grocery list's still-to-buy tally and a preview of unchecked names,
    /// in the list's own order.
    static func grocery(
        from items: [GroceryItem],
        previewLimit: Int = groceryPreviewLimit
    ) -> GrocerySnapshot {
        let unchecked = items.filter { !$0.isChecked }
        return GrocerySnapshot(
            toBuyCount: unchecked.count,
            checkedCount: items.count - unchecked.count,
            totalCount: items.count,
            preview: unchecked.prefix(previewLimit).map(\.name)
        )
    }
}
