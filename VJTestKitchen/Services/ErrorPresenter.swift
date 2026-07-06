import Foundation

/// Maps low-level errors surfaced by Services into friendly, actionable copy
/// for display. Network failures in particular come back from URLSession as
/// opaque strings ("The operation couldn't be completed…"); this turns the
/// common cases into something a user can act on. Anything not specially
/// handled falls back to the error's own `localizedDescription`.
enum ErrorPresenter {
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
        return error.localizedDescription
    }
}
