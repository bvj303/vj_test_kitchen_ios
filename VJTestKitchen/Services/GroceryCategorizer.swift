import Foundation

/// Guesses a `GroceryCategory` from a free-text item name (e.g. "boneless
/// chicken thighs" -> `.meat`). Deliberately keyword-driven and generous: the
/// user can always override the guess, so a broad, forgiving match beats a
/// precise-but-sparse one. Matching is token-based (whole words, with simple
/// plural stripping) plus multi-word phrase checks, so "butternut squash"
/// doesn't get miscategorized as dairy off the substring "butter".
enum GroceryCategorizer {
    static func categorize(_ name: String) -> GroceryCategory {
        let normalized = name.lowercased()
        let tokens = tokens(from: normalized)
        guard !tokens.isEmpty else { return .other }

        // Two passes, both in priority order (more specific / collision-prone
        // categories before broad catch-alls like pantry). Multi-word phrases
        // are matched first so a compound like "orange juice" resolves to
        // beverages instead of matching the bare "orange" produce token.
        for category in matchOrder {
            guard let keywords = keywordsByCategory[category] else { continue }
            for keyword in keywords where keyword.contains(" ") {
                if normalized.contains(keyword) { return category }
            }
        }
        for category in matchOrder {
            guard let keywords = keywordsByCategory[category] else { continue }
            for keyword in keywords where !keyword.contains(" ") {
                if tokens.contains(keyword) { return category }
            }
        }
        return .other
    }

    /// Splits into lowercased word tokens, stripping punctuation, and adds a
    /// naive singular form of each token so "apples"/"tomatoes" match
    /// "apple"/"tomato".
    private static func tokens(from normalized: String) -> Set<String> {
        let raw = normalized.split { !$0.isLetter }.map(String.init)
        var result = Set<String>()
        for word in raw where !word.isEmpty {
            result.insert(word)
            if word.hasSuffix("ies"), word.count > 3 {
                result.insert(String(word.dropLast(3)) + "y") // berries -> berry
            }
            if word.hasSuffix("es"), word.count > 3 {
                result.insert(String(word.dropLast(2))) // tomatoes -> tomato
            }
            if word.hasSuffix("s"), word.count > 3 {
                result.insert(String(word.dropLast(1))) // apples -> apple
            }
        }
        return result
    }

    private static let matchOrder: [GroceryCategory] = [
        .seafood, .meat, .dairy, .produce, .bakery, .frozen,
        .beverages, .condiments, .bakingSpices, .snacks, .household, .pantry,
    ]

    private static let keywordsByCategory: [GroceryCategory: [String]] = [
        .produce: [
            "apple", "banana", "orange", "lemon", "lime", "grape", "grapefruit",
            "strawberry", "blueberry", "raspberry", "blackberry", "berry", "berries",
            "melon", "watermelon", "cantaloupe", "peach", "pear", "plum", "mango",
            "pineapple", "kiwi", "cherry", "apricot", "pomegranate", "avocado",
            "lettuce", "spinach", "kale", "arugula", "cabbage", "broccoli",
            "cauliflower", "carrot", "celery", "cucumber", "zucchini", "squash",
            "pepper", "peppers", "bell pepper", "jalapeno", "tomato", "onion",
            "scallion", "shallot", "garlic", "ginger", "potato", "sweet potato",
            "yam", "mushroom", "corn", "pea", "peas", "green bean", "asparagus",
            "eggplant", "beet", "radish", "turnip", "leek", "cilantro", "parsley",
            "basil", "mint", "rosemary", "thyme", "herb", "herbs", "salad", "greens",
            "sprout", "sprouts", "produce", "fruit", "vegetable", "veggie",
        ],
        .meat: [
            "chicken", "beef", "steak", "pork", "bacon", "ham", "sausage", "turkey",
            "lamb", "veal", "ground beef", "ground turkey", "ground pork", "mince",
            "ribs", "brisket", "roast", "chop", "chops", "tenderloin", "sirloin",
            "meat", "poultry", "hot dog", "hotdog", "prosciutto", "pepperoni",
            "salami", "pancetta", "chorizo", "wing", "wings", "drumstick", "thigh",
            "thighs", "breast", "cutlet", "deli", "bologna",
        ],
        .seafood: [
            "fish", "salmon", "tuna", "cod", "tilapia", "halibut", "trout",
            "shrimp", "prawn", "crab", "lobster", "clam", "mussel", "oyster",
            "scallop", "squid", "calamari", "anchovy", "sardine", "seafood",
            "haddock", "mahi", "snapper", "catfish", "crawfish",
        ],
        .dairy: [
            "milk", "cream", "half and half", "heavy cream", "sour cream", "butter",
            "cheese", "cheddar", "mozzarella", "parmesan", "parmigiano", "feta",
            "gouda", "brie", "ricotta", "cottage cheese", "cream cheese", "yogurt",
            "yoghurt", "egg", "eggs", "margarine", "buttermilk", "creamer",
            "whipped cream", "kefir", "provolone", "swiss", "gruyere", "mascarpone",
        ],
        .bakery: [
            "bread", "baguette", "roll", "rolls", "bun", "buns", "bagel", "bagels",
            "croissant", "muffin", "muffins", "tortilla", "tortillas", "pita",
            "naan", "loaf", "cake", "pie crust", "donut", "doughnut", "pastry",
            "brioche", "sourdough", "focaccia", "ciabatta", "biscuit", "biscuits",
            "cornbread", "bakery",
        ],
        .pantry: [
            "rice", "pasta", "spaghetti", "macaroni", "noodle", "noodles", "penne",
            "flour", "sugar", "brown sugar", "powdered sugar", "oat", "oats",
            "oatmeal", "cereal", "granola", "quinoa", "couscous", "lentil",
            "lentils", "bean", "beans", "chickpea", "chickpeas", "black bean",
            "kidney bean", "canned", "can", "broth", "stock", "bouillon", "soup",
            "tomato sauce", "tomato paste", "crushed tomato", "diced tomato",
            "oil", "olive oil", "vegetable oil", "canola oil", "coconut oil",
            "vinegar", "peanut butter", "almond butter", "jam", "jelly", "honey",
            "syrup", "maple syrup", "cracker", "crackers", "breadcrumb",
            "breadcrumbs", "panko", "cornmeal", "cornstarch", "gravy", "raisin",
            "raisins", "dried", "nut", "nuts", "almond", "walnut", "pecan",
            "cashew", "peanut", "seed", "seeds", "tofu", "tahini", "coconut milk",
            "salsa",
        ],
        .bakingSpices: [
            "salt", "pepper", "black pepper", "cinnamon", "nutmeg", "cumin",
            "paprika", "oregano", "chili powder", "cayenne", "turmeric", "curry",
            "garlic powder", "onion powder", "vanilla", "vanilla extract",
            "baking soda", "baking powder", "yeast", "cocoa", "cocoa powder",
            "chocolate chip", "chocolate chips", "food coloring", "sprinkles",
            "spice", "spices", "seasoning", "bay leaf", "clove", "cloves",
            "cardamom", "coriander", "sesame", "molasses", "shortening",
            "confectioners", "icing",
        ],
        .condiments: [
            "ketchup", "catsup", "mustard", "mayo", "mayonnaise", "relish",
            "bbq sauce", "barbecue sauce", "soy sauce", "hot sauce", "sriracha",
            "worcestershire", "ranch", "dressing", "marinade", "teriyaki",
            "hoisin", "fish sauce", "pesto", "aioli", "tartar sauce", "sauce",
            "condiment", "pickle", "pickles", "olives", "capers",
        ],
        .frozen: [
            "frozen", "ice cream", "popsicle", "frozen pizza", "frozen yogurt",
            "sherbet", "sorbet", "ice", "frozen vegetable", "frozen fruit",
            "waffle", "waffles", "frozen meal", "tv dinner", "gelato",
        ],
        .beverages: [
            "water", "sparkling water", "soda", "cola", "pop", "juice",
            "orange juice", "apple juice", "lemonade", "coffee", "tea", "beer",
            "wine", "liquor", "vodka", "whiskey", "rum", "tequila", "gin",
            "cocktail", "energy drink", "sports drink", "gatorade", "kombucha",
            "smoothie", "milkshake", "drink", "beverage", "seltzer", "tonic",
        ],
        .snacks: [
            "potato chips", "corn chips", "tortilla chips", "banana chips",
            "chips", "pretzel", "pretzels", "popcorn", "cookie", "cookies",
            "candy", "chocolate", "chocolate bar", "granola bar", "protein bar",
            "trail mix", "gum", "snack", "snacks", "fruit snack", "jerky",
            "nachos", "dip", "wafer", "brownie", "brownies",
        ],
        .household: [
            "paper towel", "paper towels", "toilet paper", "napkin", "napkins",
            "tissue", "tissues", "dish soap", "detergent", "laundry", "bleach",
            "cleaner", "sponge", "sponges", "trash bag", "garbage bag", "foil",
            "aluminum foil", "plastic wrap", "parchment", "ziploc", "storage bag",
            "batteries", "battery", "light bulb", "shampoo", "conditioner", "soap",
            "toothpaste", "toothbrush", "deodorant", "lotion", "razor", "diaper",
            "diapers", "wipes", "hand soap", "sanitizer", "floss", "household",
        ],
    ]
}
