import SwiftUI

/// Toolbar account entry point — present on every tab, not just Recipes, so
/// reaching Profile/Sign Out doesn't depend on which tab you happen to be
/// on. Presents ProfileView as a sheet, matching how Apple's own apps
/// (App Store, Music, Photos) handle a profile icon: a dedicated page, not
/// an inline menu, once there's more than a single trivial action.
///
/// A plain title + SF Symbol label, not the user's avatar image: on iPhone Duo
/// the system only presents toolbar items vertically (the side controls column
/// on the outer display and the inner display in landscape) when they have an
/// icon, and never when they use a custom view — the avatar made Account,
/// Settings and Sign Out unreachable in those poses. The avatar still shows in
/// the Profile sheet this opens.
struct AccountButton: View {
    @Environment(SettingsViewModel.self) private var settingsViewModel
    @State private var showingProfile = false

    var body: some View {
        Button {
            showingProfile = true
        } label: {
            Label("Account", systemImage: "person.crop.circle")
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
