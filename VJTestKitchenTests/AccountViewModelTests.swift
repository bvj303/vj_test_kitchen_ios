import Foundation
import Testing
@testable import VJTestKitchen

@MainActor
struct AccountViewModelTests {
    private struct LoadError: Error {}

    @Test func loadSetsAvatarUrlFromFetchedProfile() async {
        let fake = FakeProfileService()
        fake.profileToReturn = Profile(id: UUID(), avatarUrl: "https://cdn.example.com/a.jpg", createdAt: Date())
        let viewModel = AccountViewModel(profileService: fake)

        await viewModel.load()

        #expect(viewModel.avatarUrl == "https://cdn.example.com/a.jpg")
    }

    @Test func loadLeavesAvatarNilOnFailure() async {
        let fake = FakeProfileService()
        fake.errorToThrow = LoadError()
        let viewModel = AccountViewModel(profileService: fake)

        await viewModel.load()

        // Best-effort: a failed load leaves the button on its symbol fallback,
        // it does not surface an error in chrome.
        #expect(viewModel.avatarUrl == nil)
    }

    @Test func setAvatarUrlUpdatesValueForLiveRefresh() {
        let viewModel = AccountViewModel(profileService: FakeProfileService())

        viewModel.setAvatarUrl("https://cdn.example.com/new.jpg")

        #expect(viewModel.avatarUrl == "https://cdn.example.com/new.jpg")
    }
}
