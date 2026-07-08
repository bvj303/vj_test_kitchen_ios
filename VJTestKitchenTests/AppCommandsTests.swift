import Testing
@testable import VJTestKitchen

/// The command bus is pure state, so its routing logic (which counter a
/// keyboard shortcut bumps, and whether it forces a tab switch) is unit-testable
/// without any UI. The view wiring that consumes these counters is exercised in
/// the running app, not here.
struct AppCommandsTests {

    // MARK: - Context-aware ⌘N

    @Test func newOnRecipesCreatesRecipe() {
        let commands = AppCommands()
        commands.currentTab = .recipes

        commands.requestNew()

        #expect(commands.newRecipeRequests == 1)
        #expect(commands.newGroceryItemRequests == 0)
        // Already on Recipes, but requesting the tab is harmless and keeps the
        // menu working when invoked from a background window state.
        #expect(commands.pendingTab == .recipes)
    }

    @Test func newOnGroceryCreatesGroceryItem() {
        let commands = AppCommands()
        commands.currentTab = .grocery

        commands.requestNew()

        #expect(commands.newGroceryItemRequests == 1)
        #expect(commands.newRecipeRequests == 0)
        // Grocery's add lives on the visible tab — no tab switch needed.
        #expect(commands.pendingTab == nil)
    }

    @Test func newOnOtherTabsFallsBackToRecipe() {
        for tab: AppTab in [.home, .planner, .calendar] {
            let commands = AppCommands()
            commands.currentTab = tab

            commands.requestNew()

            #expect(commands.newRecipeRequests == 1)
            #expect(commands.newGroceryItemRequests == 0)
            #expect(commands.pendingTab == .recipes)
        }
    }

    @Test func newItemTitleReflectsCurrentTab() {
        let commands = AppCommands()

        commands.currentTab = .grocery
        #expect(commands.newItemTitle == "New Grocery Item")

        commands.currentTab = .recipes
        #expect(commands.newItemTitle == "New Recipe")

        commands.currentTab = .home
        #expect(commands.newItemTitle == "New Recipe")
    }

    // MARK: - Repeat firing

    @Test func repeatedNewBumpsCounterEachTime() {
        let commands = AppCommands()
        commands.currentTab = .recipes

        commands.requestNew()
        commands.requestNew()
        commands.requestNew()

        // Monotonic counters (not Bool flags) so onChange fires on every ⌘N.
        #expect(commands.newRecipeRequests == 3)
    }

    // MARK: - Search / Refresh / tab selection

    @Test func searchForcesRecipesTab() {
        let commands = AppCommands()
        commands.currentTab = .grocery

        commands.requestSearch()

        #expect(commands.searchRequests == 1)
        #expect(commands.pendingTab == .recipes)
    }

    @Test func refreshBumpsCounterWithoutChangingTab() {
        let commands = AppCommands()
        commands.currentTab = .calendar

        commands.requestRefresh()

        #expect(commands.refreshRequests == 1)
        #expect(commands.pendingTab == nil)
        #expect(commands.currentTab == .calendar)
    }

    @Test func selectTabSetsPendingTab() {
        let commands = AppCommands()

        commands.selectTab(.planner)

        #expect(commands.pendingTab == .planner)
    }
}
