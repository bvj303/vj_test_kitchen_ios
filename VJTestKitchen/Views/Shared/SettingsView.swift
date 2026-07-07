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

            Section {
                Toggle("Use Current Location", isOn: Binding(
                    get: { settingsViewModel.useCurrentLocationForWeather },
                    set: { newValue in
                        Task { await settingsViewModel.setUseCurrentLocation(newValue) }
                    }
                ))
            } header: {
                Text("Weather")
            } footer: {
                if settingsViewModel.locationPermissionDenied {
                    Text("Location access is off. Turn it on in Settings › Privacy & Security › Location Services to show a weather outlook on your calendar.")
                } else {
                    Text("Shows a weather outlook for the week ahead on your meal calendar, using your current location.")
                }
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
