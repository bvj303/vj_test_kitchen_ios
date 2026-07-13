import Foundation
import FoundationModels
import Vision

/// The structured recipe the on-device model extracts from a photo's text.
/// `@Generable` so `LanguageModelSession.respond(generating:)` fills it in
/// directly — no brittle JSON-string parsing. Integer fields use 0 as "unknown"
/// (the `@Generable` schema is happier with a concrete `Int` than an optional).
@Generable
struct ScannedRecipe: Equatable, Sendable {
    @Guide(description: "The recipe's title or dish name.")
    var title: String
    @Guide(description: "A one or two sentence description of the dish. Empty string if there isn't one.")
    var summary: String
    @Guide(description: "Each ingredient as its own line, exactly as written, e.g. '2 cups all-purpose flour'.")
    var ingredients: [String]
    @Guide(description: "The cooking steps, as a single block of text with steps separated by newlines.")
    var instructions: String
    @Guide(description: "Total time in minutes (prep plus cook). Use 0 if the photo doesn't say.")
    var totalMinutes: Int
    @Guide(description: "How many servings the recipe makes. Use 0 if the photo doesn't say.")
    var servings: Int

    // Explicit memberwise init: the `@Generable` macro adds its own
    // `init(_:)`, which suppresses the synthesized memberwise initializer —
    // this keeps `ScannedRecipe(...)` constructible in tests and `apply(_:)`.
    init(title: String, summary: String, ingredients: [String], instructions: String, totalMinutes: Int, servings: Int) {
        self.title = title
        self.summary = summary
        self.ingredients = ingredients
        self.instructions = instructions
        self.totalMinutes = totalMinutes
        self.servings = servings
    }
}

/// Turns a photo of a recipe (a cookbook page, a recipe card, a screenshot)
/// into a structured `ScannedRecipe` the recipe form can prefill — entirely
/// on-device:
///
/// 1. **Vision** (`RecognizeTextRequest`) OCRs the image bytes to raw text.
/// 2. **Apple Intelligence** (`SystemLanguageModel`) structures that text into
///    title / ingredients / steps / times via `@Generable`.
///
/// Both steps are on-device and cross-platform (Vision + FoundationModels ship
/// on iOS and macOS 26+). The Vision call is injectable (`recognizeText`) so the
/// pieces around it stay unit-testable without a real image or model.
struct RecipePhotoImportService {
    /// OCR step: image bytes → recognized text. Defaults to Vision; overridable
    /// in tests.
    var recognizeText: @Sendable (Data) async throws -> String = { try await RecipePhotoImportService.visionRecognizeText($0) }

    /// Non-`nil` when on-device extraction can't run here — reuses the
    /// concierge's availability copy so the two features speak with one voice.
    var unavailableReason: String? {
        AppleIntelligenceAIService.unavailableReason(for: SystemLanguageModel.default.availability)
    }

    func importRecipe(from imageData: Data) async throws -> ScannedRecipe {
        if let reason = unavailableReason {
            throw AppleIntelligenceUnavailableError(message: reason)
        }
        let text = try await recognizeText(imageData)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecipeScanError.noTextFound
        }
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: Self.prompt(for: text),
            generating: ScannedRecipe.self
        )
        return response.content
    }

    // MARK: - Vision OCR

    /// Default OCR implementation: runs an accurate, language-corrected text
    /// recognition pass over the image bytes and joins the recognized lines.
    static func visionRecognizeText(_ imageData: Data) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: imageData)
        return observations
            .map(\.transcript)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    // MARK: - Pure helpers (unit-tested)

    static let instructions = """
    You extract a single recipe from raw text that was read off a photo of a \
    cookbook page, recipe card, or screenshot. The text may have OCR noise, odd \
    line breaks, or page furniture (headers, page numbers) — ignore anything \
    that isn't part of the recipe. Only use information present in the text; \
    never invent ingredients, steps, times, or servings. If a field isn't in \
    the text, leave it empty (or 0 for the numeric fields).
    """

    static func prompt(for ocrText: String) -> String {
        """
        Extract the recipe from this text:

        \(ocrText)
        """
    }
}

enum RecipeScanError: LocalizedError {
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .noTextFound:
            return "Couldn't find any text in that photo. Try a clearer, well-lit picture of the recipe."
        }
    }
}
