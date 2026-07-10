import Testing
@testable import VJTestKitchen

@MainActor
struct SpatchBuddyViewModelTests {
    @Test func startsVisibleByDefault() {
        let viewModel = SpatchBuddyViewModel(initialMessage: "Hi", initialMood: .idle)
        #expect(viewModel.isVisible)
        #expect(viewModel.message == "Hi")
        #expect(viewModel.mood == .idle)
    }

    @Test func canStartHidden() {
        let viewModel = SpatchBuddyViewModel(startsVisible: false)
        #expect(!viewModel.isVisible)
    }

    @Test func showBringsItOnScreenWithTheGivenLine() {
        let viewModel = SpatchBuddyViewModel(startsVisible: false)
        viewModel.show(message: "Look at this recipe!", mood: .happy)
        #expect(viewModel.isVisible)
        #expect(viewModel.message == "Look at this recipe!")
        #expect(viewModel.mood == .happy)
    }

    @Test func cycleSwapsTheLineWithoutHidingIt() {
        let viewModel = SpatchBuddyViewModel(initialMessage: "First")
        viewModel.cycle(to: "Second", mood: .laughing)
        #expect(viewModel.isVisible)
        #expect(viewModel.message == "Second")
        #expect(viewModel.mood == .laughing)
    }

    @Test func dismissHidesIt() {
        let viewModel = SpatchBuddyViewModel()
        viewModel.dismiss()
        #expect(!viewModel.isVisible)
    }
}
