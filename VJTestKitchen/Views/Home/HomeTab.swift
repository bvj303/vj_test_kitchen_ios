import SwiftUI

/// Hosts the Home dashboard in a plain `NavigationStack` (no split view — it's a
/// single scrolling screen). Suggested recipes and this-week's meals push a
/// `RecipeDetailView` keyed by recipe id; `selection` lets Home's stat tiles and
/// quick actions jump to the other tabs.
struct HomeTab: View {
    @Binding var selection: AppTab

    var body: some View {
        NavigationStack {
            HomeView(selection: $selection)
                .navigationDestination(for: Int64.self) { recipeId in
                    RecipeDetailView(recipeId: recipeId)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        AccountButton()
                    }
                }
        }
    }
}
