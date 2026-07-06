import Foundation
import Testing
@testable import VJTestKitchen

struct ReminderServiceTests {
    @Test func skipsItemsAlreadyPresentInList() {
        let result = ReminderService.itemsToCreate(
            desired: ["200 g Flour", "1 Salt"],
            existingTitles: ["200 g flour"]
        )
        #expect(result == ["1 Salt"])
    }

    @Test func dedupesRepeatsWithinDesiredList() {
        let result = ReminderService.itemsToCreate(
            desired: ["Milk", "milk ", "Eggs"],
            existingTitles: []
        )
        #expect(result == ["Milk", "Eggs"])
    }

    @Test func keepsEverythingWhenListIsEmpty() {
        let result = ReminderService.itemsToCreate(desired: ["A", "B"], existingTitles: [])
        #expect(result == ["A", "B"])
    }
}
