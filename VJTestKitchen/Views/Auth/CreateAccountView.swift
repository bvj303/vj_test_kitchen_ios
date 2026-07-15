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

        ZStack {
            AuthBackground()

            GeometryReader { proxy in
                ScrollView {
                    Group {
                        if viewModel.awaitingEmailConfirmation {
                            confirmationPrompt
                        } else {
                            signUpForm(viewModel: viewModel)
                        }
                    }
                    // Center the card vertically in the available space (matches
                    // AuthView) so iPad/Mac don't leave it stranded at the top.
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .navigationTitle("Create Account")
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
    }

    private func signUpForm(viewModel: AuthViewModel) -> some View {
        @Bindable var viewModel = viewModel
        // No inline "Create Your Account" heading — the large navigation title
        // already names the screen. Just a friendly one-line subtitle above the
        // fields.
        return VStack(spacing: 20) {
            Text("Just a few details to get cooking.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    TextField("First Name", text: $viewModel.firstName)
                        .textContentType(.givenName)
                        .platformAutocapitalization(.words)
                        .focused($focusedField, equals: .firstName)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .lastName }
                        .authFieldStyle(isFocused: focusedField == .firstName)
                        .frame(maxWidth: .infinity)

                    TextField("Last Name", text: $viewModel.lastName)
                        .textContentType(.familyName)
                        .platformAutocapitalization(.words)
                        .focused($focusedField, equals: .lastName)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .username }
                        .authFieldStyle(isFocused: focusedField == .lastName)
                        .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Username", text: $viewModel.username)
                        .textContentType(.username)
                        .platformAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .email }
                        .authFieldStyle(isFocused: focusedField == .username)

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
                    .authFieldStyle(isFocused: focusedField == .email)

                VStack(alignment: .leading, spacing: 4) {
                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await viewModel.signUp() } }
                        .authFieldStyle(isFocused: focusedField == .password)

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
