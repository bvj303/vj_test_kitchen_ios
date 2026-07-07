import Foundation

/// Shared by AuthViewModel (sign-up) and ProfileViewModel (editing) so the
/// two can't drift apart. Keep in sync with the `profiles_username_format`
/// check constraint (profiles_first_last_username migration) — the server
/// is the real gate; this is fast UX feedback.
enum UsernameFormat {
    static let pattern = #"^[A-Za-z0-9_]{3,20}$"#

    static func isValid(_ username: String) -> Bool {
        username.range(of: pattern, options: .regularExpression) != nil
    }
}
