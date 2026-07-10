import Foundation
import Observation

/// Schedules Spatch's surprise stunt flybys (`SpatchStunt`) — one at a time,
/// at random intervals, and only when he isn't already on screen some other
/// way. Owned once at the app root (like `SpatchTutorialViewModel`) and
/// injected into the environment: `MainTabView` runs the scheduling loop and
/// hosts the stage overlay, while every `SpatchBuddyView` both reports its
/// cameo's visibility here (so a stunt never starts over a cameo) and hides
/// itself while a stunt is playing (so a cameo never pops in mid-stunt).
@MainActor
@Observable
final class SpatchStuntCoordinator {
    /// The stunt currently playing, or nil between performances. The stage
    /// view draws whatever this holds.
    private(set) var activeRun: SpatchStuntRun?

    var isPerforming: Bool { activeRun != nil }
    var hasVisibleCameo: Bool { !visibleCameos.isEmpty }

    private var visibleCameos: Set<UUID> = []
    private var lastStunt: SpatchStunt?

    private let initialDelaySeconds: ClosedRange<Double>
    private let intervalSeconds: ClosedRange<Double>
    private let retryDelaySeconds: Double
    /// Tests shrink stunt playback to milliseconds; nil = the stunt's real duration.
    private let stuntDurationOverride: TimeInterval?

    init(
        // First stunt fairly soon after launch so the feature is discoverable,
        // then a few minutes between performances — a delight, not a nuisance.
        initialDelaySeconds: ClosedRange<Double> = 60...110,
        intervalSeconds: ClosedRange<Double> = 150...330,
        retryDelaySeconds: Double = 25,
        stuntDurationOverride: TimeInterval? = nil
    ) {
        self.initialDelaySeconds = initialDelaySeconds
        self.intervalSeconds = intervalSeconds
        self.retryDelaySeconds = retryDelaySeconds
        self.stuntDurationOverride = stuntDurationOverride
    }

    /// Cameo views report their composed visibility here (keyed by a per-view
    /// id, since Home/Recipe Detail/Cook Mode each own a cameo) so the
    /// scheduler knows whether Spatch is already on stage somewhere.
    func setCameoVisible(_ visible: Bool, id: UUID) {
        if visible {
            visibleCameos.insert(id)
        } else {
            visibleCameos.remove(id)
        }
    }

    /// Yank the current stunt off stage immediately — used when Spatch is
    /// turned off in Settings mid-performance.
    func cancelActiveStunt() {
        activeRun = nil
    }

    /// The scheduling loop, run for the life of the signed-in UI
    /// (`MainTabView.task`, cancelled automatically on sign-out). `isEnabled`
    /// is consulted right before each performance — it carries the gates the
    /// coordinator can't see itself (the Settings toggle, the tutorial).
    func run(isEnabled: @escaping @MainActor () -> Bool) async {
        defer { activeRun = nil }
        var delay = Double.random(in: initialDelaySeconds)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }

            guard isEnabled(), !hasVisibleCameo, activeRun == nil else {
                // Stage is busy (cameo up, tutorial showing, or Spatch turned
                // off) — check back soon rather than skipping a whole interval.
                delay = retryDelaySeconds
                continue
            }

            let run = SpatchStuntRun.random(excluding: lastStunt)
            lastStunt = run.stunt
            activeRun = run
            try? await Task.sleep(for: .seconds(stuntDurationOverride ?? run.stunt.duration))
            // Guarded so a mid-performance cancelActiveStunt() (or a newer run,
            // defensively) isn't clobbered by this stale wake-up.
            if activeRun?.id == run.id {
                activeRun = nil
            }
            delay = Double.random(in: intervalSeconds)
        }
    }
}
