import SwiftUI

/// One-time, first-login prompt asking the user to set a home location for the
/// calendar's weather outlook. Offers "Use My Location" (device fix →
/// reverse-geocoded to a ZIP), manual ZIP entry, or "Not now". Backed by the
/// shared `HomeLocationViewModel` so whatever the user picks is immediately
/// reflected in Settings and on the calendar. Shown at most once (see
/// `MainTabView` / `HomeLocationViewModel.shouldPromptForLocation`).
struct HomeLocationPromptView: View {
    @Environment(HomeLocationViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingZipEntry = false

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.brandPrimary)

                Text("Set your home location")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("See a weather outlook for the week ahead on your meal calendar. Your location stays on this device.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if viewModel.locationPermissionDenied {
                    Text("Location access is off — enter a ZIP code instead, or turn it on in Settings › Privacy & Security › Location Services.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if showingZipEntry {
                    zipEntry(viewModel: viewModel)
                } else {
                    actionButtons(viewModel: viewModel)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .platformPrimaryAction) {
                    Button("Not now") { dismiss() }
                }
            }
        }
        .dismissesKeyboardOnBackgroundTap()
        .keyboardDoneButton()
        // Mark as shown the moment it appears, so it never reappears regardless
        // of how the user leaves it (button, "Not now", or a swipe-dismiss).
        .task { viewModel.markPrompted() }
        // Dismiss automatically once a location has been captured.
        .onChange(of: viewModel.hasHomeLocation) { _, hasLocation in
            if hasLocation { dismiss() }
        }
    }

    private func actionButtons(viewModel: HomeLocationViewModel) -> some View {
        VStack(spacing: 12) {
            Button {
                Task { await viewModel.useCurrentLocation() }
            } label: {
                Label("Use My Location", systemImage: "location.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(viewModel.isWorking)

            Button("Enter ZIP manually") { showingZipEntry = true }
                .disabled(viewModel.isWorking)
        }
    }

    private func zipEntry(viewModel: HomeLocationViewModel) -> some View {
        @Bindable var viewModel = viewModel
        return VStack(spacing: 12) {
            TextField("ZIP code", text: $viewModel.zipInput)
                .platformKeyboardType(.numbersAndPunctuation)
                .textContentType(.postalCode)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit { Task { await viewModel.setFromZipInput() } }

            Button {
                Task { await viewModel.setFromZipInput() }
            } label: {
                Text("Save ZIP")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(viewModel.isWorking || viewModel.zipInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

#Preview {
    HomeLocationPromptView()
        .environment(HomeLocationViewModel())
}
