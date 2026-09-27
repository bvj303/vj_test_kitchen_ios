import Foundation
import Testing
import FoundationModels
@testable import VJTestKitchen

/// The on-device features (recipe photo/PDF scan, generate description, suggest
/// tags) gate on this — its copy must not mention the Kitchen Concierge, which
/// runs in the cloud and works on every device.
struct AppleIntelligenceAvailabilityTests {
    @Test func availableModelHasNoReason() {
        #expect(AppleIntelligenceAvailability.unavailableReason(for: .available) == nil)
    }

    @Test func ineligibleDeviceMentionsAppleIntelligence() {
        let reason = AppleIntelligenceAvailability.unavailableReason(for: .unavailable(.deviceNotEligible))
        #expect(reason?.contains("Apple Intelligence") == true)
    }

    @Test func disabledIntelligencePointsToSettings() {
        let reason = AppleIntelligenceAvailability.unavailableReason(for: .unavailable(.appleIntelligenceNotEnabled))
        #expect(reason?.localizedCaseInsensitiveContains("Settings") == true)
    }

    @Test func modelNotReadyAsksToRetry() {
        let reason = AppleIntelligenceAvailability.unavailableReason(for: .unavailable(.modelNotReady))
        #expect(reason?.localizedCaseInsensitiveContains("try again") == true)
    }

    @Test func copyNeverMentionsTheCloudConcierge() {
        let reasons: [SystemLanguageModel.Availability] = [
            .unavailable(.deviceNotEligible), .unavailable(.appleIntelligenceNotEnabled), .unavailable(.modelNotReady),
        ]
        for availability in reasons {
            let reason = AppleIntelligenceAvailability.unavailableReason(for: availability)
            #expect(reason?.contains("Concierge") == false)
        }
    }
}
