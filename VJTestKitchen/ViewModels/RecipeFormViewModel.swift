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

    /// Recipe-photo scan (Apple Intelligence) state.
    private(set) var isScanningPhoto = false
    var scanErrorMessage: String?

    private let recipeService: RecipeServicing
    private let saveService: RecipeSaving
    private let photoImportService: RecipePhotoImportService

    init(
        mode: Mode,
        recipeService: RecipeServicing = RecipeService(),
        saveService: RecipeSaving = RecipeSaveService(),
        photoImportService: RecipePhotoImportService = RecipePhotoImportService()
    ) {
        self.mode = mode
        self.recipeService = recipeService
        self.saveService = saveService
        self.photoImportService = photoImportService
    }

    /// Whether the "Scan from Photo" affordance should be offered — false on
    /// devices without on-device Apple Intelligence, so the button doesn't lead
    /// to a dead end.
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

    var isEditing: Bool {
        if case .edit = mode { true } else { false }
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
