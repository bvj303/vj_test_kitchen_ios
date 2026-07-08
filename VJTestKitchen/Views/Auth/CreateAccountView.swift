import SwiftUI

/// Second and final step of account creation — email/password, pushed from
/// CreateProfileView once first/last name and username are set. Performs the
/// actual sign-up, carrying those fields through as auth user metadata (see
/// AuthService.signUp).
struct CreateAccountView: View {
    @Environment(AuthViewModel.self) private var viewModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case email, password
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
        .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.inline)
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
        .frame(maxWidth: 420)
        .padding(.horizontal)
        .padding(.top, 40)
    }

    private func signUpForm(viewModel: AuthViewModel) -> some View {
        @Bindable var viewModel = viewModel
        return VStack(spacing: 14) {
                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .textFieldStyle(.roundedBorder)

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
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                .disabled(
                    viewModel.isSubmitting || viewModel.email.isEmpty
                        || viewModel.password.count < AuthViewModel.minimumPasswordLength
                )
                .padding(.top, 4)
            }
            .padding(24)
            .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .frame(maxWidth: 420)
            .padding(.horizontal)
    }
}

#Preview {
    NavigationStack {
        CreateAccountView()
            .environment(AuthViewModel())
    }
}
