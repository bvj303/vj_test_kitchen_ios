import SwiftUI
import PhotosUI

/// Pushed from ProfileView's "Edit Profile" row. Loads the signed-in user's
/// current first/last name and username, and lets them change any of the
/// three — mirrors the profile fields on the Create Account form, but as an
/// edit rather than sign-up. Also lets them set a profile picture, which
/// uploads immediately on selection (independent of Save).
struct EditProfileView: View {
    // Injected so ProfileView can share one instance — an avatar uploaded here
    // then reflects in ProfileView's header without a manual reload. Defaults
    // to a fresh one for standalone use / previews.
    private let viewModel: ProfileViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingDeleteConfirmation = false
    @Environment(AccountViewModel.self) private var accountViewModel
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    init(viewModel: ProfileViewModel = ProfileViewModel()) {
        self.viewModel = viewModel
    }

    private enum Field: Hashable {
        case firstName, lastName, username
    }

    private var fullName: String {
        "\(viewModel.firstName) \(viewModel.lastName)".trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        Group {
            if viewModel.isLoading {
                ProgressView()
            } else {
                Form {
                    Section {
                        avatarPicker
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }

                    Section {
                        TextField("First Name", text: $viewModel.firstName)
                            .textContentType(.givenName)
                            .platformAutocapitalization(.words)
                            .focused($focusedField, equals: .firstName)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .lastName }

                        TextField("Last Name", text: $viewModel.lastName)
                            .textContentType(.familyName)
                            .platformAutocapitalization(.words)
                            .focused($focusedField, equals: .lastName)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .username }
                    }

                    Section {
                        TextField("Username", text: $viewModel.username)
                            .textContentType(.username)
                            .platformAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .username)
                            .submitLabel(.done)
                    } footer: {
                        if let usernameStatusText {
                            Text(usernameStatusText)
                                .foregroundStyle(usernameStatusColor)
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
            }
        }
        .navigationTitle("Edit Profile")
        .inlineNavigationTitle()
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
        .task { await viewModel.load() }
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem else { return }
            Task { await loadAndUploadPhoto(newItem) }
        }
    }

    private var avatarPicker: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(avatarUrl: viewModel.avatarUrl, name: fullName, size: 96)
                        .opacity(viewModel.isUploadingAvatar ? 0.5 : 1)
                        .overlay {
                            if viewModel.isUploadingAvatar {
                                ProgressView()
                            }
                        }

                    Image(systemName: "pencil.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.brandPrimary)
                        .background(Circle().fill(.background))
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isUploadingAvatar)

            Text("Tap to change your photo")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func loadAndUploadPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let jpeg = AvatarImageProcessor.normalizedJPEG(from: data) else {
                viewModel.errorMessage = "Couldn't read the selected photo. Please try another."
                return
            }
            await viewModel.uploadAvatar(jpeg)
            // Propagate the new picture to app chrome (the account button on
            // every tab) so it updates without reopening Profile. On failure
            // viewModel.avatarUrl is unchanged, so guard on no error.
            if viewModel.errorMessage == nil {
                accountViewModel.setAvatarUrl(viewModel.avatarUrl)
            }
        } catch {
            viewModel.errorMessage = "Couldn't load the selected photo. Please try another."
        }
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
    .environment(AccountViewModel())
    .environment(AuthViewModel())
}
