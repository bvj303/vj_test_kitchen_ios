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
final class FakeAppIconSwitcher: AppIconSwitching {
    var supportsAlternateIcons = true
    var currentAlternateIconName: String?
    var setNames: [String?] = []
    var errorToThrow: Error?

    func setAlternateIcon(named name: String?) async throws {
        if let errorToThrow { throw errorToThrow }
        setNames.append(name)
        currentAlternateIconName = name
    }
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

    // MARK: - App icon

    @Test func defaultsToClassicIconWhenSystemReportsNone() {
        let viewModel = SettingsViewModel(appIconSwitcher: FakeAppIconSwitcher())

        #expect(viewModel.selectedAppIcon == .classic)
    }

    @Test func readsCurrentAlternateIconFromSystem() {
        let switcher = FakeAppIconSwitcher()
        switcher.currentAlternateIconName = "AppIconPizza"

        let viewModel = SettingsViewModel(appIconSwitcher: switcher)

        #expect(viewModel.selectedAppIcon == .pizzaSurf)
    }

    @Test func exposesWhetherThePlatformSupportsIconSwitching() {
        let switcher = FakeAppIconSwitcher()
        switcher.supportsAlternateIcons = false

        let viewModel = SettingsViewModel(appIconSwitcher: switcher)

        #expect(!viewModel.supportsAppIconPicker)
    }

    @Test func supportReflectsTheSystemLive_notFrozenAtInit() {
        // UIApplication reports supportsAlternateIcons=false while the app is
        // still launching (when the root view models are created) and true
        // once launch completes — the picker must not vanish forever because
        // the flag was read too early.
        let switcher = FakeAppIconSwitcher()
        switcher.supportsAlternateIcons = false
        let viewModel = SettingsViewModel(appIconSwitcher: switcher)

        switcher.supportsAlternateIcons = true

        #expect(viewModel.supportsAppIconPicker)
    }

    @Test func refreshRereadsTheSystemsCurrentIcon() {
        // Same early-launch caveat as `supportsAlternateIcons`: the name read
        // at init can be stale, so Settings re-syncs on appear.
        let switcher = FakeAppIconSwitcher()
        let viewModel = SettingsViewModel(appIconSwitcher: switcher)
        #expect(viewModel.selectedAppIcon == .classic)

        switcher.currentAlternateIconName = "AppIconRocket"
        viewModel.refreshSelectedAppIcon()

        #expect(viewModel.selectedAppIcon == .rocketRide)
    }

    @Test func selectingAnAlternateIconPassesItsSetName() async {
        let switcher = FakeAppIconSwitcher()
        let viewModel = SettingsViewModel(appIconSwitcher: switcher)

        await viewModel.selectAppIcon(.rocketRide)

        #expect(switcher.setNames == ["AppIconRocket"])
        #expect(viewModel.selectedAppIcon == .rocketRide)
    }

    @Test func selectingClassicPassesNilToRestoreThePrimaryIcon() async {
        let switcher = FakeAppIconSwitcher()
        switcher.currentAlternateIconName = "AppIconBalloon"
        let viewModel = SettingsViewModel(appIconSwitcher: switcher)

        await viewModel.selectAppIcon(.classic)

        #expect(switcher.setNames == [nil])
        #expect(viewModel.selectedAppIcon == .classic)
    }

    @Test func reselectingTheCurrentIconDoesNotCallTheSystem() async {
        let switcher = FakeAppIconSwitcher()
        let viewModel = SettingsViewModel(appIconSwitcher: switcher)

        await viewModel.selectAppIcon(.classic)

        #expect(switcher.setNames.isEmpty)
    }

    @Test func failedSwitchKeepsSelectionAndSurfacesError() async {
        let switcher = FakeAppIconSwitcher()
        switcher.errorToThrow = URLError(.cannotConnectToHost)
        let viewModel = SettingsViewModel(appIconSwitcher: switcher)

        await viewModel.selectAppIcon(.pizzaSurf)

        #expect(viewModel.selectedAppIcon == .classic)
        #expect(viewModel.appIconErrorMessage != nil)
    }

    @Test func successfulSwitchClearsAnEarlierError() async {
        let switcher = FakeAppIconSwitcher()
        switcher.errorToThrow = URLError(.cannotConnectToHost)
        let viewModel = SettingsViewModel(appIconSwitcher: switcher)
        await viewModel.selectAppIcon(.pizzaSurf)

        switcher.errorToThrow = nil
        await viewModel.selectAppIcon(.balloonRide)

        #expect(viewModel.appIconErrorMessage == nil)
        #expect(viewModel.selectedAppIcon == .balloonRide)
    }
}

struct AppearanceModeTests {
    @Test func colorSchemeMapsCorrectly() {
        #expect(AppearanceMode.system.colorScheme == nil)
        #expect(AppearanceMode.light.colorScheme == .light)
        #expect(AppearanceMode.dark.colorScheme == .dark)
    }
}
