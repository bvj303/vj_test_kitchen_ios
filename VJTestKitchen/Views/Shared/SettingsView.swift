import SwiftUI

/// Settings screen, reached from Profile. Currently just appearance
/// (Light/Dark/System); grows as more device-local preferences are added.
struct SettingsView: View {
    @Environment(SettingsViewModel.self) private var settingsViewModel

    var body: some View {
        @Bindable var settingsViewModel = settingsViewModel

        List {
            Section {
                Picker("Appearance", selection: $settingsViewModel.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text("Appearance")
            } footer: {
                Text("System matches your device's Light/Dark Mode setting.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(SettingsViewModel())
}
