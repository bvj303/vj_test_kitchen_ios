import SwiftUI

/// The signed-in app's top-level tabs, tracked by `MainTabView`'s `selection`.
enum AppTab: Hashable {
    case home, recipes, grocery, planner, calendar
}

struct MainTabView: View {
    @Environment(AccountViewModel.self) private var accountViewModel
    @Environment(HomeLocationViewModel.self) private var homeLocationViewModel
    @Environment(AppCommands.self) private var appCommands
    @State private var selection: AppTab = .home
    @State private var showLocationPrompt = false

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeTab()
            }
            Tab("Recipes", systemImage: "fork.knife", value: AppTab.recipes) {
                RecipesTab()
            }
            Tab("Groceries", systemImage: "cart", value: AppTab.grocery) {
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
        // First-login-only: offer to set a home location for the weather
        // outlook. Gated so it's shown at most once (the prompt itself records
        // that it was shown — see HomeLocationPromptView).
        .task {
            if homeLocationViewModel.shouldPromptForLocation { showLocationPrompt = true }
        }
        .sheet(isPresented: $showLocationPrompt) {
            HomeLocationPromptView()
        }
        // Menu-bar / keyboard-shortcut tab switches (see AppCommands).
        .onChange(of: appCommands.pendingTab) { _, requested in
            guard let requested else { return }
            selection = requested
            appCommands.pendingTab = nil
        }
        // Mirror the visible tab into the command bus so context-aware commands
        // (⌘N) know which screen to act on. Seed it once on appear, then track.
        .onAppear { appCommands.currentTab = selection }
        .onChange(of: selection) { _, newValue in
            appCommands.currentTab = newValue
        }
    }
}

#Preview {
    MainTabView()
        .environment(AuthViewModel())
        .environment(SettingsViewModel())
        .environment(AccountViewModel())
        .environment(HomeLocationViewModel())
        .environment(AppCommands())
}
