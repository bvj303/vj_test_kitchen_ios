import Foundation
import Supabase

/// Maps low-level errors surfaced by Services into friendly, actionable copy
/// for display. Network failures in particular come back from URLSession as
/// opaque strings ("The operation couldn't be completed…"), and Postgres/Auth
/// errors as raw server text ("duplicate key value violates unique
/// constraint…"); this turns the common cases into something a user can act
/// on. Anything not specially handled falls back to the error's own
/// `localizedDescription`.
enum ErrorPresenter {
    /// True when `error` is an intentional cancellation rather than a real
    /// failure — the debounced search/filter reload cancels its in-flight task
    /// on every keystroke, and the resulting throw (Swift's `CancellationError`
    /// or URLSession's `URLError(.cancelled)`) must be swallowed, not shown.
    /// Surfacing it flashed a spurious "Couldn't Load Recipes" alert while
    /// typing, which the next keystroke's reload then silently dismissed.
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    static func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .dataNotAllowed:
                return "No internet connection. Check your network and try again."
            case .timedOut:
                return "The request timed out. Please try again in a moment."
            case .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return "Couldn't reach the server. Please try again shortly."
            default:
                break
            }
        }
        // Postgres errors arrive as SQLSTATE codes with raw server text — map
        // the ones a user can plausibly trigger to copy without SQL in it.
        if let postgrestError = error as? PostgrestError {
            switch postgrestError.code {
            case "23505":
                return "That name is already taken. Try a different one."
            case "23503":
                return "That can't be saved because something it refers to no longer exists. Refresh and try again."
            case "42501":
                return "You don't have permission to do that."
            default:
                break
            }
        }
        // Auth errors: the ones reachable from the sign-in / sign-up forms.
        if let authError = error as? AuthError {
            switch authError.errorCode {
            case .invalidCredentials:
                return "Incorrect email or password."
            case .userAlreadyExists, .emailExists:
                return "An account with this email already exists. Try signing in instead."
            case .weakPassword:
                return "That password is too weak. Please choose a stronger one."
            case .overRequestRateLimit:
                return "Too many attempts. Please wait a moment and try again."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
