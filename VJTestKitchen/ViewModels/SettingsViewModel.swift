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

    private let store: AppearanceStoring
    private let spatchStore: SpatchPreferenceStoring

    init(
        store: AppearanceStoring = UserDefaultsAppearanceStore(),
        spatchStore: SpatchPreferenceStoring = UserDefaultsSpatchPreferenceStore()
    ) {
        self.store = store
        self.spatchStore = spatchStore
        self.appearanceMode = store.loadAppearanceMode()
        self.showSpatch = spatchStore.loadShowSpatch()
    }
}
