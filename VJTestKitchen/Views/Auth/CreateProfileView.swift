import SwiftUI

/// First step of account creation — collects first/last name and a chosen
/// username before the email/password step (CreateAccountView). Pushed from
/// AuthView's "Create Account" link.
struct CreateProfileView: View {
    @Environment(AuthViewModel.self) private var viewModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case firstName, lastName, username
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("Create Your Profile")
                        .font(.title2.bold())

                    Text("Let's start with a few details.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)

                VStack(spacing: 14) {
                    TextField("First Name", text: $viewModel.firstName)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .firstName)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .lastName }
                        .textFieldStyle(.roundedBorder)

                    TextField("Last Name", text: $viewModel.lastName)
                        .textContentType(.familyName)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .lastName)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .username }
                        .textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Username", text: $viewModel.username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .username)
                            .submitLabel(.done)
                            .textFieldStyle(.roundedBorder)

                        if let usernameStatusText {
                            Text(usernameStatusText)
                                .font(.footnote)
                                .foregroundStyle(usernameStatusColor)
                        }
                    }

                    NavigationLink {
                        CreateAccountView()
                    } label: {
                        Text("Next")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!viewModel.canProceedToAccountStep)
                    .padding(.top, 4)
                }
                .padding(24)
                .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .frame(maxWidth: 420)
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.inline)
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
        CreateProfileView()
            .environment(AuthViewModel())
    }
}
