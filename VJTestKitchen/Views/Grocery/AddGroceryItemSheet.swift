import SwiftUI

struct AddGroceryItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amountText = ""
    @State private var unit = ""

    let onAdd: (_ name: String, _ amount: Double, _ unit: String) -> Void

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name", text: $name)
                }
                Section("Amount") {
                    HStack {
                        TextField("Qty", text: $amountText)
                            .keyboardType(.decimalPad)
                            .frame(width: 60)
                        Divider()
                        TextField("Unit (optional)", text: $unit)
                    }
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let amount = IngredientAmountParser.parse(amountText) ?? 0
                        onAdd(name, amount, unit)
                        dismiss()
                    }
                    .disabled(!canAdd)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
