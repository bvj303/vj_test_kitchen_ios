import AppIntents

/// Siri/Shortcuts: search the user's own recipe collection by keyword and read
/// back the matches ("Hey Siri, find a carbonara in VJ Test Kitchen"). Runs in
/// the app's process against the signed-in Supabase session, so results are
/// RLS-scoped just like the in-app list. Unlike the Kitchen Concierge, this
/// needs no Apple Intelligence — it works on every device.
struct FindRecipeIntent: AppIntent {
    static let title: LocalizedStringResource = "Find a Recipe"
    static let description = IntentDescription(
        "Search your VJ Test Kitchen recipe collection for a dish by name."
    )

    @Parameter(title: "Recipe or ingredient")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Find \(\.$query) in VJ Test Kitchen")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "What recipe would you like to find?")
        }
        do {
            let matches = try await RecipeService().fetchPage(offset: 0, limit: 5, matching: trimmed)
            return .result(dialog: IntentDialog(stringLiteral: Self.dialog(for: matches, query: trimmed)))
        } catch {
            return .result(dialog: "Sorry, I couldn't search your recipes right now. Open VJ Test Kitchen and make sure you're signed in.")
        }
    }

    /// Pure, unit-tested: turns search results into a spoken sentence.
    static func dialog(for recipes: [Recipe], query: String) -> String {
        guard !recipes.isEmpty else {
            return "I couldn't find any recipes matching \"\(query)\" in your collection."
        }
        let titles = recipes.map(\.title)
        if titles.count == 1 {
            return "I found \(titles[0]) in your collection."
        }
        let head = titles.dropLast().joined(separator: ", ")
        let last = titles.last ?? ""
        return "I found \(titles.count) recipes: \(head), and \(last)."
    }
}

/// Siri/Shortcuts: add an item to the grocery list ("Hey Siri, add butter to my
/// VJ Test Kitchen grocery list"). The aisle category is guessed on-device with
/// the existing `GroceryCategorizer` (no AI needed). Session-scoped via the
/// grocery service, so it lands in the signed-in user's private list.
struct AddGroceryItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Grocery List"
    static let description = IntentDescription(
        "Add an item to your VJ Test Kitchen grocery list."
    )

    @Parameter(title: "Item")
    var item: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$item) to my grocery list")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "What would you like to add to your grocery list?")
        }
        do {
            let draft = GroceryItemDraft(
                name: trimmed,
                amount: 0,
                unit: "",
                category: GroceryCategorizer.categorize(trimmed)
            )
            _ = try await GroceryItemService().add(draft)
            return .result(dialog: IntentDialog(stringLiteral: "Added \(trimmed) to your grocery list."))
        } catch {
            return .result(dialog: "Sorry, I couldn't add that right now. Open VJ Test Kitchen and make sure you're signed in.")
        }
    }
}
