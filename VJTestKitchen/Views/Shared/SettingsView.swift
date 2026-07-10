import SwiftUI

/// Settings screen, reached from Profile. Currently just appearance
/// (Light/Dark/System); grows as more device-local preferences are added.
struct SettingsView: View {
    @Environment(SettingsViewModel.self) private var settingsViewModel
    @Environment(HomeLocationViewModel.self) private var homeLocationViewModel
    @Environment(SpatchTutorialViewModel.self) private var spatchTutorialViewModel

    var body: some View {
        @Bindable var settingsViewModel = settingsViewModel
        @Bindable var homeLocationViewModel = homeLocationViewModel

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

            // macOS has no alternate-icon API, so the picker only exists on
            // iOS/iPadOS (see AppIconSwitching).
            if settingsViewModel.supportsAppIconPicker {
                Section {
                    NavigationLink {
                        AppIconPickerView()
                    } label: {
                        LabeledContent("App Icon", value: settingsViewModel.selectedAppIcon.title)
                    }
                } footer: {
                    Text("Pick which pose Spatch strikes on your Home Screen.")
                }
            }

            weatherSection(homeLocationViewModel: homeLocationViewModel)

            Section {
                Toggle(isOn: $settingsViewModel.showSpatch) {
                    Label("Show Spatch", systemImage: "face.smiling")
                }
                Button {
                    spatchTutorialViewModel.restart()
                } label: {
                    Label("Meet Spatch Again", systemImage: "hand.wave.fill")
                }
                .disabled(!settingsViewModel.showSpatch)
            } header: {
                Text("Spatch")
            } footer: {
                Text("Spatch is your kitchen sidekick — he pops in with tips and the occasional stunt. Turn him off to hide his visits and animations, or replay his walkthrough anytime.")
            }
        }
        .navigationTitle("Settings")
        .inlineNavigationTitle()
        .scrollDismissesKeyboard(.interactively)
        .dismissesKeyboardOnBackgroundTap()
        .keyboardDoneButton()
    }

    /// Home location for the calendar's weather outlook — the saved ZIP (with
    /// a way to update it from the current location or a typed ZIP, and to turn
    /// the outlook off) when set, or the two set-it actions when not.
    @ViewBuilder
    private func weatherSection(homeLocationViewModel: HomeLocationViewModel) -> some View {
        @Bindable var homeLocationViewModel = homeLocationViewModel

        Section {
            if let home = homeLocationViewModel.homeLocation {
                LabeledContent("Home", value: home.displayName)
                Button {
                    Task { await homeLocationViewModel.useCurrentLocation() }
                } label: {
                    Label("Update from Current Location", systemImage: "location.fill")
                }
                .disabled(homeLocationViewModel.isWorking)
                Button(role: .destructive) {
                    homeLocationViewModel.clearHomeLocation()
                } label: {
                    Label("Turn Off Weather", systemImage: "xmark.circle")
                }
            } else {
                Button {
                    Task { await homeLocationViewModel.useCurrentLocation() }
                } label: {
                    Label("Use Current Location", systemImage: "location.fill")
                }
                .disabled(homeLocationViewModel.isWorking)

                HStack {
                    TextField("Home ZIP code", text: $homeLocationViewModel.zipInput)
                        .platformKeyboardType(.numbersAndPunctuation)
                        .textContentType(.postalCode)
                    Button("Set") {
                        Task { await homeLocationViewModel.setFromZipInput() }
                    }
                    .disabled(homeLocationViewModel.isWorking
                        || homeLocationViewModel.zipInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        } header: {
            Text("Weather")
        } footer: {
            if homeLocationViewModel.locationPermissionDenied {
                Text("Location access is off. Enter a ZIP code above, or turn it on in Settings › Privacy & Security › Location Services.")
            } else if let errorMessage = homeLocationViewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            } else {
                Text("Shows a weather outlook for the week ahead on your meal calendar, based on your home location.")
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(SettingsViewModel())
    .environment(HomeLocationViewModel())
    .environment(SpatchTutorialViewModel())
}
