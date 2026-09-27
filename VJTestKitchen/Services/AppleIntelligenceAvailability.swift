import Foundation
import FoundationModels

/// Whether Apple Intelligence's on-device model can run here, as user-facing
/// copy. Gates the on-device features — recipe photo/PDF scanning
/// (`RecipePhotoImportService`) and recipe smarts (`RecipeWritingService`) — so
/// their buttons hide on ineligible devices and the Simulator instead of leading
/// to a dead end. The Kitchen Concierge is cloud-backed (the `ai-chat` Edge
/// Function) and doesn't depend on this. See DECISIONS.md (2026-09-27).
enum AppleIntelligenceAvailability {
    /// `nil` when the on-device model is usable right now.
    static var unavailableReason: String? {
        unavailableReason(for: SystemLanguageModel.default.availability)
    }

    /// Maps the model's availability to friendly copy, or `nil` when it's
    /// usable. Pure so it's testable without an eligible device.
    static func unavailableReason(for availability: SystemLanguageModel.Availability) -> String? {
        switch availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This feature needs Apple Intelligence, which isn't supported on this device."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in Settings to use this feature."
            case .modelNotReady:
                return "Apple Intelligence is still getting set up. Please try again in a little while."
            @unknown default:
                return "Apple Intelligence isn't available on this device right now."
            }
        @unknown default:
            return "Apple Intelligence isn't available on this device right now."
        }
    }
}

/// Thrown when an on-device feature is invoked but the model can't run. Its
/// `errorDescription` is already user-facing, so `ErrorPresenter` surfaces it
/// verbatim (via its `localizedDescription` fallback).
struct AppleIntelligenceUnavailableError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
