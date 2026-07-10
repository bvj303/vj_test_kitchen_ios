import Foundation
import Observation

/// Drives one of Spatch's floating cameo appearances outside the tutorial —
/// the Home dashboard's persistent companion, or an occasional pop-in on
/// Recipe Detail / Cook Mode. Each screen owns its own instance (different
/// triggers and content sources feed the same show/cycle/dismiss shape).
@MainActor
@Observable
final class SpatchBuddyViewModel {
    private(set) var isVisible: Bool
    private(set) var message: String
    private(set) var mood: SpatchMood

    init(startsVisible: Bool = true, initialMessage: String = SpatchContent.randomEncouragement(), initialMood: SpatchMood = .idle) {
        self.isVisible = startsVisible
        self.message = initialMessage
        self.mood = initialMood
    }

    /// Bring Spatch on screen with a specific line — used by cameos that start
    /// hidden and appear after some screen-specific trigger.
    func show(message: String, mood: SpatchMood = .happy) {
        self.message = message
        self.mood = mood
        isVisible = true
    }

    /// Tap-to-cycle: swap in a new line without hiding him.
    func cycle(to message: String, mood: SpatchMood = .happy) {
        self.message = message
        self.mood = mood
    }

    func dismiss() {
        isVisible = false
    }
}
