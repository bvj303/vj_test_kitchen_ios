import SwiftUI

struct AIPlannerTab: View {
    var body: some View {
        NavigationStack {
            AIPlannerView()
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
