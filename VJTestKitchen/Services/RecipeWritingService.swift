import Foundation
import FoundationModels

/// On-device "recipe smarts" backed by Apple Intelligence's Foundation Model:
/// generate a description for a recipe from its title/ingredients/steps, and
/// suggest tags. Entirely on-device (no network, no API key), availability-
/// gated exactly like the concierge and the photo scanner, and following the
/// same injectable-closure + pure-prompt-helper shape as
/// `RecipePhotoImportService` so the wiring stays unit-testable without a model.
struct RecipeWritingService {
    /// Runs a single-shot text prompt through the on-device model. Injectable so
    /// callers can be tested without an eligible device.
    var generateText: @Sendable (_ instructions: String, _ prompt: String) async throws -> String = {
        try await RecipeWritingService.runModel(instructions: $0, prompt: $1)
    }

    /// Fills in a `@Generable` value from a prompt. Injectable for the tag path.
    var generateTags: @Sendable (_ instructions: String, _ prompt: String) async throws -> [String] = {
        try await RecipeWritingService.runTagModel(instructions: $0, prompt: $1)
    }

    /// Availability check, injectable so tests can simulate an eligible device
    /// (the on-device model is never available on the CI/simulator host). Non-
    /// `nil` is the user-facing reason it can't run; `nil` means it's usable.
    /// Reuses the concierge's copy so every AI feature speaks with one voice.
    var checkAvailability: @Sendable () -> String? = {
        AppleIntelligenceAIService.unavailableReason(for: SystemLanguageModel.default.availability)
    }

    /// Non-`nil` when on-device generation can't run here.
    var unavailableReason: String? { checkAvailability() }

    // MARK: - Description

    /// Generates a short, appetizing 1–2 sentence description from what the user
    /// has entered so far. Throws `RecipeWritingError.notEnoughContext` when
    /// there's nothing meaningful to describe yet.
    func generateDescription(title: String, ingredients: [String], instructions: String) async throws -> String {
        if let reason = unavailableReason {
            throw AppleIntelligenceUnavailableError(message: reason)
        }
        guard Self.hasEnoughContext(title: title, ingredients: ingredients, instructions: instructions) else {
            throw RecipeWritingError.notEnoughContext
        }
        let text = try await generateText(
            Self.descriptionInstructions,
            Self.descriptionPrompt(title: title, ingredients: ingredients, instructions: instructions)
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tags

    /// Suggests tags for a recipe, biased toward reusing the catalog's existing
    /// vocabulary (`existingTags`) so tags don't fragment into near-duplicates.
    /// Returns a de-duplicated, cleaned list.
    func suggestTags(title: String, ingredients: [String], instructions: String, existingTags: [String]) async throws -> [String] {
        if let reason = unavailableReason {
            throw AppleIntelligenceUnavailableError(message: reason)
        }
        guard Self.hasEnoughContext(title: title, ingredients: ingredients, instructions: instructions) else {
            throw RecipeWritingError.notEnoughContext
        }
        let raw = try await generateTags(
            Self.tagInstructions,
            Self.tagPrompt(title: title, ingredients: ingredients, instructions: instructions, existingTags: existingTags)
        )
        return Self.cleanTags(raw)
    }

    // MARK: - Model plumbing

    private static func runModel(instructions: String, prompt: String) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)
        return response.content
    }

    /// Not `private`: the `@Generable` macro synthesizes a conformance
    /// extension at file scope, which can't reach a `private` nested type.
    @Generable
    struct GeneratedTags {
        @Guide(description: "Between 2 and 5 short tags describing this recipe (course, cuisine, or key traits). Prefer tags from the provided list when they fit.")
        var tags: [String]
    }

    private static func runTagModel(instructions: String, prompt: String) async throws -> [String] {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt, generating: GeneratedTags.self)
        return response.content.tags
    }

    // MARK: - Pure helpers (unit-tested)

    /// There's enough to work with once the title plus at least one of
    /// ingredients/instructions is present — describing/tagging a blank form
    /// would just make the model hallucinate.
    static func hasEnoughContext(title: String, ingredients: [String], instructions: String) -> Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasIngredients = ingredients.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let hasInstructions = !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasTitle && (hasIngredients || hasInstructions)
    }

    static let descriptionInstructions = """
    You write short, appetizing recipe descriptions for a home-cooking app. \
    Given a recipe's title, ingredients, and steps, write ONE or TWO sentences \
    that describe the dish invitingly. Do not restate the full ingredient list \
    or the steps, do not invent details that aren't implied by the recipe, and \
    do not use marketing hyperbole. Return only the description text.
    """

    static func descriptionPrompt(title: String, ingredients: [String], instructions: String) -> String {
        var parts = ["Title: \(title)"]
        let ing = ingredients.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !ing.isEmpty { parts.append("Ingredients:\n" + ing.joined(separator: "\n")) }
        let steps = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !steps.isEmpty { parts.append("Steps:\n\(steps)") }
        return "Write a description for this recipe:\n\n" + parts.joined(separator: "\n\n")
    }

    static let tagInstructions = """
    You suggest a few short tags for a recipe in a home-cooking app — things \
    like the course (Breakfast, Dinner, Dessert), cuisine (Italian, Mexican), \
    or a key trait (Vegetarian, Quick). Prefer tags from the list of existing \
    tags the user already uses when they fit, so tags don't fragment. Only \
    suggest tags clearly supported by the recipe.
    """

    static func tagPrompt(title: String, ingredients: [String], instructions: String, existingTags: [String]) -> String {
        var prompt = descriptionPrompt(title: title, ingredients: ingredients, instructions: instructions)
        let existing = existingTags.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !existing.isEmpty {
            prompt += "\n\nExisting tags to prefer when they fit: " + existing.joined(separator: ", ")
        }
        return prompt
    }

    /// Trim, drop empties, and de-duplicate case-insensitively while preserving
    /// order and the model's original casing for the first occurrence.
    static func cleanTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted { result.append(trimmed) }
        }
        return result
    }
}

enum RecipeWritingError: LocalizedError {
    case notEnoughContext

    var errorDescription: String? {
        switch self {
        case .notEnoughContext:
            return "Add a title and a few ingredients or steps first, then Apple Intelligence can help."
        }
    }
}
