import SwiftUI

/// The terracotta wash behind the whole auth flow. Shared by `AuthView` (sign
/// in) and `CreateAccountView` (sign up) so the two screens read as one
/// continuous space rather than a gradient that disappears the moment you tap
/// "Create Account".
struct AuthBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.18), Color.platformBackground],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

/// A filled, comfortably tall (≥44pt) text-field container with a real focus
/// ring — the native inset-form look. Replaces the thin `.roundedBorder` style,
/// whose hairline outline is a small tap target and reads as flat against the
/// glass card. Callers pass whether the field currently holds focus so the ring
/// can highlight in the brand accent.
struct AuthFieldStyle: ViewModifier {
    var isFocused: Bool

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(.fill.tertiary, in: shape)
            .overlay {
                shape.strokeBorder(
                    isFocused ? Color.accentColor : Color.primary.opacity(0.10),
                    lineWidth: isFocused ? 2 : 1
                )
            }
            .contentShape(shape)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

extension View {
    /// Applies the shared filled auth-field look, highlighting the focus ring
    /// when `isFocused`.
    func authFieldStyle(isFocused: Bool) -> some View {
        modifier(AuthFieldStyle(isFocused: isFocused))
    }
}
