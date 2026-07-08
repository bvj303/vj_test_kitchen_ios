import SwiftUI

/// A lightweight command bus so menu-bar commands (which live in the `.commands`
/// scene modifier, outside the window's view tree) can drive in-app navigation
/// and actions owned by views like `MainTabView`, `RecipeListView`, and
/// `GroceryListView`. Injected into the environment at the app root and observed
/// by those views.
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
    /// The tab currently on screen, mirrored from `MainTabView.selection` so
    /// context-aware commands (⌘N) can dispatch to the right screen's action.
    var currentTab: AppTab = .home
    /// Bumped to request the Recipes "New Recipe" sheet.
    var newRecipeRequests = 0
    /// Bumped to request the Grocery "Add Item" sheet.
    var newGroceryItemRequests = 0
    /// Bumped to request focusing the Recipes search field.
    var searchRequests = 0
    /// Bumped to request the visible screen reload its data (⌘R).
    var refreshRequests = 0

    /// The File ▸ New menu title, reflecting what ⌘N will create on the current
    /// tab — the way native Mac apps keep the New item honest.
    var newItemTitle: String {
        switch currentTab {
        case .grocery: return "New Grocery Item"
        default: return "New Recipe"
        }
    }

    func selectTab(_ tab: AppTab) {
        pendingTab = tab
    }

    /// Context-aware ⌘N: create on whatever tab is showing. Grocery adds a list
    /// item in place; every other tab creates a recipe (switching to Recipes).
    func requestNew() {
        switch currentTab {
        case .grocery:
            newGroceryItemRequests += 1
        default:
            requestNewRecipe()
        }
    }

    func requestNewRecipe() {
        pendingTab = .recipes
        newRecipeRequests += 1
    }

    func requestSearch() {
        pendingTab = .recipes
        searchRequests += 1
    }

    /// ⌘R: ask the currently-visible screen to reload. Deliberately does not
    /// change tabs — it acts on whatever the user is looking at.
    func requestRefresh() {
        refreshRequests += 1
    }
}
