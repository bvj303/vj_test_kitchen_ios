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
            VStack(spacing: 14) {
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
        .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        CreateAccountView()
            .environment(AuthViewModel())
    }
}
