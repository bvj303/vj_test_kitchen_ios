import SwiftUI

/// Account creation on a single page — profile (first/last name, username with
/// live availability) and credentials (email, password) together, then the
/// sign-up itself. Pushed from AuthView's "Create Account" link. The profile
/// fields ride through as auth user metadata (see AuthService.signUp).
struct CreateAccountView: View {
    @Environment(AuthViewModel.self) private var viewModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case firstName, lastName, username, email, password
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            if viewModel.awaitingEmailConfirmation {
                confirmationPrompt
            } else {
                signUpForm(viewModel: viewModel)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Create Account")
        .inlineNavigationTitle()
        .dismissesKeyboardOnBackgroundTap()
        .keyboardDoneButton()
    }

    /// Shown after a successful sign-up when the account still needs email
    /// confirmation — there's no session yet, so tell the user to check their
    /// inbox rather than leaving them on a form that looks like it did nothing.
    private var confirmationPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 48))
                .foregroundStyle(Color.brandPrimary)
            Text("Check your email")
                .font(.title2.bold())
            Text("We sent a confirmation link to \(viewModel.email). Tap it to activate your account, then come back and sign in.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .frame(maxWidth: 460)
        .padding(.horizontal)
        .padding(.top, 40)
    }

    private func signUpForm(viewModel: AuthViewModel) -> some View {
        @Bindable var viewModel = viewModel
        return VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("Create Your Account")
                    .font(.title2.bold())
                Text("Just a few details to get cooking.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)

            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    TextField("First Name", text: $viewModel.firstName)
                        .textContentType(.givenName)
                        .platformAutocapitalization(.words)
                        .focused($focusedField, equals: .firstName)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .lastName }
                        .textFieldStyle(.roundedBorder)

                    TextField("Last Name", text: $viewModel.lastName)
                        .textContentType(.familyName)
                        .platformAutocapitalization(.words)
                        .focused($focusedField, equals: .lastName)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .username }
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Username", text: $viewModel.username)
                        .textContentType(.username)
                        .platformAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .email }
                        .textFieldStyle(.roundedBorder)

                    if let usernameStatusText {
                        Text(usernameStatusText)
                            .font(.footnote)
                            .foregroundStyle(usernameStatusColor)
                    }
                }

                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .platformKeyboardType(.emailAddress)
                    .platformAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 4) {
                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await viewModel.signUp() } }
                        .textFieldStyle(.roundedBorder)

                    if !viewModel.password.isEmpty && viewModel.password.count < AuthViewModel.minimumPasswordLength {
                        Text("Password must be at least \(AuthViewModel.minimumPasswordLength) characters.")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { await viewModel.signUp() }
                } label: {
                    Text("Create Account")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(viewModel.isSubmitting || !viewModel.canSubmitSignUp)
                .padding(.top, 4)
            }
            .padding(24)
            .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .frame(maxWidth: 460)
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity)
    }

    private var usernameStatusText: String? {
        switch viewModel.usernameAvailability {
        case .invalidFormat: "3–20 letters, numbers, or underscores."
        case .checking: "Checking availability…"
        case .available: "Username is available."
        case .taken: "That username is already taken."
        case .unknown: "Couldn't check availability — try again."
        case nil: nil
        }
    }

    private var usernameStatusColor: Color {
        switch viewModel.usernameAvailability {
        case .taken, .invalidFormat, .unknown: .red
        case .available: .green
        case .checking, nil: .secondary
        }
    }
}

#Preview {
    NavigationStack {
        CreateAccountView()
            .environment(AuthViewModel())
    }
}
