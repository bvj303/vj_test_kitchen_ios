import Foundation
import Observation

/// Drives Spatch's single fixed **perch** — the non-blocking replacement for the
/// old random-corner pop-in cameo (`SpatchBuddyView`), whose whole design was to
/// float over whatever screen was up, wherever a random corner landed. That was
/// the structural source of the recurring "Spatch overlaps a card title / stat
/// tile" bugs.
///
/// The perch is one fixed anchor (bottom-trailing, above the tab bar — see
/// `SpatchPerchView`). Every screen routes its commentary here via `post(_:mood:)`
/// instead of hosting its own overlay. A posted tip is **non-intrusive**: it
/// updates what Spatch will say and raises a small "unread" indicator, but it
/// does *not* pop a bubble open over content. The user taps the perch to read it
/// (`toggle()` / `expand()`) and ignores it to leave him collapsed — so a tip can
/// never cover interactive or text content unbidden.
///
/// One instance is owned at the app root and injected into the environment (the
/// main app's perch); the fullscreen Cook Mode surface, which sits above that,
/// owns its own local instance.
@MainActor
@Observable
final class SpatchPerchViewModel {
    /// The line Spatch is currently offering (shown when expanded).
    private(set) var message: String
    private(set) var mood: SpatchMood
    /// Whether the speech bubble is open. Only ever `true` because the user
    /// tapped — never forced open by an incoming tip.
    private(set) var isExpanded: Bool = false
    /// A fresh tip arrived while collapsed — drives the little unread dot. Cleared
    /// when the user expands to read it.
    private(set) var hasUnreadTip: Bool = false
    /// Bumped on every `post`, so the view can play a one-shot attention nudge
    /// (a small bounce) without the tip forcing itself open.
    private(set) var attentionNonce: Int = 0
    /// Extra lift for the perch so it clears a screen's own pinned bottom bar
    /// (e.g. Recipe Detail's "Start Cooking" action bar) instead of overlapping
    /// it — the very overlap this anchor exists to prevent. Screens set this
    /// while visible and reset it to 0 on the way out.
    var extraBottomInset: CGFloat = 0

    private let autoCollapseDelay: Duration?
    private var autoCollapseTask: Task<Void, Never>?

    init(
        initialMessage: String = SpatchContent.randomEncouragement(),
        initialMood: SpatchMood = .idle,
        // Once opened, the bubble tidies itself away after a while so it isn't
        // left sitting over content indefinitely.
        autoCollapseDelay: Duration? = .seconds(8)
    ) {
        self.message = initialMessage
        self.mood = initialMood
        self.autoCollapseDelay = autoCollapseDelay
    }

    /// A screen offers Spatch a fresh line. Deliberately non-intrusive: updates
    /// what he'll say and flags an unread tip (unless the bubble is already open,
    /// in which case the new line just replaces the current one), but never opens
    /// the bubble itself.
    func post(_ message: String, mood: SpatchMood = .happy) {
        self.message = message
        self.mood = mood
        if isExpanded {
            // Already reading — swap the line in place and keep the timer alive.
            scheduleAutoCollapse()
        } else {
            hasUnreadTip = true
        }
        attentionNonce += 1
    }

    /// Tap the perch: open the bubble if closed, close it if open.
    func toggle() {
        if isExpanded { collapse() } else { expand() }
    }

    /// Open the bubble to read the current line; clears the unread flag.
    func expand() {
        isExpanded = true
        hasUnreadTip = false
        scheduleAutoCollapse()
    }

    /// Tuck the bubble away.
    func collapse() {
        isExpanded = false
        autoCollapseTask?.cancel()
    }

    /// Tap the open bubble: swap in a new line without closing, and reset the
    /// auto-collapse clock since the user just engaged.
    func cycle(to message: String, mood: SpatchMood = .happy) {
        self.message = message
        self.mood = mood
        scheduleAutoCollapse()
    }

    private func scheduleAutoCollapse() {
        autoCollapseTask?.cancel()
        guard let autoCollapseDelay else { return }
        autoCollapseTask = Task { [weak self] in
            try? await Task.sleep(for: autoCollapseDelay)
            guard !Task.isCancelled else { return }
            self?.isExpanded = false
        }
    }
}
