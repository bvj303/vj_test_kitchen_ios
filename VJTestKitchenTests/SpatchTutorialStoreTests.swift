import Foundation
import Testing
@testable import VJTestKitchen

struct SpatchTutorialStoreTests {
    private func makeStore() -> UserDefaultsSpatchTutorialStore {
        let suiteName = "SpatchTutorialStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return UserDefaultsSpatchTutorialStore(defaults: defaults)
    }

    @Test func defaultsToNotCompleted() {
        #expect(makeStore().hasCompletedTutorial() == false)
    }

    @Test func persistsCompletion() {
        let store = makeStore()
        store.setHasCompletedTutorial(true)
        #expect(store.hasCompletedTutorial() == true)
    }

    @Test func canBeResetToNotCompleted() {
        let store = makeStore()
        store.setHasCompletedTutorial(true)
        store.setHasCompletedTutorial(false)
        #expect(store.hasCompletedTutorial() == false)
    }
}
