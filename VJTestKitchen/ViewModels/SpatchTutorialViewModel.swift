import Foundation
import Observation

/// Drives the first-launch walkthrough (`SpatchTutorialView`, an overlay card
/// in `MainTabView` rather than a sheet): which step is showing, which real
/// tab that step should switch to (`targetTab` — `MainTabView` follows this
/// with its own `selection`, so the walkthrough shows the actual screens, not
/// static mockups), Spatch's mood, and the "Send Spatch Away"
/// sad-then-dismiss sequence. Shared at the app root (like
/// `HomeLocationViewModel`) so both `MainTabView` (presentation gating) and
/// Settings (`SpatchTutorialView`'s "Meet Spatch Again" replay) read and write
/// the same instance.
@MainActor
@Observable
final class SpatchTutorialViewModel {
    /// Bound to the overlay's presence in `MainTabView`.
    var isPresented = false
    private(set) var stepIndex = 0
    private(set) var mood: SpatchMood = .happy
    /// True for the brief "aww" beat after "Send Spatch Away", so the user
    /// sees his sad reaction before the overlay actually closes.
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

    /// The real tab `MainTabView` should switch `selection` to for the
    /// current step, so the tour narrates over the actual screen rather than
    /// a mockup. Nil for the intro step (stays wherever the app landed).
    /// Order must track `SpatchContent.tutorialSteps`: intro, Home, Recipes,
    /// Calendar, Grocery, AI Planner, outro.
    var targetTab: AppTab? {
        switch stepIndex {
        case 0: nil
        case 1: .home
        case 2: .recipes
        case 3: .calendar
        case 4: .grocery
        case 5: .planner
        default: .home
        }
    }

    /// Called once at app launch (`MainTabView.task`) — presents the tour only
    /// if it's never been shown before.
    func maybePresentOnLaunch() {
        guard !store.hasCompletedTutorial() else { return }
        isPresented = true
    }

    /// Marks the tour as shown the moment the overlay appears, so it never
    /// replays automatically regardless of how it's left (Next-through,
    /// "Send Spatch Away") — mirrors `HomeLocationPromptView.markPrompted()`.
    func onAppear() {
        store.setHasCompletedTutorial(true)
    }

    func advance() {
        if isLastStep {
            isPresented = false
        } else {
            stepIndex += 1
            mood = Self.mood(forStep: stepIndex)
        }
    }

    func goBack() {
        guard !isFirstStep else { return }
        stepIndex -= 1
        mood = Self.mood(forStep: stepIndex)
    }

    /// Skip: Spatch turns sad for a beat, then the overlay closes on its own.
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
        mood = Self.mood(forStep: 0)
        isLeaving = false
        isPresented = true
    }

    /// A little mood variety per step so the tour itself shows off his range
    /// of expressions, not just a static happy face. Falls back to `.happy`
    /// for any index beyond the mapped steps rather than crashing, so this
    /// stays safe even if `SpatchContent.tutorialSteps` grows.
    private static func mood(forStep index: Int) -> SpatchMood {
        switch index {
        case 2: .thinking
        case 5: .surprised
        case 6: .laughing
        default: .happy
        }
    }
}
