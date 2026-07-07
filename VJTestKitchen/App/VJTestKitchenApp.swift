import SwiftUI

@main
struct VJTestKitchenApp: App {
    @State private var authViewModel = AuthViewModel()
    @State private var settingsViewModel = SettingsViewModel()
    @State private var accountViewModel = AccountViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authViewModel)
                .environment(settingsViewModel)
                .environment(accountViewModel)
                .preferredColorScheme(settingsViewModel.appearanceMode.colorScheme)
        }
    }
}
