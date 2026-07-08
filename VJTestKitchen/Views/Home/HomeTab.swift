import SwiftUI

/// Hosts the Home dashboard in a plain `NavigationStack` (no split view — it's a
/// single scrolling screen). Suggested recipes push a `RecipeDetailView` keyed by
/// recipe id.
struct HomeTab: View {
    var body: some View {
        NavigationStack {
            HomeView()
                .navigationDestination(for: Int64.self) { recipeId in
                    RecipeDetailView(recipeId: recipeId)
                }
                .toolbar {
                    ToolbarItem(placement: .platformPrimaryAction) {
                        AccountButton()
                    }
                }
        }
    }
}
