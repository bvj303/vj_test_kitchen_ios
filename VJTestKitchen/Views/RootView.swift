import SwiftUI

struct RootView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        switch authViewModel.state {
        case .loading:
            ProgressView()
        case .signedOut:
            AuthView()
        case .signedIn:
            MainTabView()
        }
    }
}

#Preview {
    RootView()
        .environment(AuthViewModel())
        .environment(SettingsViewModel())
}
