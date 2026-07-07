import SwiftUI

/// Sheet presented from `RecipeDetailView` to schedule the current recipe onto
/// the meal calendar: a meal-type segmented control, a day picker over the next
/// couple of weeks, and a prominent "Add to Calendar" action. Mirrors the
/// Calendar tab's Quick Planner controls (same meal types, same glass styling)
/// so the two entry points feel like one feature. Dismisses itself once the
/// row is written.
struct AddToCalendarSheet: View {
    @State private var viewModel: AddToCalendarViewModel
    @Environment(\.dismiss) private var dismiss

    init(recipeId: Int64, recipeTitle: String) {
        _viewModel = State(initialValue: AddToCalendarViewModel(recipeId: recipeId, recipeTitle: recipeTitle))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            Form {
                Section {
                    Text(viewModel.recipeTitle)
                        .font(.headline)
                        .foregroundStyle(Color.brandPrimary)
                }

                Section("Meal") {
                    Picker("Meal", selection: $viewModel.selectedMealType) {
                        ForEach(AddToCalendarViewModel.mealTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Day") {
                    Picker("Day", selection: $viewModel.selectedDate) {
                        ForEach(viewModel.days) { day in
                            Text(day.label).tag(day.date)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Add to Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        Task {
                            await viewModel.add()
                            if viewModel.didAdd { dismiss() }
                        }
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .alert(
                "Couldn't Add to Calendar",
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
}
