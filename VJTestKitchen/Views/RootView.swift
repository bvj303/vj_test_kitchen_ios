import SwiftUI

struct RootView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        content
            // Warm up the auth session once at launch so a fresh token is pushed
            // to every Supabase sub-client (the Functions client caches its token
            // from auth events, not per-request) before the user opens the AI
            // Planner — otherwise its server-side recipe search runs unauthenticated
            // and reports an empty collection until another tab forces a refresh.
            // See AuthViewModel.warmUpSession.
            .task { await authViewModel.warmUpSession() }
    }

    @ViewBuilder
    private var content: some View {
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
        .environment(AccountViewModel())
        .environment(HomeLocationViewModel())
}
