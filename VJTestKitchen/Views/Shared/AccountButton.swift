import SwiftUI

/// Toolbar account entry point — present on every tab, not just Recipes, so
/// reaching Profile/Sign Out doesn't depend on which tab you happen to be
/// on. Presents ProfileView as a sheet, matching how Apple's own apps
/// (App Store, Music, Photos) handle a profile icon: a dedicated page, not
/// an inline menu, once there's more than a single trivial action.
struct AccountButton: View {
    @Environment(SettingsViewModel.self) private var settingsViewModel
    @Environment(AccountViewModel.self) private var accountViewModel
    @State private var showingProfile = false

    var body: some View {
        Button {
            showingProfile = true
        } label: {
            if let avatarUrl = accountViewModel.avatarUrl, !avatarUrl.isEmpty {
                // Show the user's actual profile picture in the toolbar; falls
                // back to the person symbol when they haven't set one.
                AvatarView(avatarUrl: avatarUrl, name: nil, size: 28)
            } else {
                Image(systemName: "person.crop.circle")
            }
        }
        .accessibilityLabel("Account")
        .sheet(isPresented: $showingProfile) {
            ProfileView()
                // `.preferredColorScheme` on the WindowGroup root doesn't
                // propagate into `.sheet` content in SwiftUI — sheets get
                // their own presentation context, so the override must be
                // re-applied here too.
                .preferredColorScheme(settingsViewModel.appearanceMode.colorScheme)
        }
    }
}
