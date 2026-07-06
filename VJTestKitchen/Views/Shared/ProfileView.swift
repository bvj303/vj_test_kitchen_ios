import SwiftUI

/// Placeholder profile/account screen — presented as a sheet from the
/// toolbar account button on every tab. Grows into real profile content
/// (display name, avatar) in a later stage; for now it just hosts sign out
/// so that action lives somewhere more standard than a bare toolbar icon.
struct ProfileView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Profile details coming soon", systemImage: "person.crop.circle")
                        .foregroundStyle(.secondary)
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
        }
    }
}

#Preview {
    ProfileView()
        .environment(AuthViewModel())
}
