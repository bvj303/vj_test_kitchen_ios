import SwiftUI

/// Profile/account screen — presented as a sheet from the toolbar account
/// button on every tab.
struct ProfileView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ProfileViewModel()

    private var fullName: String {
        "\(viewModel.firstName) \(viewModel.lastName)".trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        AvatarView(avatarUrl: viewModel.avatarUrl, name: fullName, size: 96)

                        if !fullName.isEmpty {
                            Text(fullName)
                                .font(.title3.weight(.semibold))
                        }
                        if !viewModel.username.isEmpty {
                            Text("@\(viewModel.username)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section {
                    NavigationLink {
                        EditProfileView(viewModel: viewModel)
                    } label: {
                        Label("Edit Profile", systemImage: "person.crop.circle")
                    }
                }

                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task {
                            await authViewModel.signOut()
                            dismiss()
                        }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // Reload whenever the sheet reappears (e.g. returning from Edit
            // Profile after changing the picture) so the header stays fresh.
            .task { await viewModel.load() }
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { authViewModel.errorMessage != nil },
                set: { if !$0 { authViewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") { authViewModel.errorMessage = nil }
        } message: {
            Text(authViewModel.errorMessage ?? "")
        }
    }
}

#Preview {
    ProfileView()
        .environment(AuthViewModel())
        .environment(SettingsViewModel())
        .environment(AccountViewModel())
}
