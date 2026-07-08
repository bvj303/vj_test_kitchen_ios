import SwiftUI

/// The one tab where iPad benefits from a real list+detail split — the
/// other four tabs don't have that shape, so they stay plain NavigationStacks.
struct RecipesTab: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedRecipe: Recipe?
    @State private var path = NavigationPath()
    // Bumped after a delete to re-run the list's load, so the removed recipe
    // stops appearing (and can't be tapped back into a now-broken detail).
    @State private var listReloadToken = UUID()

    /// A recipe was deleted from its detail screen. Clear the split-view
    /// selection (iPad — swaps the detail column back to the placeholder; the
    /// iPhone push pops itself via the detail's own `dismiss()`) and reload the
    /// list so the removed recipe drops out and can't be reopened.
    private func handleRecipeDeleted() {
        selectedRecipe = nil
        listReloadToken = UUID()
    }

    var body: some View {
        if horizontalSizeClass == .regular {
            // iPad: the account menu lives on the detail column, not the
            // sidebar — the sidebar's own trailing slot is already taken by
            // the system-provided sidebar-collapse toggle, and stacking our
            // icon next to it there felt cramped.
            NavigationSplitView {
                RecipeListView(reloadToken: listReloadToken) { recipe in selectedRecipe = recipe }
                    .navigationTitle("Recipes")
            } detail: {
                Group {
                    if let selectedRecipe {
                        // Give the detail view a per-recipe identity so
                        // selecting a different recipe rebuilds it (fresh
                        // @State + re-run .task); without this the detail
                        // column keeps showing the first recipe tapped.
                        RecipeDetailView(recipeId: selectedRecipe.id, onDeleted: handleRecipeDeleted)
                            .id(selectedRecipe.id)
                    } else {
                        ContentUnavailableView("Select a Recipe", systemImage: "fork.knife")
                    }
                }
                .toolbar { accountToolbarItem }
            }
        } else {
            NavigationStack(path: $path) {
                RecipeListView(reloadToken: listReloadToken) { recipe in path.append(recipe) }
                    .navigationTitle("Recipes")
                    .navigationDestination(for: Recipe.self) { recipe in
                        RecipeDetailView(recipeId: recipe.id, onDeleted: handleRecipeDeleted)
                    }
                    .toolbar { accountToolbarItem }
            }
        }
    }

    private var accountToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .platformPrimaryAction) {
            AccountButton()
        }
    }
}
