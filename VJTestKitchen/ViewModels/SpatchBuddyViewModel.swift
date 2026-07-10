import Foundation
import Observation

/// Drives one of Spatch's floating cameo appearances outside the tutorial —
/// pop-ins on Home, Recipe Detail, and Cook Mode. Each screen owns its own
/// instance (different triggers and content sources feed the same
/// show/cycle/dismiss shape). Every appearance picks a random screen corner
/// and auto-hides after a delay, on top of the explicit dismiss (tap the × or
/// swipe — see `SpatchBuddyView`).
@MainActor
@Observable
final class SpatchBuddyViewModel {
    private(set) var isVisible: Bool
    private(set) var message: String
    private(set) var mood: SpatchMood
    private(set) var corner: SpatchCorner

    private let autoHideDelay: Duration?
    private var autoHideTask: Task<Void, Never>?

    init(
        startsVisible: Bool = true,
        initialMessage: String = SpatchContent.randomEncouragement(),
        initialMood: SpatchMood = .idle,
        autoHideDelay: Duration? = .seconds(7)
    ) {
        self.isVisible = startsVisible
        self.message = initialMessage
        self.mood = initialMood
        self.corner = .random()
        self.autoHideDelay = autoHideDelay
        if startsVisible { scheduleAutoHide() }
    }

    /// Bring Spatch on screen (at a fresh corner) with a specific line — used
    /// by cameos that start hidden and appear after some screen-specific
    /// trigger.
    func show(message: String, mood: SpatchMood = .happy) {
        self.message = message
        self.mood = mood
        corner = .random(excluding: corner)
        isVisible = true
        scheduleAutoHide()
    }

    /// Tap-to-cycle: swap in a new line (and hop to a new corner) without
    /// hiding him, and reset the auto-hide clock since the user just engaged.
    func cycle(to message: String, mood: SpatchMood = .happy) {
        self.message = message
        self.mood = mood
        corner = .random(excluding: corner)
        scheduleAutoHide()
    }

    func dismiss() {
        isVisible = false
        autoHideTask?.cancel()
    }

    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        guard let autoHideDelay else { return }
        autoHideTask = Task { [weak self] in
            try? await Task.sleep(for: autoHideDelay)
            guard !Task.isCancelled else { return }
            self?.isVisible = false
        }
    }
}
