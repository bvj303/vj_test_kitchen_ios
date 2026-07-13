import Foundation

/// Spatch's library of dialogue — jokes, encouragement, tutorial-step copy, and
/// context-aware quips for the Home/Recipe/Cook Mode cameos. Pure content plus
/// pure selection logic (same shape as `RecipeSuggester`/`HolidayProvider`), no
/// view or service dependency, so it's fully unit-testable.
enum SpatchContent {
    // MARK: - Jokes

    static let jokes: [String] = [
        "Why did the tomato turn red? It saw the salad dressing.",
        "What do you call a fake noodle? An impasta.",
        "Why did the cookie go to the doctor? It was feeling crumbly.",
        "I'm a spatula, not a magician — but flipping pancakes without a tear IS kind of a trick.",
        "What's a spatula's favorite music? Anything with a good flip side.",
        "Lettuce romaine calm and cook something good.",
        "I don't do egg puns. They're too eggs-aggerating.",
        "Why did the chef quit? He couldn't ketchup with the orders.",
        "What do you call cheese that isn't yours? Nacho cheese.",
        "I burned a salad once. Don't ask. Some things can't be undone.",
        "Why do spatulas make terrible secret-keepers? We always flip.",
        "What did the spatula say to the pancake? I've got your back — and your front, honestly.",
        "Why did the baker stop making bread? He kneaded a break.",
        "I tried to make a joke about butter, but it didn't spread well.",
        "What's a spatula's least favorite exercise? Flipping out.",
        "Why don't eggs tell jokes? They'd crack each other up.",
        "What do you call a sad strawberry? A blueberry.",
        "I stayed up all night wondering where the sun went. Then it dawned on me.",
        "Why was the kitchen so tense? Someone kept whisking it.",
        "What's the most patient vegetable? A slow-cooker squash.",
        "I told the onion a joke. It brought tears to its eyes.",
        "Why did the pot feel important? Everyone kept saying it was the main dish.",
        "What did one plate say to the other? Dinner's on me.",
        "I'm great at multitasking — I can stir, flip, and drop a pun at the same time.",
        "Why did the recipe break up with the oven? It needed some space.",
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
        "Every great meal starts with someone brave enough to open the fridge.",
        "Not sure what to make? That's half the fun. The other half is eating it.",
        "Fun fact: nothing bad has ever happened while snacking. Probably.",
        "You know what pairs well with anything? Confidence. And maybe garlic.",
        "Reminder: a slightly lopsided dish still tastes exactly the same.",
        "I've never met a recipe I didn't want to cheer on from the sidelines.",
        "Whatever you're making, I already think it smells great.",
        "Cooking tip: taste as you go. Second tip: taste again, just to be sure.",
    ]

    static func randomEncouragement() -> String {
        encouragements.randomElement() ?? encouragements[0]
    }

    // MARK: - Home recommendation line

    /// The pool of Home recommendation lines for a given recipe title, exposed
    /// separately from `recommendationLine` so it's unit-testable (e.g. for
    /// tone — these are meant to read as gentle nudges, not a hard sell).
    static func recommendationTemplates(for recipeTitle: String) -> [String] {
        [
            "Psst — I've got a good feeling about \(recipeTitle) today.",
            "If I had hands, I'd already be making \(recipeTitle).",
            "\(recipeTitle) is calling your name. Spatulas have great ears.",
            "How about \(recipeTitle)? Just a thought.",
            "\(recipeTitle) has been on my mind today, no idea why.",
            "No pressure, but \(recipeTitle) sounds pretty good right about now.",
            "\(recipeTitle) crossed my mind. That's all, just putting it out there.",
        ]
    }

    /// A line tying Spatch's Home cameo to the dashboard's actual suggested
    /// recipe, falling back to generic encouragement when none is loaded yet.
    static func recommendationLine(recipeTitle: String?) -> String {
        guard let recipeTitle else { return randomEncouragement() }
        let templates = recommendationTemplates(for: recipeTitle)
        return templates.randomElement() ?? "How about \(recipeTitle)?"
    }

    // MARK: - Catchphrases

    /// Spatch's signature one-liners — short, punchy, and recognizably "him,"
    /// distinct from the puns in `jokes` and the softer support in
    /// `encouragements`. Mixed into the Home cameo rotation alongside jokes so
    /// he doesn't read as constantly pitching a recipe.
    static let catchphrases: [String] = [
        "Let's get flipping!",
        "Kitchen's open. Let's go.",
        "Spatula up. Let's do this.",
        "Whisk happens. Cook anyway.",
        "Aprons on, puns loaded.",
        "Today's forecast: a good chance of dinner.",
        "Let's make something worth telling people about.",
        "Heat's on whenever you're ready.",
        "One flip at a time. That's the whole philosophy.",
        "Good things come to those who preheat.",
    ]

    static func randomCatchphrase() -> String {
        catchphrases.randomElement() ?? catchphrases[0]
    }

    // MARK: - Recipe Detail cameo lines

    /// A line referencing something concrete about the recipe being viewed
    /// (its prep time or first tag), falling back to a general cooking joke
    /// when neither is available.
    static func recipeCameoLine(prepTime: Int?, tag: String?) -> String {
        var pool: [String] = []
        if let prepTime, prepTime <= 20 {
            pool.append("Only \(prepTime) minutes? I like your style — fast hands, big flavor.")
            pool.append("\(prepTime) minutes is basically a snack by kitchen standards.")
        }
        if let prepTime, prepTime >= 60 {
            pool.append("\(prepTime) minutes, huh. A labor of love. I'll be right here rooting for you.")
            pool.append("\(prepTime) minutes of your life, dedicated to this. Respect.")
        }
        if let tag {
            pool.append("Ooh, \(tag.lowercased())! One of my favorites.")
            pool.append("\(tag.lowercased()) again? Bold choice. I love it.")
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
            lines = [
                "You've got this — one step at a time!",
                "Mise en place, then go. You're doing great.",
                "Off to a great start. I'm not even worried.",
            ]
        case ..<0.75:
            lines = [
                "Smells good from here. Keep going!",
                "Halfway to delicious.",
                "This is the part where it starts looking like the photo.",
            ]
        default:
            lines = [
                "Almost there — don't forget to taste as you go!",
                "So close. Don't let me distract you.",
                "The finish line smells amazing.",
            ]
        }
        return lines.randomElement() ?? lines[0]
    }

    static let cookModeCompletionLines: [String] = [
        "You did it! Go plate that masterpiece.",
        "Chef's kiss. Literally, if I had lips shaped like that.",
        "Look at you go! Dinner is served.",
        "That's a wrap. Somebody call the food critics.",
        "You cooked. Actually cooked. I'm proud of you.",
        "Nailed it. Now the real challenge: not eating it standing over the stove.",
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
