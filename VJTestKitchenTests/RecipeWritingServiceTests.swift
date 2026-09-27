import Foundation
import Testing
@testable import VJTestKitchen

struct RecipeWritingServiceTests {

    // MARK: - hasEnoughContext

    @Test func needsTitlePlusIngredientsOrSteps() {
        // Title alone isn't enough.
        #expect(RecipeWritingService.hasEnoughContext(title: "Carbonara", ingredients: [], instructions: "") == false)
        // Title + an ingredient is enough.
        #expect(RecipeWritingService.hasEnoughContext(title: "Carbonara", ingredients: ["eggs"], instructions: "") == true)
        // Title + steps is enough.
        #expect(RecipeWritingService.hasEnoughContext(title: "Carbonara", ingredients: [], instructions: "Boil pasta") == true)
        // No title is never enough.
        #expect(RecipeWritingService.hasEnoughContext(title: "  ", ingredients: ["eggs"], instructions: "Boil") == false)
    }

    @Test func ignoresWhitespaceOnlyIngredients() {
        #expect(RecipeWritingService.hasEnoughContext(title: "Soup", ingredients: ["   ", "\n"], instructions: "") == false)
    }

    // MARK: - Prompt building

    @Test func descriptionPromptIncludesFilledFieldsOnly() {
        let prompt = RecipeWritingService.descriptionPrompt(title: "Tacos", ingredients: ["beef", "  "], instructions: "")
        #expect(prompt.contains("Title: Tacos"))
        #expect(prompt.contains("beef"))
        #expect(!prompt.contains("Steps:")) // no instructions supplied
    }

    @Test func tagPromptAppendsExistingVocabulary() {
        let prompt = RecipeWritingService.tagPrompt(
            title: "Tacos", ingredients: ["beef"], instructions: "Cook", existingTags: ["Dinner", "Mexican"]
        )
        #expect(prompt.contains("Existing tags to prefer"))
        #expect(prompt.contains("Dinner"))
        #expect(prompt.contains("Mexican"))
    }

    @Test func tagPromptOmitsVocabularyLineWhenEmpty() {
        let prompt = RecipeWritingService.tagPrompt(title: "Tacos", ingredients: ["beef"], instructions: "Cook", existingTags: [])
        #expect(!prompt.contains("Existing tags"))
    }

    // MARK: - cleanTags

    @Test func cleanTagsTrimsDropsEmptyAndDedupes() {
        let cleaned = RecipeWritingService.cleanTags([" Dinner ", "dinner", "", "Mexican", "  "])
        #expect(cleaned == ["Dinner", "Mexican"]) // case-insensitive dedupe, first casing kept
    }

    // MARK: - Injectable generation seam

    /// A service that behaves as if Apple Intelligence is available (the model
    /// is never available on the test host, so we inject past the guard).
    private func availableService() -> RecipeWritingService {
        var service = RecipeWritingService()
        service.checkAvailability = { nil }
        return service
    }

    @Test func generateDescriptionUsesInjectedGenerator() async throws {
        var service = availableService()
        service.generateText = { _, _ in "  A cozy classic.  " }
        let text = try await service.generateDescription(title: "Stew", ingredients: ["beef"], instructions: "")
        #expect(text == "A cozy classic.") // trimmed
    }

    @Test func suggestTagsCleansInjectedResults() async throws {
        var service = availableService()
        service.generateTags = { _, _ in [" Dinner ", "dinner", "Italian"] }
        let tags = try await service.suggestTags(title: "Pasta", ingredients: ["noodles"], instructions: "", existingTags: [])
        #expect(tags == ["Dinner", "Italian"])
    }

    @Test func generateDescriptionThrowsWithoutContextWhenAvailable() async {
        let service = availableService()
        await #expect(throws: RecipeWritingError.self) {
            _ = try await service.generateDescription(title: "", ingredients: [], instructions: "")
        }
    }

    @Test func generateDescriptionThrowsWhenUnavailable() async {
        var service = RecipeWritingService()
        service.checkAvailability = { "Turn on Apple Intelligence." }
        await #expect(throws: AppleIntelligenceUnavailableError.self) {
            _ = try await service.generateDescription(title: "Stew", ingredients: ["beef"], instructions: "")
        }
    }
}
