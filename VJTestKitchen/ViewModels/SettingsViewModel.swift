import Foundation
import Observation

/// Backs `SettingsView`. Owned at the app root (`VJTestKitchenApp`) and
/// injected into the environment so the appearance override can be read by
/// the root scene's `.preferredColorScheme`, not just the Settings screen.
@MainActor
@Observable
final class SettingsViewModel {
    var appearanceMode: AppearanceMode {
        didSet { store.saveAppearanceMode(appearanceMode) }
    }

    /// Whether Spatch shows up at all — gates his cameo pop-ins, stunt
    /// flybys, and the walkthrough replay (see `SpatchPreferenceStoring`).
    var showSpatch: Bool {
        didSet { spatchStore.saveShowSpatch(showSpatch) }
    }

    /// The icon look currently applied — the system owns the persistence
    /// (`setAlternateIconName` survives relaunches), so this is read back from
    /// the switcher at init rather than from a store of our own.
    private(set) var selectedAppIcon: AppIconOption
    var appIconErrorMessage: String?
    /// False on macOS (no alternate-icon API) — Settings hides the picker.
    let supportsAppIconPicker: Bool

    private let store: AppearanceStoring
    private let spatchStore: SpatchPreferenceStoring
    private let appIconSwitcher: AppIconSwitching

    init(
        store: AppearanceStoring = UserDefaultsAppearanceStore(),
        spatchStore: SpatchPreferenceStoring = UserDefaultsSpatchPreferenceStore(),
        appIconSwitcher: AppIconSwitching = AppIconSwitcher()
    ) {
        self.store = store
        self.spatchStore = spatchStore
        self.appIconSwitcher = appIconSwitcher
        self.appearanceMode = store.loadAppearanceMode()
        self.showSpatch = spatchStore.loadShowSpatch()
        self.selectedAppIcon = .option(forAlternateIconName: appIconSwitcher.currentAlternateIconName)
        self.supportsAppIconPicker = appIconSwitcher.supportsAlternateIcons
    }

    /// Applies an icon look, keeping the current selection if the system
    /// rejects the switch.
    func selectAppIcon(_ option: AppIconOption) async {
        guard option != selectedAppIcon else { return }
        do {
            try await appIconSwitcher.setAlternateIcon(named: option.alternateIconName)
            selectedAppIcon = option
            appIconErrorMessage = nil
        } catch {
            appIconErrorMessage = ErrorPresenter.message(for: error)
        }
    }
}
