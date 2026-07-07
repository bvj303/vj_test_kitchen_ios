import SwiftUI

struct MainTabView: View {
    @Environment(AccountViewModel.self) private var accountViewModel

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
        // Load the signed-in user's avatar once for the account button; runs
        // on each sign-in since MainTabView is recreated when auth state flips.
        .task { await accountViewModel.load() }
    }
}

#Preview {
    MainTabView()
        .environment(AuthViewModel())
        .environment(SettingsViewModel())
        .environment(AccountViewModel())
}
