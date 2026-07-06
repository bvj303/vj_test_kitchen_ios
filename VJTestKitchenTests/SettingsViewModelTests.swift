import Foundation
import Testing
@testable import VJTestKitchen

final class FakeAppearanceStore: AppearanceStoring, @unchecked Sendable {
    var mode: AppearanceMode = .system

    func loadAppearanceMode() -> AppearanceMode { mode }
    func saveAppearanceMode(_ mode: AppearanceMode) { self.mode = mode }
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
}

struct AppearanceModeTests {
    @Test func colorSchemeMapsCorrectly() {
        #expect(AppearanceMode.system.colorScheme == nil)
        #expect(AppearanceMode.light.colorScheme == .light)
        #expect(AppearanceMode.dark.colorScheme == .dark)
    }
}
