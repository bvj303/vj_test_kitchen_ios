import SwiftUI

struct RecipeFormView: View {
    @State private var viewModel: RecipeFormViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false

    /// Called after a successful save, in addition to `dismiss()`. `dismiss()`
    /// is a no-op when this view is a tab's root rather than something
    /// presented — the Add-Recipe tab uses this hook to reset to a blank
    /// form instead, since there's nothing to dismiss back to.
    var onSaved: (() -> Void)?

    /// Called after a successful delete, before `dismiss()`. The detail screen
    /// uses this to distinguish "sheet dismissed after delete" (pop back to the
    /// list — the recipe is gone) from "dismissed after save/cancel" (reload the
    /// detail). Without it the detail would reload a now-deleted recipe and its
    /// `.single()` fetch would fail with "Cannot coerce the result to a single
    /// JSON object."
    var onDeleted: (() -> Void)?

    /// False when hosted as a tab's root, where "Cancel" doesn't make sense
    /// (there's nothing to cancel back to) and the leading toolbar slot is
    /// used for the account button instead.
    var showsCancelButton = true

    init(mode: RecipeFormViewModel.Mode, showsCancelButton: Bool = true, onSaved: (() -> Void)? = nil, onDeleted: (() -> Void)? = nil) {
        _viewModel = State(initialValue: RecipeFormViewModel(mode: mode))
        self.showsCancelButton = showsCancelButton
        self.onSaved = onSaved
        self.onDeleted = onDeleted
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section("Basics") {
                TextField("Title", text: $viewModel.title)
                TextField("Description", text: $viewModel.description, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section("Instructions") {
                TextField("Step-by-step instructions", text: $viewModel.instructions, axis: .vertical)
                    .lineLimit(4...10)
            }

            Section("Quick Stats") {
                HStack {
                    TextField("Prep time (min)", text: $viewModel.prepTimeText)
                        .keyboardType(.numberPad)
                    Divider()
                    TextField("Servings", text: $viewModel.servingsText)
                        .keyboardType(.numberPad)
                }
            }

            Section("Ingredients") {
                ForEach($viewModel.ingredientRows) { $row in
                    HStack {
                        TextField("Qty", text: $row.amount)
                            .keyboardType(.decimalPad)
                            .frame(width: 50)
                        TextField("Unit", text: $row.unit)
                            .frame(width: 60)
                        TextField("Ingredient name", text: $row.name)
                        Button {
                            viewModel.removeIngredientRow(row)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    viewModel.addIngredientRow()
                } label: {
                    Label("Add Ingredient", systemImage: "plus.circle")
                }
                .foregroundStyle(Color.brandSage)
            }

            Section("Categories") {
                TextField("Italian, Spicy, ...", text: $viewModel.tagsText)
            }

            if viewModel.isEditing {
                Section {
                    Button("Delete Recipe", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }
            }
        }
        .navigationTitle(viewModel.isEditing ? "Edit Recipe" : "New Recipe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCancelButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await viewModel.save()
                        if viewModel.didSave {
                            onSaved?()
                            dismiss()
                        }
                    }
                }
                .disabled(!viewModel.canSave || viewModel.isSaving)
            }
        }
        .task { await viewModel.loadIfNeeded() }
        .confirmationDialog(
            "Delete this recipe?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    if await viewModel.delete() {
                        onDeleted?()
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
