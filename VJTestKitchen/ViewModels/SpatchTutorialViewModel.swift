import Foundation
import Observation

/// Drives the first-launch walkthrough sheet (`SpatchTutorialView`): which
/// step is showing, Spatch's mood, and the "Send Spatch Away" sad-then-dismiss
/// sequence. Shared at the app root (like `HomeLocationViewModel`) so both
/// `MainTabView` (presentation gating) and Settings (`SpatchTutorialView`'s
/// "Meet Spatch Again" replay) read and write the same instance.
@MainActor
@Observable
final class SpatchTutorialViewModel {
    /// Bound to the presenting `.sheet(isPresented:)` in `MainTabView`.
    var isPresented = false
    private(set) var stepIndex = 0
    private(set) var mood: SpatchMood = .happy
    /// True for the brief "aww" beat after "Send Spatch Away", so the user
    /// sees his sad reaction before the sheet actually closes.
    private(set) var isLeaving = false

    private let store: SpatchTutorialStoring
    private let leavingDelay: Duration

    init(
        store: SpatchTutorialStoring = UserDefaultsSpatchTutorialStore(),
        leavingDelay: Duration = .seconds(1.6)
    ) {
        self.store = store
        self.leavingDelay = leavingDelay
    }

    var steps: [SpatchContent.TutorialStep] { SpatchContent.tutorialSteps }
    var currentStep: SpatchContent.TutorialStep { steps[stepIndex] }
    var isFirstStep: Bool { stepIndex == 0 }
    var isLastStep: Bool { stepIndex == steps.count - 1 }

    /// Called once at app launch (`MainTabView.task`) — presents the tour only
    /// if it's never been shown before.
    func maybePresentOnLaunch() {
        guard !store.hasCompletedTutorial() else { return }
        isPresented = true
    }

    /// Marks the tour as shown the moment the sheet appears, so it never
    /// replays automatically regardless of how it's left (Next-through,
    /// "Send Spatch Away", or a swipe-dismiss) — mirrors
    /// `HomeLocationPromptView.markPrompted()`.
    func onAppear() {
        store.setHasCompletedTutorial(true)
    }

    func advance() {
        if isLastStep {
            isPresented = false
        } else {
            stepIndex += 1
        }
    }

    func goBack() {
        guard !isFirstStep else { return }
        stepIndex -= 1
    }

    /// Skip: Spatch turns sad for a beat, then the sheet closes on its own.
    func sendAway() {
        mood = .sad
        isLeaving = true
        Task {
            try? await Task.sleep(for: leavingDelay)
            isPresented = false
        }
    }

    /// "Meet Spatch Again" from Settings.
    func restart() {
        stepIndex = 0
        mood = .happy
        isLeaving = false
        isPresented = true
    }
}
