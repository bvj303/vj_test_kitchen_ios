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

    private let store: AppearanceStoring

    init(store: AppearanceStoring = UserDefaultsAppearanceStore()) {
        self.store = store
        self.appearanceMode = store.loadAppearanceMode()
    }
}
