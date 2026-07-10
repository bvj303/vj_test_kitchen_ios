import SwiftUI

@main
struct VJTestKitchenApp: App {
    @State private var authViewModel = AuthViewModel()
    @State private var settingsViewModel = SettingsViewModel()
    @State private var accountViewModel = AccountViewModel()
    // Shared so the first-login prompt (MainTabView) and Settings both read and
    // write the same saved home location, and the calendar picks up changes.
    @State private var homeLocationViewModel = HomeLocationViewModel()
    // Menu-bar / keyboard-shortcut command bus (see AppCommands).
    @State private var appCommands = AppCommands()
    // Shared so the first-launch walkthrough (MainTabView) and Settings'
    // "Meet Spatch Again" replay read and write the same instance.
    @State private var spatchTutorialViewModel = SpatchTutorialViewModel()
    // Schedules Spatch's surprise stunt flybys — shared so the stage/scheduler
    // (MainTabView) and every cameo (which must yield the stage to a stunt and
    // vice versa) coordinate through one instance.
    @State private var spatchStuntCoordinator = SpatchStuntCoordinator()

    init() {
        // Give `URLSession.shared` (and therefore every `RemoteImage`) a roomy
        // on-disk/in-memory response cache so recipe thumbnails survive scrolling
        // and app relaunches instead of re-downloading. Pairs with the decoded
        // `ImageCache` in-memory tier for flicker-free image loading.
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024,   // 32 MB
            diskCapacity: 256 * 1024 * 1024,    // 256 MB
            diskPath: "vjtk_image_cache"
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authViewModel)
                .environment(settingsViewModel)
                .environment(accountViewModel)
                .environment(homeLocationViewModel)
                .environment(appCommands)
                .environment(spatchTutorialViewModel)
                .environment(spatchStuntCoordinator)
                .preferredColorScheme(settingsViewModel.appearanceMode.colorScheme)
                // Two kinds of vjtestkitchen:// deep links land here:
                //  • Widget taps (host = a tab, e.g. vjtestkitchen://calendar) →
                //    switch to that tab via the command bus.
                //  • Email-confirmation / magic-link redirects
                //    (vjtestkitchen://login-callback) → complete auth so the user
                //    lands signed-in in the app rather than on a dead web page.
                .onOpenURL { url in
                    if let tab = AppTab(deepLinkHost: url.host) {
                        appCommands.selectTab(tab)
                    } else {
                        Task { await authViewModel.handleAuthCallback(url: url) }
                    }
                }
                #if os(macOS)
                // Floor the window size so it can't collapse to a screen's
                // intrinsic size (e.g. the compact auth view); it still resizes
                // freely above this.
                .frame(minWidth: 900, idealWidth: 1100, minHeight: 620, idealHeight: 760)
                #endif
        }
        #if os(macOS)
        // A real Mac window: opens at the ideal size, resizable down to the
        // content minimum (not the content's fitting size — that's what made it
        // open tiny).
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 760)
        #endif
        // Menu-bar commands. Cross-platform: on macOS this is the menu bar; on
        // iPadOS it powers hardware-keyboard shortcuts + the ⌘ discoverability HUD.
        .commands {
            // Replace the default File ▸ New with a context-aware create (⌘N):
            // the title tracks the current tab ("New Recipe" vs "New Grocery
            // Item"), and `requestNew()` routes to that tab's add action.
            CommandGroup(replacing: .newItem) {
                Button(appCommands.newItemTitle) { appCommands.requestNew() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            // Reload the visible screen (⌘R) — the app has no system refresh
            // command, so add one next to the standard toolbar/window items.
            CommandGroup(after: .toolbar) {
                Button("Refresh") { appCommands.requestRefresh() }
                    .keyboardShortcut("r", modifiers: .command)
            }
            // App navigation + search.
            CommandMenu("Go") {
                Button("Find Recipes…") { appCommands.requestSearch() }
                    .keyboardShortcut("f", modifiers: .command)
                Divider()
                Button("Home") { appCommands.selectTab(.home) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Recipes") { appCommands.selectTab(.recipes) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Groceries") { appCommands.selectTab(.grocery) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("AI Planner") { appCommands.selectTab(.planner) }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Calendar") { appCommands.selectTab(.calendar) }
                    .keyboardShortcut("5", modifiers: .command)
            }
        }

        #if os(macOS)
        // Standard macOS Preferences window (⌘,) hosting the existing settings
        // screen, wired to the same view-model instances as the main window.
        Settings {
            SettingsView()
                .environment(authViewModel)
                .environment(settingsViewModel)
                .environment(accountViewModel)
                .environment(homeLocationViewModel)
                .environment(spatchTutorialViewModel)
                .preferredColorScheme(settingsViewModel.appearanceMode.colorScheme)
                .frame(minWidth: 420, minHeight: 320)
        }
        #endif
    }
}
