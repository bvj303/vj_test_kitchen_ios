import Foundation
import Testing
@testable import VJTestKitchen

final class FakeAppearanceStore: AppearanceStoring, @unchecked Sendable {
    var mode: AppearanceMode = .system

    func loadAppearanceMode() -> AppearanceMode { mode }
    func saveAppearanceMode(_ mode: AppearanceMode) { self.mode = mode }
}

final class FakeSpatchPreferenceStore: SpatchPreferenceStoring, @unchecked Sendable {
    var showSpatch = true

    func loadShowSpatch() -> Bool { showSpatch }
    func saveShowSpatch(_ show: Bool) { showSpatch = show }
}

@MainActor
struct SettingsViewModelTests {
    @Test func loadsInitialModeFromStore() {
        let store = FakeAppearanceStore()
        store.mode = .dark

        let viewModel = SettingsViewModel(store: store)

        #expect(viewModel.appearanceMode == .dark)
    }

    @Test func defaultsToSystemWhenNothingStored() {
        let viewModel = SettingsViewModel(store: FakeAppearanceStore())

        #expect(viewModel.appearanceMode == .system)
    }

    @Test func settingAppearanceModePersistsToStore() {
        let store = FakeAppearanceStore()
        let viewModel = SettingsViewModel(store: store)

        viewModel.appearanceMode = .light

        #expect(store.mode == .light)
    }

    @Test func showSpatchDefaultsToOn() {
        let viewModel = SettingsViewModel(spatchStore: FakeSpatchPreferenceStore())

        #expect(viewModel.showSpatch)
    }

    @Test func loadsShowSpatchFromStore() {
        let store = FakeSpatchPreferenceStore()
        store.showSpatch = false

        let viewModel = SettingsViewModel(spatchStore: store)

        #expect(!viewModel.showSpatch)
    }

    @Test func togglingShowSpatchPersistsToStore() {
        let store = FakeSpatchPreferenceStore()
        let viewModel = SettingsViewModel(spatchStore: store)

        viewModel.showSpatch = false

        #expect(store.showSpatch == false)
    }
}

struct AppearanceModeTests {
    @Test func colorSchemeMapsCorrectly() {
        #expect(AppearanceMode.system.colorScheme == nil)
        #expect(AppearanceMode.light.colorScheme == .light)
        #expect(AppearanceMode.dark.colorScheme == .dark)
    }
}
