import SwiftUI

/// A lightweight command bus so menu-bar commands (which live in the `.commands`
/// scene modifier, outside the window's view tree) can drive in-app navigation
/// and actions owned by views like `MainTabView` and `RecipeListView`. Injected
/// into the environment at the app root and observed by those views.
///
/// Although the menu bar is a macOS concept, `.commands` also surfaces keyboard
/// shortcuts to iPad hardware keyboards, so this is injected on both platforms.
///
/// Requests are monotonically-increasing counters rather than `Bool` flags so a
/// repeat of the same command (e.g. ⌘N twice) still fires `.onChange` without a
/// manual reset-to-false dance. `pendingTab` is a plain optional the observer
/// clears once consumed.
@Observable
final class AppCommands {
    /// A requested top-level tab switch; the observer applies it and resets to nil.
    var pendingTab: AppTab?
    /// Bumped to request the Recipes "New Recipe" sheet.
    var newRecipeRequests = 0
    /// Bumped to request focusing the Recipes search field.
    var searchRequests = 0

    func selectTab(_ tab: AppTab) {
        pendingTab = tab
    }

    func requestNewRecipe() {
        pendingTab = .recipes
        newRecipeRequests += 1
    }

    func requestSearch() {
        pendingTab = .recipes
        searchRequests += 1
    }
}
