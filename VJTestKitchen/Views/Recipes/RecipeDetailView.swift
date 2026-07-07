import SwiftUI

struct RecipeDetailView: View {
    @State private var viewModel: RecipeDetailViewModel
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var showingEditSheet = false
    @State private var showingAddToCalendar = false
    let recipeId: Int64

    init(recipeId: Int64) {
        self.recipeId = recipeId
        _viewModel = State(initialValue: RecipeDetailViewModel(recipeId: recipeId))
    }

    private var isOwnedByCurrentUser: Bool {
        guard let detail = viewModel.detail, case .signedIn(let userId) = authViewModel.state else { return false }
        return detail.userId == userId
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let detail = viewModel.detail {
                    header(detail)
                    statsRow(detail)
                    if !detail.ingredients.isEmpty {
                        ingredientsSection(detail)
                    }
                    if let instructions = detail.instructions, !instructions.isEmpty {
                        instructionsSection(instructions)
                    }
                    ratingSection
                } else if viewModel.isLoading {
                    ProgressView().padding(.top, 80)
                }
            }
            .padding()
        }
        .navigationTitle(viewModel.detail?.title ?? "Recipe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Any signed-in user can schedule any recipe onto their own
            // (RLS-scoped) calendar — this isn't gated on ownership the way
            // Edit is. Shown once the recipe has loaded, since the sheet needs
            // its title.
            if viewModel.detail != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddToCalendar = true
                    } label: {
                        Label("Add to Calendar", systemImage: "calendar.badge.plus")
                    }
                }
            }
            if isOwnedByCurrentUser {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showingEditSheet = true }
                }
            }
        }
        .sheet(isPresented: $showingEditSheet, onDismiss: { Task { await viewModel.load() } }) {
            NavigationStack {
                RecipeFormView(mode: .edit(recipeId: recipeId))
            }
        }
        .sheet(isPresented: $showingAddToCalendar) {
            if let detail = viewModel.detail {
                AddToCalendarSheet(recipeId: recipeId, recipeTitle: detail.title)
                    .presentationDetents([.medium, .large])
            }
        }
        .task { await viewModel.load() }
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

    @ViewBuilder
    private func heroImage(_ detail: RecipeDetail) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        ZStack {
            shape
                .fill(.thinMaterial)
                .glassEffect(.regular.tint(Color.brandPrimary.opacity(0.22)), in: shape)
            if let imageUrl = detail.imageUrl, let url = URL(string: imageUrl), !imageUrl.isEmpty {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        heroPlaceholder
                    case .empty:
                        ProgressView()
                    @unknown default:
                        heroPlaceholder
                    }
                }
            } else {
                heroPlaceholder
            }
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .clipShape(shape)
    }

    private var heroPlaceholder: some View {
        Image(systemName: "fork.knife.circle")
            .font(.system(size: 48))
            .foregroundStyle(Color.brandPrimary)
    }

    @ViewBuilder
    private func header(_ detail: RecipeDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heroImage(detail)

            Text(detail.title)
                .font(.largeTitle.bold())

            if !detail.tagNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(detail.tagNames, id: \.self) { tag in
                            Text(tag)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.brandSage)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .glassEffect(.regular.tint(Color.brandSage.opacity(0.28)), in: Capsule())
                        }
                    }
                }
            }

            if let description = detail.description, !description.isEmpty {
                Text(description)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func statsRow(_ detail: RecipeDetail) -> some View {
        HStack(spacing: 16) {
            if let prepTime = detail.prepTime {
                statTile(icon: "clock", value: "\(prepTime) min", label: "Prep Time")
            }
            if let servings = detail.servings {
                statTile(icon: "person.2", value: "\(servings)", label: "Servings")
            }
        }
    }

    private func statTile(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(Color.brandPrimary)
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func ingredientsSection(_ detail: RecipeDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Ingredients").font(.title3.bold()).foregroundStyle(Color.brandPrimary)
                Spacer()
                Button {
                    Task { await viewModel.addAllIngredientsToGroceryList() }
                } label: {
                    Label(viewModel.didAddAllToGroceryList ? "Added" : "Add All",
                          systemImage: viewModel.didAddAllToGroceryList ? "checkmark.circle.fill" : "cart.badge.plus")
                        .font(.subheadline)
                }
                .foregroundStyle(Color.brandSage)
                .disabled(viewModel.didAddAllToGroceryList)
            }
            ForEach(detail.ingredients) { ingredient in
                HStack(alignment: .firstTextBaseline) {
                    Text(formattedAmount(ingredient))
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .leading)
                    Text(ingredient.name)
                    Spacer()
                    Button {
                        Task { await viewModel.addIngredientToGroceryList(ingredient) }
                    } label: {
                        Image(systemName: viewModel.addedIngredientIds.contains(ingredient.id) ? "checkmark.circle.fill" : "plus.circle")
                            .foregroundStyle(Color.brandSage)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.addedIngredientIds.contains(ingredient.id))
                    .accessibilityLabel("Add \(ingredient.name) to Grocery List")
                }
                .font(.subheadline)
            }
        }
    }

    private func formattedAmount(_ ingredient: Ingredient) -> String {
        let amountText = ingredient.amount == ingredient.amount.rounded()
            ? String(Int(ingredient.amount))
            : String(format: "%.2f", ingredient.amount)
        return ingredient.unit.isEmpty ? amountText : "\(amountText) \(ingredient.unit)"
    }

    @ViewBuilder
    private func instructionsSection(_ instructions: String) -> some View {
        let steps = RecipeInstructions.steps(from: instructions)
        VStack(alignment: .leading, spacing: 12) {
            Text("Instructions").font(.title3.bold()).foregroundStyle(Color.brandPrimary)
            if steps.count > 1 {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.brandPrimary)
                            .frame(width: 28, height: 28)
                            .glassEffect(.regular.tint(Color.brandPrimary.opacity(0.22)), in: Circle())
                        Text(step)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                // Single unbroken paragraph — nothing to number.
                Text(steps.first ?? instructions)
            }
        }
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Rating & Notes").font(.title3.bold()).foregroundStyle(Color.brandPrimary)

            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= (viewModel.rating ?? 0) ? "star.fill" : "star")
                        .foregroundStyle(Color.brandSaffron)
                        .onTapGesture { viewModel.rating = star }
                }
            }
            .font(.title3)

            TextField("Notes (e.g. substitutions, tips)", text: $viewModel.notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)

            Button("Save") {
                Task { await viewModel.saveRating() }
            }
            .buttonStyle(.glassProminent)
        }
        .padding()
        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
