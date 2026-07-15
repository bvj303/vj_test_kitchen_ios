import SwiftUI

struct AuthView: View {
    @Environment(AuthViewModel.self) private var viewModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case email, password
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            ZStack {
                AuthBackground()

                // Center the card vertically so a roomy screen (iPad, Mac)
                // doesn't leave the sign-in floating against the top with the
                // bottom two-thirds empty. The Spacers collapse to nothing on a
                // compact iPhone where the content already fills the height.
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 28) {
                            Spacer(minLength: 0)

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

                            VStack(spacing: 14) {
                                TextField("Email", text: $viewModel.email)
                                    .textContentType(.emailAddress)
                                    .platformKeyboardType(.emailAddress)
                                    .platformAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .focused($focusedField, equals: .email)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .password }
                                    .authFieldStyle(isFocused: focusedField == .email)

                                SecureField("Password", text: $viewModel.password)
                                    .textContentType(.password)
                                    .focused($focusedField, equals: .password)
                                    .submitLabel(.go)
                                    .onSubmit { Task { await viewModel.signIn() } }
                                    .authFieldStyle(isFocused: focusedField == .password)

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
                                    Task { await viewModel.signIn() }
                                } label: {
                                    Text("Sign In")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.glassProminent)
                                .disabled(viewModel.isSubmitting || viewModel.email.isEmpty || viewModel.password.isEmpty)
                                .padding(.top, 4)

                                NavigationLink("Create Account") {
                                    CreateAccountView()
                                }
                                .disabled(viewModel.isSubmitting)
                            }
                            .padding(24)
                            .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .frame(maxWidth: 420)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        }
        .dismissesKeyboardOnBackgroundTap()
        .keyboardDoneButton()
    }
}

#Preview {
    AuthView()
        .environment(AuthViewModel())
}
