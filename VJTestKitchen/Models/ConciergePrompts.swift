import Foundation

/// The Kitchen Concierge's tap-to-send prompts. Pure and unit-tested, same shape
/// as `RecipeSuggester`: starters fill an empty chat, and follow-ups under the
/// latest reply are picked from what that reply contains — so every answer has
/// an obvious next step instead of a blank text field.
enum ConciergePrompts {
    struct Prompt: Identifiable, Hashable, Sendable {
        let label: String
        let prompt: String
        let systemImage: String

        var id: String { label }
    }

    /// Shown when the chat is empty. Each one is a request the concierge's tools
    /// can actually fulfil (search the catalog, propose meals for real dates).
    static let starters: [Prompt] = [
        Prompt(
            label: "Plan this week's dinners",
            prompt: "Plan dinners for the rest of this week and add them to my calendar.",
            systemImage: "calendar.badge.plus"
        ),
        Prompt(
            label: "Quick weeknight dinner",
            prompt: "Find me a dinner I can make tonight in under 30 minutes.",
            systemImage: "timer"
        ),
        Prompt(
            label: "Use the pantry",
            prompt: "What can I cook tonight with common pantry ingredients?",
            systemImage: "basket"
        ),
        Prompt(
            label: "Surprise me",
            prompt: "Surprise me with something new to cook this weekend.",
            systemImage: "sparkles"
        ),
    ]

    /// At most three follow-ups for a reply that cited `recipeCount` recipes and
    /// proposed `mealPlanActionCount` calendar additions and
    /// `groceryActionCount` grocery additions.
    static func followUps(recipeCount: Int, mealPlanActionCount: Int, groceryActionCount: Int) -> [Prompt] {
        var prompts: [Prompt] = []
        if mealPlanActionCount > 0 {
            if groceryActionCount == 0 {
                prompts.append(Prompt(
                    label: "Make a grocery list",
                    prompt: "Add the ingredients for these meals to my grocery list.",
                    systemImage: "cart.badge.plus"
                ))
            }
            prompts.append(Prompt(
                label: "Swap a meal",
                prompt: "Swap one of those meals for something different.",
                systemImage: "arrow.triangle.2.circlepath"
            ))
            prompts.append(quicker)
        } else if groceryActionCount > 0 {
            prompts.append(Prompt(
                label: "Add it to my calendar",
                prompt: "Add that recipe to my calendar for dinner this week.",
                systemImage: "calendar.badge.plus"
            ))
            prompts.append(different)
        } else if recipeCount > 0 {
            prompts.append(Prompt(
                label: "Plan these this week",
                prompt: "Add those recipes to my calendar for dinners this week.",
                systemImage: "calendar.badge.plus"
            ))
            prompts.append(quicker)
            prompts.append(different)
        } else {
            prompts.append(Prompt(
                label: "Suggest some recipes",
                prompt: "Suggest a few recipes from my collection.",
                systemImage: "book.pages"
            ))
            prompts.append(Prompt(
                label: "Plan this week's dinners",
                prompt: "Plan dinners for the rest of this week and add them to my calendar.",
                systemImage: "calendar.badge.plus"
            ))
        }
        return Array(prompts.prefix(3))
    }

    private static let quicker = Prompt(
        label: "Something quicker",
        prompt: "Something quicker — under 30 minutes.",
        systemImage: "timer"
    )

    private static let different = Prompt(
        label: "Show different ones",
        prompt: "Show me different recipes than those.",
        systemImage: "shuffle"
    )
}
