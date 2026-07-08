import Foundation

/// A single rendered grocery row. In the "by recipe" view it wraps exactly one
/// item; in the "by category" view several like-named items (matched case- and
/// plural-insensitively) are combined into one line whose quantity is the summed
/// total. Every row action (toggle/delete/recategorize) fans out to `items`.
struct GroceryDisplayRow: Identifiable, Sendable {
    let id: String
    let name: String
    let quantityText: String
    /// True only when *every* underlying item is checked, so a partially-bought
    /// combined line still reads as "to buy".
    let isChecked: Bool
    let category: GroceryCategory
    let items: [GroceryItem]

    var isCombined: Bool { items.count > 1 }

    /// Wraps a single item unchanged — the "by recipe" case, where each source
    /// line stays separate.
    init(single item: GroceryItem) {
        self.id = item.id.uuidString
        self.name = item.name
        self.quantityText = GroceryListViewModel.formattedQuantity(amount: item.amount, unit: item.unit)
        self.isChecked = item.isChecked
        self.category = item.category
        self.items = [item]
    }

    init(
        id: String, name: String, quantityText: String, isChecked: Bool,
        category: GroceryCategory, items: [GroceryItem]
    ) {
        self.id = id
        self.name = name
        self.quantityText = quantityText
        self.isChecked = isChecked
        self.category = category
        self.items = items
    }
}

/// Combines like ingredients for the "by category" grocery view: "2 lemons" from
/// one recipe and "1 lemon" from another read as a single "3" line. Pure and
/// unit-tested (same shape as `GroceryCategorizer`). Names match case- and
/// plural-insensitively; quantities sum *per unit*, so unlike units
/// ("2 cups" + "200 g") stay as separate addends joined with " + " rather than
/// being nonsensically added together — and fractional amounts add cleanly
/// (0.5 + 0.5 → "1").
enum GroceryAggregator {
    /// Combines `items` (assumed to share a category) into display rows — one per
    /// distinct ingredient, in first-seen order.
    static func combine(_ items: [GroceryItem]) -> [GroceryDisplayRow] {
        var order: [String] = []
        var groups: [String: [GroceryItem]] = [:]
        for item in items {
            let key = nameKey(item.name)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(item)
        }
        return order.map { key in
            let group = groups[key] ?? []
            let category = group.first?.category ?? .other
            return GroceryDisplayRow(
                id: "cat:\(category.rawValue):\(key)",
                name: group.first?.name ?? key,
                quantityText: combinedQuantityText(group),
                isChecked: !group.isEmpty && group.allSatisfy(\.isChecked),
                category: category,
                items: group
            )
        }
    }

    /// Sums amounts by unit and renders the total: "3", "2 cups + 200 g", ….
    /// Amounts sharing a (plural-insensitive) unit add together; different units
    /// become separate "+"-joined addends. Units are shown in their first-seen
    /// original spelling.
    static func combinedQuantityText(_ items: [GroceryItem]) -> String {
        var order: [String] = []
        var totals: [String: Double] = [:]
        var displayUnit: [String: String] = [:]
        for item in items {
            let key = unitKey(item.unit)
            if totals[key] == nil {
                order.append(key)
                displayUnit[key] = item.unit.trimmingCharacters(in: .whitespaces)
            }
            totals[key, default: 0] += item.amount
        }
        let pieces = order.compactMap { key -> String? in
            let text = GroceryListViewModel.formattedQuantity(
                amount: totals[key] ?? 0, unit: displayUnit[key] ?? ""
            )
            return text.isEmpty ? nil : text
        }
        return pieces.joined(separator: " + ")
    }

    /// Canonical match key for an item name — lowercased, whitespace-collapsed,
    /// each word naively singularized so "Lemons"/"lemon" collapse together.
    static func nameKey(_ name: String) -> String {
        name.lowercased()
            .split { $0.isWhitespace }
            .map { singularize(String($0)) }
            .joined(separator: " ")
    }

    private static func unitKey(_ unit: String) -> String {
        singularize(unit.lowercased().trimmingCharacters(in: .whitespaces))
    }

    /// Strips a naive trailing plural: "berries"→"berry", "tomatoes"→"tomato",
    /// "lemons"→"lemon". Deliberately simple — it only has to be *consistent*
    /// (it's a match key, never shown), not linguistically perfect.
    private static func singularize(_ word: String) -> String {
        guard word.count > 3 else { return word }
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        for suffix in ["oes", "shes", "ches", "xes", "ses"] where word.hasSuffix(suffix) {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast(1)) }
        return word
    }
}
