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
    /// the switcher rather than from a store of our own.
    private(set) var selectedAppIcon: AppIconOption
    var appIconErrorMessage: String?
    /// False on macOS (no alternate-icon API) — Settings hides the picker.
    /// Computed live, never frozen at init: UIApplication reports false while
    /// the app is still launching (this view model is created as a root
    /// `@State` before UIKit finishes), then true once launch completes.
    var supportsAppIconPicker: Bool { appIconSwitcher.supportsAlternateIcons }

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
    }

    /// Re-reads the system's current icon — the init-time read can predate
    /// launch completing (see `supportsAppIconPicker`), so Settings calls this
    /// on appear.
    func refreshSelectedAppIcon() {
        selectedAppIcon = .option(forAlternateIconName: appIconSwitcher.currentAlternateIconName)
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
