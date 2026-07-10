import SwiftUI

/// The signed-in app's top-level tabs, tracked by `MainTabView`'s `selection`.
enum AppTab: Hashable {
    case home, recipes, grocery, planner, calendar

    /// The tab a widget deep link (`vjtestkitchen://<host>`) targets, or nil for
    /// a non-navigation URL (e.g. the auth `login-callback`), so
    /// `VJTestKitchenApp.onOpenURL` can tell a widget tap from an auth redirect.
    /// Kinds map through `WidgetSharedConfig.DeepLink`.
    init?(deepLinkHost host: String?) {
        switch host {
        case "home": self = .home
        case "recipes", "recipe": self = .recipes
        case "grocery": self = .grocery
        case "planner": self = .planner
        case "calendar": self = .calendar
        default: return nil
        }
    }
}

struct MainTabView: View {
    @Environment(AccountViewModel.self) private var accountViewModel
    @Environment(HomeLocationViewModel.self) private var homeLocationViewModel
    @Environment(AppCommands.self) private var appCommands
    @Environment(SpatchTutorialViewModel.self) private var spatchTutorialViewModel
    @State private var selection: AppTab = .home
    @State private var showLocationPrompt = false

    var body: some View {
        ZStack {
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
            // The real screens must be inert while the tour narrates over
            // them. The dim layer's tap-swallowing alone isn't enough: on
            // macOS, clicks pass straight through it into the content
            // (confirmed live — a click behind the tour pushed a recipe
            // detail), and `.allowsHitTesting(false)` doesn't help either
            // (also confirmed live — the tab content is AppKit-backed there,
            // and event routing bypasses SwiftUI hit-testing). `.disabled`
            // works: it disables the actual controls across the bridge.
            .disabled(spatchTutorialViewModel.isPresented)

            // Spatch's walkthrough overlays the real tabs (rather than
            // covering them in a sheet) and drives `selection` itself as it
            // advances — see `SpatchTutorialViewModel.targetTab` — so each
            // step narrates over the actual screen it introduces. The dimming
            // layer blocks stray taps on the tab bar/content underneath
            // without hiding what it's showing off.
            if spatchTutorialViewModel.isPresented {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .transition(.opacity)
                SpatchTutorialView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Load the signed-in user's avatar once for the account button; runs
        // on each sign-in since MainTabView is recreated when auth state flips.
        .task { await accountViewModel.load() }
        // First-launch-only: Spatch's walkthrough, shown ahead of the location
        // prompt below so a brand-new user isn't hit with two prompts at once.
        .task {
            spatchTutorialViewModel.maybePresentOnLaunch()
            if !spatchTutorialViewModel.isPresented, homeLocationViewModel.shouldPromptForLocation {
                showLocationPrompt = true
            }
        }
        // Follow the tour's target tab live, so each step shows the real
        // screen rather than a static mockup.
        .onChange(of: spatchTutorialViewModel.stepIndex) { _, _ in
            if let tab = spatchTutorialViewModel.targetTab {
                selection = tab
            }
        }
        // First-login-only: offer to set a home location for the weather
        // outlook. Gated so it's shown at most once (the prompt itself records
        // that it was shown — see HomeLocationPromptView). Deferred until
        // Spatch's walkthrough (above) has been dismissed.
        .onChange(of: spatchTutorialViewModel.isPresented) { _, isPresented in
            guard !isPresented, homeLocationViewModel.shouldPromptForLocation else { return }
            showLocationPrompt = true
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
        .environment(SpatchTutorialViewModel())
}
