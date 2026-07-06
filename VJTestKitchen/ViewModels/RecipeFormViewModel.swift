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

    private let recipeService: RecipeServicing
    private let ingredientService: IngredientServicing
    private let tagService: TagServicing

    init(
        mode: Mode,
        recipeService: RecipeServicing = RecipeService(),
        ingredientService: IngredientServicing = IngredientService(),
        tagService: TagServicing = TagService()
    ) {
        self.mode = mode
        self.recipeService = recipeService
        self.ingredientService = ingredientService
        self.tagService = tagService
    }

    var isEditing: Bool {
        if case .edit = mode { true } else { false }
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            prepTime: Int(prepTimeText),
            servings: Int(servingsText)
        )

        do {
            let recipeId: Int64
            switch mode {
            case .create:
                recipeId = try await recipeService.create(draft).id
            case .edit(let id):
                try await recipeService.update(id: id, with: draft)
                recipeId = id
            }

            let ingredients: [IngredientInsert] = ingredientRows.compactMap { row in
                let trimmedName = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else { return nil }
                return IngredientInsert(recipeId: recipeId, name: trimmedName, amount: IngredientAmountParser.parse(row.amount) ?? 0, unit: row.unit)
            }
            try await ingredientService.replaceAll(recipeId: recipeId, with: ingredients)

            let tagNames = tagsText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            try await tagService.replaceAll(recipeId: recipeId, withTagNames: tagNames)

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

    private static func formatAmount(_ amount: Double) -> String {
        amount == amount.rounded() ? String(Int(amount)) : String(format: "%.2f", amount)
    }
}
