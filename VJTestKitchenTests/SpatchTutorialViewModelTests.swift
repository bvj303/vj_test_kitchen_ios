import Foundation
import Testing
@testable import VJTestKitchen

private final class FakeSpatchTutorialStore: SpatchTutorialStoring, @unchecked Sendable {
    var completed = false
    func hasCompletedTutorial() -> Bool { completed }
    func setHasCompletedTutorial(_ completed: Bool) { self.completed = completed }
}

@MainActor
struct SpatchTutorialViewModelTests {
    private func makeViewModel(store: FakeSpatchTutorialStore = FakeSpatchTutorialStore()) -> SpatchTutorialViewModel {
        SpatchTutorialViewModel(store: store, leavingDelay: .milliseconds(10))
    }

    @Test func presentsOnLaunchWhenNeverCompleted() {
        let viewModel = makeViewModel()
        viewModel.maybePresentOnLaunch()
        #expect(viewModel.isPresented)
    }

    @Test func doesNotPresentOnLaunchWhenAlreadyCompleted() {
        let store = FakeSpatchTutorialStore()
        store.completed = true
        let viewModel = makeViewModel(store: store)
        viewModel.maybePresentOnLaunch()
        #expect(!viewModel.isPresented)
    }

    @Test func onAppearRecordsCompletion() {
        let store = FakeSpatchTutorialStore()
        let viewModel = makeViewModel(store: store)
        viewModel.onAppear()
        #expect(store.hasCompletedTutorial())
    }

    @Test func advanceStepsThroughTheTourThenDismisses() {
        let viewModel = makeViewModel()
        viewModel.isPresented = true
        let stepCount = viewModel.steps.count
        for _ in 0..<(stepCount - 1) {
            viewModel.advance()
        }
        #expect(viewModel.isLastStep)
        #expect(viewModel.isPresented) // still up until the final "Let's Cook!" tap
        viewModel.advance()
        #expect(!viewModel.isPresented)
    }

    @Test func goBackDoesNothingOnFirstStep() {
        let viewModel = makeViewModel()
        viewModel.goBack()
        #expect(viewModel.isFirstStep)
    }

    @Test func goBackReturnsToThePreviousStep() {
        let viewModel = makeViewModel()
        viewModel.advance()
        viewModel.advance()
        viewModel.goBack()
        #expect(viewModel.stepIndex == 1)
    }

    @Test func sendAwayTurnsSadImmediatelyThenDismissesAfterTheDelay() async {
        let viewModel = makeViewModel()
        viewModel.isPresented = true
        viewModel.sendAway()

        #expect(viewModel.mood == .sad)
        #expect(viewModel.isLeaving)
        #expect(viewModel.isPresented) // still up during the goodbye beat

        try? await Task.sleep(for: .milliseconds(100))
        #expect(!viewModel.isPresented)
    }

    @Test func restartResetsToTheFirstStepAndPresents() {
        let viewModel = makeViewModel()
        viewModel.advance()
        viewModel.sendAway()

        viewModel.restart()

        #expect(viewModel.stepIndex == 0)
        #expect(viewModel.mood == .happy)
        #expect(!viewModel.isLeaving)
        #expect(viewModel.isPresented)
    }
}
