import SwiftUI

struct AuthView: View {
    @Environment(AuthViewModel.self) private var viewModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case email, password
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.18), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Image(systemName: "fork.knife.circle.fill")
                            .font(.system(size: 56))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.accentColor)

                        Text("VJ Test Kitchen")
                            .font(.largeTitle.bold())

                        Text("Sign in to your kitchen")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 60)

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
                            .textContentType(.password)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { Task { await viewModel.signIn() } }
                            .textFieldStyle(.roundedBorder)

                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            Task { await viewModel.signIn() }
                        } label: {
                            Text("Sign In")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(viewModel.isSubmitting || viewModel.email.isEmpty || viewModel.password.isEmpty)
                        .padding(.top, 4)

                        Button("Create Account") {
                            Task { await viewModel.signUp() }
                        }
                        .disabled(viewModel.isSubmitting || viewModel.email.isEmpty || viewModel.password.isEmpty)
                    }
                    .padding(24)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .frame(maxWidth: 420)
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

#Preview {
    AuthView()
        .environment(AuthViewModel())
}
