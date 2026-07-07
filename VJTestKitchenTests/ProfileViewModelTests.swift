import Foundation
import Testing
@testable import VJTestKitchen

private struct TestError: Error, LocalizedError {
    var errorDescription: String? { "failed to load" }
}

@MainActor
struct ProfileViewModelTests {
    private func makeViewModel(
        profile: Profile = Profile(id: UUID(), displayName: "Ada Lovelace", firstName: "Ada", lastName: "Lovelace", username: "ada_l", createdAt: Date()),
        fakeProfile: FakeProfileService = FakeProfileService()
    ) -> (ProfileViewModel, FakeProfileService) {
        fakeProfile.profileToReturn = profile
        let viewModel = ProfileViewModel(profileService: fakeProfile, usernameDebounceDelay: .zero)
        return (viewModel, fakeProfile)
    }

    @Test func loadPopulatesFieldsFromFetchedProfile() async {
        let (viewModel, _) = makeViewModel()

        await viewModel.load()

        #expect(viewModel.firstName == "Ada")
        #expect(viewModel.lastName == "Lovelace")
        #expect(viewModel.username == "ada_l")
        #expect(viewModel.errorMessage == nil)
    }

    @Test func loadSurfacesErrorMessageOnFailure() async {
        let fakeProfile = FakeProfileService()
        fakeProfile.errorToThrow = TestError()
        let viewModel = ProfileViewModel(profileService: fakeProfile, usernameDebounceDelay: .zero)

        await viewModel.load()

        #expect(viewModel.errorMessage == "failed to load")
    }

    @Test func loadPopulatesAvatarUrlFromFetchedProfile() async {
        let profile = Profile(id: UUID(), displayName: "Ada Lovelace", firstName: "Ada", lastName: "Lovelace", username: "ada_l", avatarUrl: "https://cdn.example.com/a.jpg", createdAt: Date())
        let (viewModel, _) = makeViewModel(profile: profile)

        await viewModel.load()

        #expect(viewModel.avatarUrl == "https://cdn.example.com/a.jpg")
    }

    @Test func uploadAvatarSetsReturnedUrlAndPassesDataToService() async {
        let (viewModel, fakeProfile) = makeViewModel()
        await viewModel.load()
        fakeProfile.avatarUrlToReturn = "https://cdn.example.com/new.jpg?v=2"
        let data = Data([0x01, 0x02, 0x03])

        await viewModel.uploadAvatar(data)

        #expect(fakeProfile.uploadedAvatarData == [data])
        #expect(viewModel.avatarUrl == "https://cdn.example.com/new.jpg?v=2")
        #expect(viewModel.isUploadingAvatar == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func uploadAvatarSurfacesErrorAndLeavesAvatarUnchangedOnFailure() async {
        let profile = Profile(id: UUID(), displayName: "Ada", firstName: "Ada", lastName: "Lovelace", username: "ada_l", avatarUrl: "https://cdn.example.com/old.jpg", createdAt: Date())
        let (viewModel, fakeProfile) = makeViewModel(profile: profile)
        await viewModel.load()
        fakeProfile.errorToThrow = TestError()

        await viewModel.uploadAvatar(Data([0xFF]))

        #expect(viewModel.errorMessage == "failed to load")
        #expect(viewModel.avatarUrl == "https://cdn.example.com/old.jpg")
        #expect(viewModel.isUploadingAvatar == false)
    }

    @Test func unchangedUsernameIsMarkedUnchangedAndAllowsSaveWithoutARoundTrip() async {
        let (viewModel, fakeProfile) = makeViewModel()
        await viewModel.load()

        // Re-typing the same username (e.g. editing then reverting) should
        // never hit the network — it's trivially the user's own username.
        viewModel.username = "ada_l"
        try? await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.usernameAvailability == .unchanged)
        #expect(fakeProfile.checkedUsernames.isEmpty)
        #expect(viewModel.canSave == true)
    }

    @Test func changingUsernameChecksAvailability() async {
        let (viewModel, fakeProfile) = makeViewModel()
        await viewModel.load()

        viewModel.username = "newhandle"
        try? await Task.sleep(for: .milliseconds(50))

        #expect(fakeProfile.checkedUsernames == ["newhandle"])
        #expect(viewModel.usernameAvailability == .available)
    }

    @Test func changingToATakenUsernameIsMarkedTaken() async {
        let fakeProfile = FakeProfileService()
        fakeProfile.takenUsernames = ["someoneelse"]
        let (viewModel, _) = makeViewModel(fakeProfile: fakeProfile)
        await viewModel.load()

        viewModel.username = "someoneelse"
        try? await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.usernameAvailability == .taken)
        #expect(viewModel.canSave == false)
    }

    @Test func canSaveRequiresNonEmptyNames() async {
        let (viewModel, _) = makeViewModel()
        await viewModel.load()
        #expect(viewModel.canSave == true)

        viewModel.firstName = ""
        #expect(viewModel.canSave == false)
    }

    @Test func saveCallsServiceWithTrimmedNamesAndCurrentUsername() async {
        let (viewModel, fakeProfile) = makeViewModel()
        await viewModel.load()
        viewModel.firstName = "  Grace  "
        viewModel.lastName = "  Hopper  "

        await viewModel.save()

        #expect(fakeProfile.updateCallCount == 1)
        #expect(fakeProfile.lastUpdateFirstName == "Grace")
        #expect(fakeProfile.lastUpdateLastName == "Hopper")
        #expect(fakeProfile.lastUpdateUsername == "ada_l")
        #expect(viewModel.didSave == true)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func saveDoesNothingWhenCanSaveIsFalse() async {
        let (viewModel, fakeProfile) = makeViewModel()
        await viewModel.load()
        viewModel.firstName = ""

        await viewModel.save()

        #expect(fakeProfile.updateCallCount == 0)
        #expect(viewModel.didSave == false)
    }

    @Test func saveSurfacesErrorMessageOnFailure() async {
        let (viewModel, fakeProfile) = makeViewModel()
        await viewModel.load()
        fakeProfile.errorToThrow = TestError()

        await viewModel.save()

        #expect(viewModel.errorMessage == "failed to load")
        #expect(viewModel.didSave == false)
    }
}
