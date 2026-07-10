import SwiftUI

struct AddGroceryItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amountText = ""
    @State private var unit = ""
    @State private var category: GroceryCategory = .other
    /// Once the user touches the category picker, stop auto-overwriting their
    /// choice as they keep typing the name.
    @State private var userPickedCategory = false
    /// Auto-open the keyboard on the Name field the moment the sheet appears,
    /// so adding an item is a single tap on "+" rather than tap-then-tap-field.
    @FocusState private var nameFieldFocused: Bool

    let onAdd: (_ name: String, _ amount: Double, _ unit: String, _ category: GroceryCategory) -> Void

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name", text: $name)
                        .focused($nameFieldFocused)
                }
                Section("Amount") {
                    HStack {
                        TextField("Qty", text: $amountText)
                            .platformKeyboardType(.decimalPad)
                            .frame(width: 60)
                        Divider()
                        TextField("Unit (optional)", text: $unit)
                    }
                }
                Section("Category") {
                    Picker("Category", selection: Binding(
                        get: { category },
                        set: { category = $0; userPickedCategory = true }
                    )) {
                        ForEach(GroceryCategory.allCases) { category in
                            Label(category.displayName, systemImage: category.systemImage)
                                .tag(category)
                        }
                    }
                }
            }
            .navigationTitle("Add Item")
            .inlineNavigationTitle()
            .scrollDismissesKeyboard(.interactively)
            .dismissesKeyboardOnBackgroundTap()
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let amount = IngredientAmountParser.parse(amountText) ?? 0
                        onAdd(name, amount, unit, category)
                        dismiss()
                    }
                    .disabled(!canAdd)
                }
            }
            // Auto-suggest a category from the name until the user overrides it.
            .onChange(of: name) { _, newName in
                if !userPickedCategory {
                    category = GroceryCategorizer.categorize(newName)
                }
            }
            // Focus the Name field as the sheet presents so the keyboard is
            // already up — no second tap needed to start typing.
            .onAppear { nameFieldFocused = true }
        }
        .platformMediumLargeDetents()
        // macOS sheets size to their content; a bare Form collapses to a cramped
        // box, so pin a comfortable minimum. No-op on iOS (detents drive size).
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 460)
        #endif
    }
}
