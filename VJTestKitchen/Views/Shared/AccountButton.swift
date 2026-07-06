import SwiftUI

/// Toolbar account entry point — present on every tab, not just Recipes, so
/// reaching Profile/Sign Out doesn't depend on which tab you happen to be
/// on. Presents ProfileView as a sheet, matching how Apple's own apps
/// (App Store, Music, Photos) handle a profile icon: a dedicated page, not
/// an inline menu, once there's more than a single trivial action.
struct AccountButton: View {
    @Environment(SettingsViewModel.self) private var settingsViewModel
    @State private var showingProfile = false

    var body: some View {
        Button {
            showingProfile = true
        } label: {
            Image(systemName: "person.crop.circle")
        }
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
