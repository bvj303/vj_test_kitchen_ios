import SwiftUI

/// Picks between the app-icon looks (classic Spatch and his stunt alter
/// egos). Pushed from Settings; iOS/iPadOS only — macOS has no alternate-icon
/// API, so Settings hides the entry point there (see `AppIconSwitching`).
struct AppIconPickerView: View {
    @Environment(SettingsViewModel.self) private var settingsViewModel

    var body: some View {
        List {
            Section {
                ForEach(AppIconOption.allCases) { option in
                    Button {
                        Task { await settingsViewModel.selectAppIcon(option) }
                    } label: {
                        row(option)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                if let message = settingsViewModel.appIconErrorMessage {
                    Text(message).foregroundStyle(.red)
                } else {
                    Text("Spatch strikes a different pose on your Home Screen. Each look has its own Dark Mode version too.")
                }
            }
        }
        .navigationTitle("App Icon")
        .inlineNavigationTitle()
    }

    private func row(_ option: AppIconOption) -> some View {
        HStack(spacing: 14) {
            Image(option.previewImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                Text(option.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if settingsViewModel.selectedAppIcon == option {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Selected")
            }
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        AppIconPickerView()
    }
    .environment(SettingsViewModel())
}
