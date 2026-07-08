import Foundation
import Testing
@testable import VJTestKitchen

private func item(
    name: String, amount: Double = 1, unit: String = "", category: GroceryCategory = .produce,
    isChecked: Bool = false
) -> GroceryItem {
    GroceryItem(
        id: UUID(), userId: UUID(), name: name, amount: amount, unit: unit,
        category: category, isChecked: isChecked, sourceRecipeId: nil,
        sourceRecipeTitle: nil, createdAt: Date()
    )
}

struct GroceryAggregatorTests {
    @Test func combinesLikeNamedItemsSummingCount() {
        let rows = GroceryAggregator.combine([
            item(name: "Lemons", amount: 2),
            item(name: "Lemon", amount: 1),
        ])
        #expect(rows.count == 1)
        #expect(rows[0].quantityText == "3")
        #expect(rows[0].isCombined)
        #expect(rows[0].items.count == 2)
    }

    @Test func sumsFractionalAmounts() {
        let rows = GroceryAggregator.combine([
            item(name: "Butter", amount: 0.5, unit: "cup", category: .dairy),
            item(name: "butter", amount: 0.5, unit: "cups", category: .dairy),
        ])
        #expect(rows.count == 1)
        #expect(rows[0].quantityText == "1 cup")
    }

    @Test func keepsUnlikeUnitsAsSeparateAddends() {
        let rows = GroceryAggregator.combine([
            item(name: "Flour", amount: 2, unit: "cups", category: .pantry),
            item(name: "flour", amount: 200, unit: "g", category: .pantry),
        ])
        #expect(rows.count == 1)
        #expect(rows[0].quantityText == "2 cups + 200 g")
    }

    @Test func distinctNamesStaySeparateInFirstSeenOrder() {
        let rows = GroceryAggregator.combine([
            item(name: "Onion", amount: 1),
            item(name: "Garlic", amount: 2),
            item(name: "Onions", amount: 3),
        ])
        #expect(rows.map(\.name) == ["Onion", "Garlic"])
        #expect(rows[0].quantityText == "4")
    }

    @Test func combinedRowCheckedOnlyWhenAllChecked() {
        let partly = GroceryAggregator.combine([
            item(name: "Egg", amount: 1, category: .dairy, isChecked: true),
            item(name: "Eggs", amount: 2, category: .dairy, isChecked: false),
        ])
        #expect(partly[0].isChecked == false)

        let all = GroceryAggregator.combine([
            item(name: "Egg", amount: 1, category: .dairy, isChecked: true),
            item(name: "Eggs", amount: 2, category: .dairy, isChecked: true),
        ])
        #expect(all[0].isChecked == true)
    }

    @Test func zeroAmountToTasteItemsCollapseWithoutQuantity() {
        let rows = GroceryAggregator.combine([
            item(name: "Salt", amount: 0, unit: "", category: .bakingSpices),
            item(name: "salt", amount: 0, unit: "", category: .bakingSpices),
        ])
        #expect(rows.count == 1)
        #expect(rows[0].quantityText == "")
    }
}
