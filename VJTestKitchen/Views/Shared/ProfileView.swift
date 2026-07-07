import SwiftUI

/// Placeholder profile/account screen — presented as a sheet from the
/// toolbar account button on every tab. Grows into real profile content
/// (display name, avatar) in a later stage; for now it just hosts sign out
/// so that action lives somewhere more standard than a bare toolbar icon.
struct ProfileView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Profile details coming soon", systemImage: "person.crop.circle")
                        .foregroundStyle(.secondary)
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

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Account", systemImage: "trash")
                    }
                    .disabled(authViewModel.isSubmitting)
                } footer: {
                    Text("Permanently deletes your account and all your recipes, ratings, and meal plans. This can't be undone.")
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .confirmationDialog(
            "Delete your account?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task {
                    await authViewModel.deleteAccount()
                    if authViewModel.errorMessage == nil { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account and all your recipes, ratings, and meal plans. This can't be undone.")
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
}
