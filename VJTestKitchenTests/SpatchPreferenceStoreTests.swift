import Foundation
import Testing
@testable import VJTestKitchen

struct SpatchPreferenceStoreTests {
    private func makeStore() -> UserDefaultsSpatchPreferenceStore {
        let suiteName = "SpatchPreferenceStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return UserDefaultsSpatchPreferenceStore(defaults: defaults)
    }

    @Test func defaultsToShown() {
        // Spatch is part of the app's personality — he's on until the user
        // explicitly sends him away.
        #expect(makeStore().loadShowSpatch() == true)
    }

    @Test func persistsBeingTurnedOff() {
        let store = makeStore()
        store.saveShowSpatch(false)
        #expect(store.loadShowSpatch() == false)
    }

    @Test func canBeTurnedBackOn() {
        let store = makeStore()
        store.saveShowSpatch(false)
        store.saveShowSpatch(true)
        #expect(store.loadShowSpatch() == true)
    }
}
