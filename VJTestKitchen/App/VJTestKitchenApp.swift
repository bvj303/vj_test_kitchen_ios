import SwiftUI

@main
struct VJTestKitchenApp: App {
    @State private var authViewModel = AuthViewModel()
    @State private var settingsViewModel = SettingsViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authViewModel)
                .environment(settingsViewModel)
                .preferredColorScheme(settingsViewModel.appearanceMode.colorScheme)
        }
    }
}
