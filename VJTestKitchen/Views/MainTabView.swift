import SwiftUI

/// The signed-in app's top-level tabs. `selection` is bound so the Home tab's
/// stat tiles / quick actions can jump straight to another tab.
enum AppTab: Hashable {
    case home, recipes, grocery, planner, calendar
}

struct MainTabView: View {
    @Environment(AccountViewModel.self) private var accountViewModel
    @State private var selection: AppTab = .home

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeTab(selection: $selection)
            }
            Tab("Recipes", systemImage: "fork.knife", value: AppTab.recipes) {
                RecipesTab()
            }
            Tab("Grocery List", systemImage: "cart", value: AppTab.grocery) {
                GroceryListTab()
            }
            Tab("AI Planner", systemImage: "sparkles", value: AppTab.planner) {
                AIPlannerTab()
            }
            Tab("Calendar", systemImage: "calendar", value: AppTab.calendar) {
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
