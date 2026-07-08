import SwiftUI
import UIKit

/// Full-screen, at-the-stove cooking view: large checkable ingredients and
/// step-by-step instructions, with the screen kept awake so it doesn't sleep
/// mid-recipe. Presented from `RecipeDetailView`'s "Start Cooking" button and
/// honors the current serving `scale` so quantities match what's being cooked.
///
/// State is intentionally local and ephemeral — checking off an ingredient or a
/// step is a within-session cooking aid, not something to persist.
struct CookModeView: View {
    let detail: RecipeDetail
    var scale: Double = 1

    @Environment(\.dismiss) private var dismiss
    @State private var checkedIngredients: Set<Int64> = []
    @State private var checkedSteps: Set<Int> = []

    /// Instruction steps (numbered) and section headers, derived once.
    private var rows: [Row] {
        guard let instructions = detail.instructions, !instructions.isEmpty else { return [] }
        var result: [Row] = []
        var number = 0
        for element in RecipeInstructions.elements(from: instructions) {
            switch element {
            case let .header(title):
                result.append(.header(title))
            case let .step(text):
                number += 1
                result.append(.step(number: number, text: text))
            }
        }
        return result
    }

    private var stepCount: Int {
        rows.reduce(0) { if case .step = $1 { return $0 + 1 } else { return $0 } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !detail.ingredients.isEmpty {
                        ingredientsSection
                    }
                    if !rows.isEmpty {
                        stepsSection
                    }
                }
                .padding()
            }
            .navigationTitle(detail.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.headline)
                }
            }
        }
        // Keep the screen awake while cooking; restore on exit.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: - Ingredients

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Ingredients", systemImage: "checklist")
            ForEach(detail.ingredients) { ingredient in
                let amount = IngredientAmount(amount: ingredient.amount, unit: ingredient.unit, name: ingredient.name)
                    .scaled(by: scale)
                let isChecked = checkedIngredients.contains(ingredient.id)
                Button {
                    toggle(&checkedIngredients, ingredient.id)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        checkCircle(isChecked)
                        Text(amount.formatted)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(isChecked ? .secondary : Color.brandPrimary)
                            .frame(minWidth: 80, alignment: .leading)
                        Text(amount.name)
                            .font(.title3)
                            .strikethrough(isChecked)
                            .foregroundStyle(isChecked ? .secondary : .primary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }

    // MARK: - Steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Steps", systemImage: "list.number")
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                switch row {
                case let .header(title):
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color.brandPrimary)
                        .padding(.top, 4)
                case let .step(number, text):
                    let isChecked = checkedSteps.contains(number)
                    Button {
                        toggle(&checkedSteps, number)
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(number)")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(isChecked ? .white : Color.brandPrimary)
                                .frame(width: 34, height: 34)
                                .background(
                                    Circle().fill(isChecked ? AnyShapeStyle(Color.brandPrimary) : AnyShapeStyle(Color.brandPrimary.opacity(0.14)))
                                )
                            Text(text)
                                .font(.title3)
                                .strikethrough(isChecked)
                                .foregroundStyle(isChecked ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Bits

    private func checkCircle(_ isChecked: Bool) -> some View {
        Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .foregroundStyle(isChecked ? Color.brandSage : Color.secondary)
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.title2.bold())
            .foregroundStyle(Color.brandPrimary)
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ value: T) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    private enum Row {
        case header(String)
        case step(number: Int, text: String)
    }
}
