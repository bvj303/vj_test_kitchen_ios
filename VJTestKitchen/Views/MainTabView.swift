import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Recipes", systemImage: "fork.knife") {
                RecipesTab()
            }
            Tab("Add", systemImage: "plus.circle") {
                AddRecipeTab()
            }
            Tab("Grocery List", systemImage: "cart") {
                GroceryListTab()
            }
            Tab("AI Planner", systemImage: "sparkles") {
                AIPlannerTab()
            }
            Tab("Calendar", systemImage: "calendar") {
                CalendarTab()
            }
        }
    }
}

#Preview {
    MainTabView()
        .environment(AuthViewModel())
}
