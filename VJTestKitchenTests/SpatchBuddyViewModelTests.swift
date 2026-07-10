import Testing
@testable import VJTestKitchen

@MainActor
struct SpatchBuddyViewModelTests {
    private func makeViewModel(
        startsVisible: Bool = true,
        initialMessage: String = "Hi",
        initialMood: SpatchMood = .idle,
        autoHideDelay: Duration? = nil
    ) -> SpatchBuddyViewModel {
        SpatchBuddyViewModel(startsVisible: startsVisible, initialMessage: initialMessage, initialMood: initialMood, autoHideDelay: autoHideDelay)
    }

    @Test func startsVisibleByDefault() {
        let viewModel = makeViewModel(initialMessage: "Hi", initialMood: .idle)
        #expect(viewModel.isVisible)
        #expect(viewModel.message == "Hi")
        #expect(viewModel.mood == .idle)
    }

    @Test func canStartHidden() {
        let viewModel = makeViewModel(startsVisible: false)
        #expect(!viewModel.isVisible)
    }

    @Test func startsAtARandomValidCorner() {
        let viewModel = makeViewModel()
        #expect(SpatchCorner.allCases.contains(viewModel.corner))
    }

    @Test func showBringsItOnScreenWithTheGivenLine() {
        let viewModel = makeViewModel(startsVisible: false)
        viewModel.show(message: "Look at this recipe!", mood: .happy)
        #expect(viewModel.isVisible)
        #expect(viewModel.message == "Look at this recipe!")
        #expect(viewModel.mood == .happy)
    }

    @Test func showAlwaysMovesToADifferentCorner() {
        // `.random(excluding:)` is called with the corner at the time of the
        // call, so every `show()` is guaranteed to relocate — deterministic,
        // not just eventual.
        let viewModel = makeViewModel(startsVisible: false)
        let startingCorner = viewModel.corner
        viewModel.show(message: "Hi", mood: .happy)
        #expect(viewModel.corner != startingCorner)
    }

    @Test func cycleSwapsTheLineWithoutHidingIt() {
        let viewModel = makeViewModel(initialMessage: "First")
        viewModel.cycle(to: "Second", mood: .laughing)
        #expect(viewModel.isVisible)
        #expect(viewModel.message == "Second")
        #expect(viewModel.mood == .laughing)
    }

    @Test func dismissHidesIt() {
        let viewModel = makeViewModel()
        viewModel.dismiss()
        #expect(!viewModel.isVisible)
    }

    @Test func autoHidesAfterTheConfiguredDelay() async {
        let viewModel = makeViewModel(autoHideDelay: .milliseconds(20))
        #expect(viewModel.isVisible)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(!viewModel.isVisible)
    }

    @Test func cycleResetsTheAutoHideClockRatherThanLettingTheOriginalTimerFire() async {
        let viewModel = makeViewModel(autoHideDelay: .milliseconds(40))
        try? await Task.sleep(for: .milliseconds(20))
        viewModel.cycle(to: "Updated")
        // 50ms since start — past the *original* 40ms window, but cycle()
        // should have pushed the hide-time out from its own call.
        try? await Task.sleep(for: .milliseconds(30))
        #expect(viewModel.isVisible)
        // Now past 40ms since the cycle() call itself.
        try? await Task.sleep(for: .milliseconds(30))
        #expect(!viewModel.isVisible)
    }

    @Test func dismissThenShowAgainStillAutoHidesOnItsOwnSchedule() async {
        let viewModel = makeViewModel(autoHideDelay: .milliseconds(30))
        viewModel.dismiss()
        try? await Task.sleep(for: .milliseconds(50)) // past the original timer's window
        #expect(!viewModel.isVisible)

        viewModel.show(message: "Hi", mood: .happy)
        #expect(viewModel.isVisible)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!viewModel.isVisible)
    }

    @Test func tiltLeansInwardFromWhicheverSideHePopsFrom() {
        // Positive degrees lean clockwise. Popping from the leading side he
        // should lean right (toward screen center); from trailing, left.
        for _ in 0..<20 {
            let viewModel = makeViewModel(startsVisible: false)
            viewModel.show(message: "Hi", mood: .happy)
            let magnitude = abs(viewModel.tilt)
            #expect(magnitude >= 3 && magnitude <= 12)
            if viewModel.corner.isTrailing {
                #expect(viewModel.tilt < 0)
            } else {
                #expect(viewModel.tilt > 0)
            }
        }
    }

    @Test func showRerollsTheTiltSoRepeatEntrancesVaryInAngle() {
        let viewModel = makeViewModel(startsVisible: false)
        var seen = Set<Double>()
        for _ in 0..<40 {
            viewModel.show(message: "Hi", mood: .happy)
            seen.insert(viewModel.tilt)
        }
        #expect(seen.count > 1)
    }

    @Test func noAutoHideWhenDelayIsNil() async {
        let viewModel = makeViewModel(autoHideDelay: nil)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.isVisible)
    }
}
