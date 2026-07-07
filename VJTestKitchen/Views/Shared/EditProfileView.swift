import SwiftUI

/// Pushed from ProfileView's "Edit Profile" row. Loads the signed-in user's
/// current first/last name and username, and lets them change any of the
/// three — mirrors CreateProfileView's fields, but as an edit rather than
/// the first step of sign-up.
struct EditProfileView: View {
    @State private var viewModel = ProfileViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case firstName, lastName, username
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        Group {
            if viewModel.isLoading {
                ProgressView()
            } else {
                Form {
                    Section {
                        TextField("First Name", text: $viewModel.firstName)
                            .textContentType(.givenName)
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .firstName)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .lastName }

                        TextField("Last Name", text: $viewModel.lastName)
                            .textContentType(.familyName)
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .lastName)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .username }
                    }

                    Section {
                        TextField("Username", text: $viewModel.username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .username)
                            .submitLabel(.done)
                    } footer: {
                        if let usernameStatusText {
                            Text(usernameStatusText)
                                .foregroundStyle(usernameStatusColor)
                        }
                    }
                }
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await viewModel.save()
                        if viewModel.didSave { dismiss() }
                    }
                }
                .disabled(!viewModel.canSave || viewModel.isSaving)
            }
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task { await viewModel.load() }
    }

    private var usernameStatusText: String? {
        switch viewModel.usernameAvailability {
        case .invalidFormat: "3–20 letters, numbers, or underscores."
        case .checking: "Checking availability…"
        case .available: "Username is available."
        case .taken: "That username is already taken."
        case .unknown: "Couldn't check availability — try again."
        case .unchanged, nil: nil
        }
    }

    private var usernameStatusColor: Color {
        switch viewModel.usernameAvailability {
        case .taken, .invalidFormat, .unknown: .red
        case .available: .green
        case .checking, .unchanged, nil: .secondary
        }
    }
}

#Preview {
    NavigationStack {
        EditProfileView()
    }
}
