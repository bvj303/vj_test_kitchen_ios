import Foundation

/// Spatch's library of dialogue — jokes, encouragement, tutorial-step copy, and
/// context-aware quips for the Home/Recipe/Cook Mode cameos. Pure content plus
/// pure selection logic (same shape as `RecipeSuggester`/`HolidayProvider`), no
/// view or service dependency, so it's fully unit-testable.
enum SpatchContent {
    // MARK: - Jokes

    static let jokes: [String] = [
        "Why did the tomato turn red? It saw the salad dressing!",
        "I'm on a seafood diet. I see food, and I whisk it into something delicious.",
        "What do you call a fake noodle? An impasta.",
        "I whisked it all for this app, you know.",
        "Why did the cookie go to the doctor? It was feeling crumbly.",
        "I'm a spatula, not a magician — but flipping pancakes without a tear IS kind of a trick.",
        "What's a spatula's favorite music? Anything with a good flip side.",
        "Lettuce romaine calm and cook something good.",
        "I don't do egg puns. They're too eggs-aggerating.",
        "Someone told me I was spoon-fed my jokes. Rude. I'm a spatula. I'd never.",
    ]

    static func randomJoke() -> String {
        jokes.randomElement() ?? jokes[0]
    }

    // MARK: - Encouragement / idle lines

    static let encouragements: [String] = [
        "Hi! I'm just hanging out here if you need a recipe idea.",
        "Cooking something good today?",
        "Poke me for a joke. I've got dozens. Some are even funny.",
        "You've got this. Whatever 'this' turns out to be.",
        "I believe in you and your ability to not burn the garlic.",
    ]

    static func randomEncouragement() -> String {
        encouragements.randomElement() ?? encouragements[0]
    }

    // MARK: - Home recommendation line

    /// A line tying Spatch's Home cameo to the dashboard's actual suggested
    /// recipe, falling back to generic encouragement when none is loaded yet.
    static func recommendationLine(recipeTitle: String?) -> String {
        guard let recipeTitle else { return randomEncouragement() }
        let templates = [
            "Psst — I've got a good feeling about \(recipeTitle) today.",
            "If I had hands, I'd already be making \(recipeTitle).",
            "\(recipeTitle) is calling your name. Spatulas have great ears.",
            "How about \(recipeTitle)? Trust me on this one.",
        ]
        return templates.randomElement() ?? "How about \(recipeTitle)?"
    }

    // MARK: - Recipe Detail cameo lines

    /// A line referencing something concrete about the recipe being viewed
    /// (its prep time or first tag), falling back to a general cooking joke
    /// when neither is available.
    static func recipeCameoLine(prepTime: Int?, tag: String?) -> String {
        var pool: [String] = []
        if let prepTime, prepTime <= 20 {
            pool.append("Only \(prepTime) minutes? I like your style — fast hands, big flavor.")
        }
        if let prepTime, prepTime >= 60 {
            pool.append("\(prepTime) minutes, huh. A labor of love. I'll be right here rooting for you.")
        }
        if let tag {
            pool.append("Ooh, \(tag.lowercased())! One of my favorites.")
        }
        guard !pool.isEmpty else { return randomJoke() }
        return pool.randomElement() ?? pool[0]
    }

    // MARK: - Cook Mode lines

    /// An encouragement line keyed to how far through the recipe the cook is
    /// (0...1 fraction of steps checked off).
    static func cookModeEncouragement(progress: Double) -> String {
        let lines: [String]
        switch progress {
        case ..<0.34:
            lines = ["You've got this — one step at a time!", "Mise en place, then go. You're doing great."]
        case ..<0.75:
            lines = ["Smells good from here. Keep going!", "Halfway to delicious."]
        default:
            lines = ["Almost there — don't forget to taste as you go!", "So close. Don't let me distract you."]
        }
        return lines.randomElement() ?? lines[0]
    }

    static let cookModeCompletionLines: [String] = [
        "You did it! Go plate that masterpiece.",
        "Chef's kiss. Literally, if I had lips shaped like that.",
        "Look at you go! Dinner is served.",
    ]

    static func randomCompletionLine() -> String {
        cookModeCompletionLines.randomElement() ?? cookModeCompletionLines[0]
    }

    // MARK: - Tutorial

    struct TutorialStep: Equatable {
        let title: String
        let message: String
        let symbol: String
    }

    static let tutorialSteps: [TutorialStep] = [
        TutorialStep(
            title: "Hi, I'm Spatch!",
            message: "I'm your kitchen sidekick. Give me a sec to show you around — I promise it's quick.",
            symbol: "hand.wave.fill"
        ),
        TutorialStep(
            title: "Home",
            message: "This is your dashboard — I'll drop recipe ideas here based on the day and the weather.",
            symbol: "house.fill"
        ),
        TutorialStep(
            title: "Recipes",
            message: "Browse, search, and save recipes here. Tap the + to add your own — I love a good original recipe.",
            symbol: "fork.knife"
        ),
        TutorialStep(
            title: "Meal Calendar",
            message: "Plan out your week and I'll help keep it interesting — no one wants pasta five nights in a row. Unless you want that. No judgment.",
            symbol: "calendar"
        ),
        TutorialStep(
            title: "Grocery List",
            message: "Add ingredients straight from a recipe and check them off at the store. I'll keep it organized by aisle.",
            symbol: "cart.fill"
        ),
        TutorialStep(
            title: "AI Planner",
            message: "Stuck on what to make? Ask in here. I mostly just make jokes, but the AI is actually useful.",
            symbol: "sparkles"
        ),
        TutorialStep(
            title: "That's the tour!",
            message: "I'll pop by now and then with recipe ideas and the occasional pun. Let's get cooking!",
            symbol: "checkmark.seal.fill"
        ),
    ]

    static let sadGoodbyeLine = "Oh... okay. I'll just be over here if you need me."
}
