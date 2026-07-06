import SwiftUI

/// The one tab where iPad benefits from a real list+detail split — the
/// other four tabs don't have that shape, so they stay plain NavigationStacks.
struct RecipesTab: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedRecipe: Recipe?
    @State private var path = NavigationPath()

    var body: some View {
        if horizontalSizeClass == .regular {
            // iPad: the account menu lives on the detail column, not the
            // sidebar — the sidebar's own trailing slot is already taken by
            // the system-provided sidebar-collapse toggle, and stacking our
            // icon next to it there felt cramped.
            NavigationSplitView {
                RecipeListView { recipe in selectedRecipe = recipe }
                    .navigationTitle("Recipes")
            } detail: {
                Group {
                    if let selectedRecipe {
                        // Give the detail view a per-recipe identity so
                        // selecting a different recipe rebuilds it (fresh
                        // @State + re-run .task); without this the detail
                        // column keeps showing the first recipe tapped.
                        RecipeDetailView(recipeId: selectedRecipe.id)
                            .id(selectedRecipe.id)
                    } else {
                        ContentUnavailableView("Select a Recipe", systemImage: "fork.knife")
                    }
                }
                .toolbar { accountToolbarItem }
            }
        } else {
            NavigationStack(path: $path) {
                RecipeListView { recipe in path.append(recipe) }
                    .navigationTitle("Recipes")
                    .navigationDestination(for: Recipe.self) { recipe in
                        RecipeDetailView(recipeId: recipe.id)
                    }
                    .toolbar { accountToolbarItem }
            }
        }
    }

    private var accountToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            AccountButton()
        }
    }
}
