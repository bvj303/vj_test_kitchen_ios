import Foundation
import Observation

@MainActor
@Observable
final class RecipeFormViewModel {
    enum Mode: Equatable {
        case create
        case edit(recipeId: Int64)
    }

    struct IngredientRow: Identifiable, Equatable {
        let id = UUID()
        var amount = ""
        var unit = ""
        var name = ""
    }

    let mode: Mode

    var title = ""
    var description = ""
    var instructions = ""
    var prepTimeText = ""
    var servingsText = ""
    var ingredientRows: [IngredientRow] = [IngredientRow()]
    var tagsText = ""

    private(set) var isLoading = false
    private(set) var isSaving = false
    var errorMessage: String?
    private(set) var didSave = false

    /// Recipe-import scan (Apple Intelligence) state. Covers both photo scans
    /// and PDF/document imports — they share the same OCR → structuring path.
    private(set) var isScanningPhoto = false
    var scanErrorMessage: String?

    /// On-device "recipe smarts" (Apple Intelligence) state.
    private(set) var isGeneratingDescription = false
    private(set) var isSuggestingTags = false

    private let recipeService: RecipeServicing
    private let saveService: RecipeSaving
    private let logger: AppLogger
    private let photoImportService: RecipePhotoImportService
    private let writingService: RecipeWritingService
    private let tagService: TagServicing

    init(
        mode: Mode,
        recipeService: RecipeServicing = RecipeService(),
        saveService: RecipeSaving = RecipeSaveService(),
        logger: AppLogger = .shared,
        photoImportService: RecipePhotoImportService = RecipePhotoImportService(),
        writingService: RecipeWritingService = RecipeWritingService(),
        tagService: TagServicing = TagService()
    ) {
        self.mode = mode
        self.recipeService = recipeService
        self.saveService = saveService
        self.logger = logger
        self.photoImportService = photoImportService
        self.writingService = writingService
        self.tagService = tagService
    }

    /// Whether the on-device "recipe smarts" (generate description, suggest
    /// tags) affordances should be shown — gated on Apple Intelligence being
    /// available, same as the scanner.
    var canUseWritingTools: Bool {
        writingService.unavailableReason == nil
    }

    /// The non-empty ingredient names currently entered, for feeding the
    /// on-device writing helpers.
    private var currentIngredientNames: [String] {
        ingredientRows
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Generates a description from the title/ingredients/steps and fills the
    /// Description field. Best-effort: surfaces failures in `errorMessage`.
    func generateDescription() async {
        errorMessage = nil
        isGeneratingDescription = true
        defer { isGeneratingDescription = false }
        do {
            let text = try await writingService.generateDescription(
                title: title,
                ingredients: currentIngredientNames,
                instructions: instructions
            )
            if !text.isEmpty { description = text }
        } catch {
            logger.warning("Recipe description generation failed", category: "ai", metadata: ["errorDescription": error.localizedDescription])
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Suggests tags (preferring the catalog's existing vocabulary) and merges
    /// them into the comma-separated Categories field without dropping tags the
    /// user already typed. Best-effort.
    func suggestTags() async {
        errorMessage = nil
        isSuggestingTags = true
        defer { isSuggestingTags = false }
        do {
            let existing = (try? await tagService.fetchAllNames()) ?? []
            let suggested = try await writingService.suggestTags(
                title: title,
                ingredients: currentIngredientNames,
                instructions: instructions,
                existingTags: existing
            )
            tagsText = Self.mergeTags(into: tagsText, adding: suggested)
        } catch {
            logger.warning("Recipe tag suggestion failed", category: "ai", metadata: ["errorDescription": error.localizedDescription])
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Merges suggested tags into an existing comma-separated field, appending
    /// only the ones not already present (case-insensitively). Pure/tested —
    /// `nonisolated` so tests can call it off the main actor.
    nonisolated static func mergeTags(into existingText: String, adding suggested: [String]) -> String {
        let existing = existingText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set(existing.map { $0.lowercased() })
        var result = existing
        for tag in suggested {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
        }
        return result.joined(separator: ", ")
    }

    var isEditing: Bool {
        if case .edit = mode { true } else { false }
    }

    /// Whether the "Scan from Photo" / "Import from PDF" affordances should be
    /// offered — false on devices without on-device Apple Intelligence, so the
    /// buttons don't lead to a dead end.
    var canScanPhoto: Bool {
        photoImportService.unavailableReason == nil
    }

    /// OCRs a picked recipe photo and prefills the form from it (on-device).
    /// Best-effort: a failure surfaces in `scanErrorMessage` and leaves the
    /// form untouched.
    func scanRecipe(from imageData: Data) async {
        scanErrorMessage = nil
        isScanningPhoto = true
        defer { isScanningPhoto = false }
        do {
            let scanned = try await photoImportService.importRecipe(from: imageData)
            apply(scanned)
        } catch {
            logger.warning("Recipe photo scan failed", category: "ai", metadata: ["errorDescription": error.localizedDescription])
            scanErrorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// OCRs a picked PDF (or other document) and prefills the form from it —
    /// same on-device path as `scanRecipe(from:)`, just fed by the document's
    /// rendered pages instead of a single photo.
    func importRecipe(fromDocument documentData: Data) async {
        scanErrorMessage = nil
        isScanningPhoto = true
        defer { isScanningPhoto = false }
        do {
            let scanned = try await photoImportService.importRecipe(fromDocument: documentData)
            apply(scanned)
        } catch {
            logger.warning("Recipe document import failed", category: "ai", metadata: ["errorDescription": error.localizedDescription])
            scanErrorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Prefills the form fields from an extracted recipe, only overwriting a
    /// field when the scan actually found something for it. Pure enough to test
    /// without OCR or the model.
    func apply(_ scanned: ScannedRecipe) {
        func filled(_ text: String) -> Bool {
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if filled(scanned.title) { title = scanned.title }
        if filled(scanned.summary) { description = scanned.summary }
        if filled(scanned.instructions) { instructions = scanned.instructions }
        if scanned.totalMinutes > 0 { prepTimeText = String(scanned.totalMinutes) }
        if scanned.servings > 0 { servingsText = String(scanned.servings) }

        let rows = scanned.ingredients
            .map { RecipeIngredientLineParser.parse($0) }
            .filter { !$0.name.isEmpty || !$0.amount.isEmpty }
            .map { IngredientRow(amount: $0.amount, unit: $0.unit, name: $0.name) }
        if !rows.isEmpty { ingredientRows = rows }
    }

    /// Whether the prep-time field reads as a duration ("45", "1 hr 30 min",
    /// …) — empty is fine (prep time is optional), garbage is not. The old
    /// form's `Int(prepTimeText)` silently saved nil for "45 min".
    var prepTimeIsValid: Bool {
        prepTimeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || PrepTimeFormat.parseMinutes(prepTimeText) != nil
    }

    /// Whether the servings field contains a readable count — empty is fine,
    /// and "4 people" reads as 4 (see `parseServings`).
    var servingsIsValid: Bool {
        servingsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || Self.parseServings(servingsText) != nil
    }

    /// Inline feedback for the Quick Stats section; nil when both fields parse.
    var quickStatsValidationMessage: String? {
        if !prepTimeIsValid {
            return "Prep time should be minutes, like \"45\" or \"1 hr 30 min\"."
        }
        if !servingsIsValid {
            return "Servings should be a number, like \"4\"."
        }
        return nil
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && prepTimeIsValid
            && servingsIsValid
    }

    func loadIfNeeded() async {
        guard case .edit(let recipeId) = mode else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let detail = try await recipeService.fetchDetail(id: recipeId)
            title = detail.title
            description = detail.description ?? ""
            instructions = detail.instructions ?? ""
            prepTimeText = detail.prepTime.map(String.init) ?? ""
            servingsText = detail.servings.map(String.init) ?? ""
            ingredientRows = detail.ingredients.isEmpty
                ? [IngredientRow()]
                : detail.ingredients.map {
                    IngredientRow(amount: Self.formatAmount($0.amount), unit: $0.unit, name: $0.name)
                }
            tagsText = detail.tagNames.joined(separator: ", ")
        } catch {
            logger.error("Recipe edit-form load failed", category: "recipes", error: error)
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    func addIngredientRow() {
        ingredientRows.append(IngredientRow())
    }

    func removeIngredientRow(_ row: IngredientRow) {
        ingredientRows.removeAll { $0.id == row.id }
    }

    func save() async {
        guard canSave else { return }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let draft = RecipeDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.isEmpty ? nil : description,
            instructions: instructions.isEmpty ? nil : instructions,
            imagePath: nil,
            prepTime: PrepTimeFormat.parseMinutes(prepTimeText),
            servings: Self.parseServings(servingsText)
        )

        let ingredients: [RecipeSaveIngredient] = ingredientRows.compactMap { row in
            let trimmedName = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return nil }
            return RecipeSaveIngredient(name: trimmedName, amount: IngredientAmountParser.parse(row.amount) ?? 0, unit: row.unit)
        }

        let tagNames = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let recipeId: Int64? = if case .edit(let id) = mode { id } else { nil }

        do {
            // One atomic RPC — recipe + ingredients + tags land together or not
            // at all, so a mid-save network drop can't leave a recipe without
            // its ingredients or duplicate it on retry (see RecipeSaveService).
            try await saveService.save(recipeId: recipeId, draft: draft, ingredients: ingredients, tagNames: tagNames)
            didSave = true
        } catch {
            logger.error("Recipe save failed", category: "recipes", error: error)
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Returns whether the delete succeeded, so the view can dismiss.
    @discardableResult
    func delete() async -> Bool {
        guard case .edit(let recipeId) = mode else { return false }
        errorMessage = nil
        do {
            try await recipeService.delete(id: recipeId)
            return true
        } catch {
            logger.error("Recipe delete failed", category: "recipes", error: error)
            errorMessage = ErrorPresenter.message(for: error)
            return false
        }
    }

    /// Reads a serving count out of user-typed text: "4" → 4, "4 people" → 4,
    /// "serves 6" → 6. Nil when there's no number to read.
    static func parseServings(_ text: String) -> Int? {
        guard let match = text.firstMatch(of: #/\d+/#) else { return nil }
        return Int(match.0)
    }

    private static func formatAmount(_ amount: Double) -> String {
        amount == amount.rounded() ? String(Int(amount)) : String(format: "%.2f", amount)
    }
}
