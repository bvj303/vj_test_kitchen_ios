import SwiftUI

@main
struct VJTestKitchenApp: App {
    @State private var authViewModel = AuthViewModel()
    @State private var settingsViewModel = SettingsViewModel()
    @State private var accountViewModel = AccountViewModel()
    // Shared so the first-login prompt (MainTabView) and Settings both read and
    // write the same saved home location, and the calendar picks up changes.
    @State private var homeLocationViewModel = HomeLocationViewModel()

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
                .preferredColorScheme(settingsViewModel.appearanceMode.colorScheme)
        }
    }
}
