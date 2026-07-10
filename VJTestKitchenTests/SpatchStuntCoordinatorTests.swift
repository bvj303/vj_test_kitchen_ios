import Foundation
import Testing
@testable import VJTestKitchen

@MainActor
struct SpatchStuntCoordinatorTests {
    /// Millisecond-scale timings so the scheduling loop can be exercised for
    /// real in tests without multi-minute sleeps.
    private func makeCoordinator() -> SpatchStuntCoordinator {
        SpatchStuntCoordinator(
            initialDelaySeconds: 0.01...0.02,
            intervalSeconds: 0.01...0.02,
            retryDelaySeconds: 0.01,
            stuntDurationOverride: 0.05
        )
    }

    /// Polls until `condition` holds, or fails after ~1s — the coordinator's
    /// loop advances on its own MainActor sleeps, so tests wait rather than
    /// assume exact timing.
    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test func startsIdle() {
        let coordinator = makeCoordinator()
        #expect(coordinator.activeRun == nil)
        #expect(!coordinator.isPerforming)
        #expect(!coordinator.hasVisibleCameo)
    }

    @Test func tracksCameoVisibilityAcrossMultipleScreens() {
        let coordinator = makeCoordinator()
        let home = UUID()
        let detail = UUID()

        coordinator.setCameoVisible(true, id: home)
        coordinator.setCameoVisible(true, id: detail)
        #expect(coordinator.hasVisibleCameo)

        // One cameo hiding doesn't clear the stage while another is still up.
        coordinator.setCameoVisible(false, id: home)
        #expect(coordinator.hasVisibleCameo)

        coordinator.setCameoVisible(false, id: detail)
        #expect(!coordinator.hasVisibleCameo)
    }

    @Test func performsAStuntAndClearsItWhenDone() async {
        let coordinator = makeCoordinator()
        let loop = Task { await coordinator.run(isEnabled: { true }) }
        defer { loop.cancel() }

        #expect(await waitUntil { coordinator.isPerforming })
        let run = coordinator.activeRun
        #expect(run != nil)
        #expect(await waitUntil { !coordinator.isPerforming })
    }

    @Test func backToBackStuntsAreDifferent() async {
        let coordinator = makeCoordinator()
        let loop = Task { await coordinator.run(isEnabled: { true }) }
        defer { loop.cancel() }

        var seen: [SpatchStunt] = []
        for _ in 0..<3 {
            #expect(await waitUntil { coordinator.isPerforming })
            if let run = coordinator.activeRun { seen.append(run.stunt) }
            #expect(await waitUntil { !coordinator.isPerforming })
        }
        #expect(seen.count == 3)
        #expect(seen[0] != seen[1])
        #expect(seen[1] != seen[2])
    }

    @Test func neverPerformsWhileDisabled() async {
        let coordinator = makeCoordinator()
        let loop = Task { await coordinator.run(isEnabled: { false }) }
        defer { loop.cancel() }

        try? await Task.sleep(for: .milliseconds(150))
        #expect(!coordinator.isPerforming)
    }

    @Test func neverPerformsWhileACameoIsOnScreen() async {
        let coordinator = makeCoordinator()
        coordinator.setCameoVisible(true, id: UUID())
        let loop = Task { await coordinator.run(isEnabled: { true }) }
        defer { loop.cancel() }

        try? await Task.sleep(for: .milliseconds(150))
        #expect(!coordinator.isPerforming)
    }

    @Test func resumesOnceTheStageClears() async {
        let coordinator = makeCoordinator()
        let cameo = UUID()
        coordinator.setCameoVisible(true, id: cameo)
        let loop = Task { await coordinator.run(isEnabled: { true }) }
        defer { loop.cancel() }

        try? await Task.sleep(for: .milliseconds(100))
        #expect(!coordinator.isPerforming)

        coordinator.setCameoVisible(false, id: cameo)
        #expect(await waitUntil { coordinator.isPerforming })
    }

    @Test func cancelActiveStuntClearsTheStageImmediately() async {
        let coordinator = makeCoordinator()
        let loop = Task { await coordinator.run(isEnabled: { true }) }
        defer { loop.cancel() }

        #expect(await waitUntil { coordinator.isPerforming })
        coordinator.cancelActiveStunt()
        #expect(!coordinator.isPerforming)
    }

    @Test func cancellingTheLoopClearsAnyActiveStunt() async {
        let coordinator = makeCoordinator()
        let loop = Task { await coordinator.run(isEnabled: { true }) }

        #expect(await waitUntil { coordinator.isPerforming })
        loop.cancel()
        #expect(await waitUntil { !coordinator.isPerforming })
    }
}
