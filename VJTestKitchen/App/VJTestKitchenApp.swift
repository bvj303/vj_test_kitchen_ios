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
                .preferredColorScheme(settingsViewModel.appearanceMode.colorScheme)
                // Email-confirmation (and future magic-link) deep links redirect
                // to vjtestkitchen://login-callback; complete them here so the
                // user lands signed-in in the app rather than on a web page.
                .onOpenURL { url in
                    Task { await authViewModel.handleAuthCallback(url: url) }
                }
        }
        #if os(macOS)
        // A real Mac window: resizable, with a sensible first-run size.
        .windowResizability(.contentSize)
        .defaultSize(width: 1100, height: 720)
        #endif
        // Menu-bar commands. Cross-platform: on macOS this is the menu bar; on
        // iPadOS it powers hardware-keyboard shortcuts + the ⌘ discoverability HUD.
        .commands {
            // Replace the default File ▸ New with recipe creation (⌘N).
            CommandGroup(replacing: .newItem) {
                Button("New Recipe") { appCommands.requestNewRecipe() }
                    .keyboardShortcut("n", modifiers: .command)
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
                .preferredColorScheme(settingsViewModel.appearanceMode.colorScheme)
                .frame(minWidth: 420, minHeight: 320)
        }
        #endif
    }
}
