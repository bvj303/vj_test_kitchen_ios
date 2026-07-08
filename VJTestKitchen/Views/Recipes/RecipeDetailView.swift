import SwiftUI

struct RecipeDetailView: View {
    @State private var viewModel: RecipeDetailViewModel
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditSheet = false
    @State private var showingAddToCalendar = false
    @State private var showingCookMode = false
    /// Serving multiplier applied to ingredient quantities and the servings
    /// tile. 1 = original.
    @State private var scale: Double = 1
    @State private var wasDeleted = false
    let recipeId: Int64

    /// Called when the recipe is deleted, so a coordinating parent can drop it
    /// from its state — clearing the split-view selection and reloading the list
    /// so the now-deleted row can't be tapped into a broken detail. Independent
    /// of `dismiss()`, which pops this view when it was pushed (iPhone / Home).
    var onDeleted: (() -> Void)?

    init(recipeId: Int64, onDeleted: (() -> Void)? = nil) {
        self.recipeId = recipeId
        self.onDeleted = onDeleted
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
                    if hasCookableContent(detail) {
                        cookButton(detail)
                    }
                    if !detail.ingredients.isEmpty {
                        ingredientsSection(detail)
                    }
                    if let instructions = detail.instructions, !instructions.isEmpty {
                        instructionsSection(instructions)
                    }
                    reviewsSection
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
                    scaleMenu
                }
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
        .sheet(isPresented: $showingEditSheet, onDismiss: {
            // If the recipe was deleted from the edit sheet, it's gone — tell the
            // parent to drop it and pop back, rather than reloading a row that no
            // longer exists (whose `.single()` fetch would fail). Otherwise
            // refresh the detail to reflect any saved edits.
            if wasDeleted {
                onDeleted?()
                dismiss()
            } else {
                Task { await viewModel.load() }
            }
        }) {
            NavigationStack {
                RecipeFormView(mode: .edit(recipeId: recipeId), onDeleted: { wasDeleted = true })
            }
        }
        .sheet(isPresented: $showingAddToCalendar) {
            if let detail = viewModel.detail {
                AddToCalendarSheet(recipeId: recipeId, recipeTitle: detail.title)
                    .presentationDetents([.medium, .large])
            }
        }
        .fullScreenCover(isPresented: $showingCookMode) {
            if let detail = viewModel.detail {
                CookModeView(detail: detail, scale: scale)
            }
        }
        .task {
            // Give the community list the signed-in user so it can omit the
            // user's own review (shown in the personal editor above it).
            if case .signedIn(let userId) = authViewModel.state {
                viewModel.currentUserId = userId
            }
            await viewModel.load()
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

    /// Short "×N" label for the current scale, e.g. "½×", "1×", "2×".
    private var scaleLabel: String {
        "\(IngredientAmount.format(scale))×"
    }

    /// Top-right menu to halve/double/triple the recipe. Scaling multiplies
    /// ingredient quantities and the servings tile live.
    private var scaleMenu: some View {
        Menu {
            Picker("Scale Recipe", selection: $scale) {
                Text("Half (½×)").tag(0.5)
                Text("Original (1×)").tag(1.0)
                Text("Double (2×)").tag(2.0)
                Text("Triple (3×)").tag(3.0)
            }
        } label: {
            if scale == 1 {
                Label("Scale Recipe", systemImage: "slider.horizontal.3")
            } else {
                // Show the active multiplier so it's clear the recipe is scaled.
                Text(scaleLabel)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.brandPrimary)
            }
        }
        .accessibilityLabel("Scale Recipe")
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

            // The recipe title lives in the (inline) navigation bar — no second
            // large title here, which keeps the header from feeling cramped.
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
                statTile(icon: "clock", value: PrepTimeFormat.string(minutes: prepTime), label: "Prep Time")
            }
            if let servings = detail.servings {
                statTile(
                    icon: "person.2",
                    value: IngredientAmount.format(Double(servings) * scale),
                    label: scale == 1 ? "Servings" : "Servings (\(scaleLabel))"
                )
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
                    Task { await viewModel.addAllIngredientsToGroceryList(scale: scale) }
                } label: {
                    Label(viewModel.didAddAllToGroceryList ? "Added" : "Add All",
                          systemImage: viewModel.didAddAllToGroceryList ? "checkmark.circle.fill" : "cart.badge.plus")
                        .font(.subheadline)
                }
                .foregroundStyle(Color.brandSage)
                .disabled(viewModel.didAddAllToGroceryList)
            }
            ForEach(detail.ingredients) { ingredient in
                let amount = IngredientAmount(amount: ingredient.amount, unit: ingredient.unit, name: ingredient.name)
                    .scaled(by: scale)
                HStack(alignment: .firstTextBaseline) {
                    Text(amount.formatted)
                        .foregroundStyle(.secondary)
                        .frame(width: 96, alignment: .leading)
                    Text(amount.name)
                    Spacer()
                    Button {
                        Task { await viewModel.addIngredientToGroceryList(ingredient, scale: scale) }
                    } label: {
                        Image(systemName: viewModel.addedIngredientIds.contains(ingredient.id) ? "checkmark.circle.fill" : "plus.circle")
                            .foregroundStyle(Color.brandSage)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.addedIngredientIds.contains(ingredient.id))
                    .accessibilityLabel("Add \(amount.name) to Grocery List")
                }
                .font(.subheadline)
            }
        }
    }

    /// A single rendered instruction row: either a component subheading (from an
    /// ATK `**FOR THE X:**` marker) or a numbered step. Step numbers restart at 1
    /// after each header, so a multi-component recipe reads as distinct sections.
    private enum InstructionRow {
        case header(String)
        case step(number: Int, text: String)
    }

    private func instructionRows(_ instructions: String) -> [(id: Int, row: InstructionRow)] {
        var rows: [(id: Int, row: InstructionRow)] = []
        var stepNumber = 0
        for element in RecipeInstructions.elements(from: instructions) {
            switch element {
            case let .header(title):
                stepNumber = 0
                rows.append((rows.count, .header(title)))
            case let .step(text):
                stepNumber += 1
                rows.append((rows.count, .step(number: stepNumber, text: text)))
            }
        }
        return rows
    }

    @ViewBuilder
    private func instructionsSection(_ instructions: String) -> some View {
        let rows = instructionRows(instructions)
        let stepCount = rows.filter { if case .step = $0.row { return true } else { return false } }.count
        VStack(alignment: .leading, spacing: 12) {
            Text("Instructions").font(.title3.bold()).foregroundStyle(Color.brandPrimary)
            if stepCount > 1 || rows.contains(where: { if case .header = $0.row { return true } else { return false } }) {
                ForEach(rows, id: \.id) { entry in
                    switch entry.row {
                    case let .header(title):
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(Color.brandPrimary)
                            .padding(.top, 4)
                    case let .step(number, text):
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(number)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.brandPrimary)
                                .frame(width: 28, height: 28)
                                .glassEffect(.regular.tint(Color.brandPrimary.opacity(0.22)), in: Circle())
                            Text(text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } else {
                // Single unbroken paragraph — nothing to number.
                Text(rows.first.flatMap { if case let .step(_, text) = $0.row { return text } else { return nil } } ?? instructions)
            }
        }
    }

    /// One unified "Ratings & Reviews" card: the current user's editable rating
    /// and notes at the top, then — directly below, in the same card — the rest
    /// of the household's comments, so your review and everyone else's read as a
    /// single streamlined thread rather than two separate boxes.
    private var reviewsSection: some View {
        let summary = viewModel.communitySummary
        let others = viewModel.otherReviews
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Ratings & Reviews").font(.title3.bold()).foregroundStyle(Color.brandPrimary)
                Spacer()
                favoriteButton
            }

            // Your own review.
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= (viewModel.rating ?? 0) ? "star.fill" : "star")
                            .foregroundStyle(Color.brandSaffron)
                            .onTapGesture { viewModel.rating = star }
                    }
                }
                .font(.title3)

                // Notes are visible to other household members (they show as the
                // comments below), so the field says so.
                TextField("Notes & tips — visible to your household", text: $viewModel.notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                Button("Save") {
                    Task { await viewModel.saveRating() }
                }
                .buttonStyle(.glassProminent)
            }

            // The rest of the household, streamlined right beneath your review.
            if summary.hasRatings || !others.isEmpty {
                Divider()

                HStack(alignment: .firstTextBaseline) {
                    Text("From your household")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if summary.hasRatings {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill").font(.caption).foregroundStyle(Color.brandSaffron)
                            Text(summary.averageText).font(.subheadline.weight(.semibold))
                            Text("· \(summary.count) \(summary.count == 1 ? "rating" : "ratings")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if others.isEmpty {
                    Text("No one else has weighed in yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(others) { review in
                            reviewRow(review)
                        }
                    }
                }
            }
        }
        .padding()
        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Heart toggle beside the ratings — the "favorites" affordance.
    private var favoriteButton: some View {
        Button {
            Task { await viewModel.toggleFavorite() }
        } label: {
            Image(systemName: viewModel.isFavorite ? "heart.fill" : "heart")
                .font(.title3)
                .foregroundStyle(viewModel.isFavorite ? Color.brandPrimary : Color.secondary)
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.isFavorite ? "Remove from Favorites" : "Add to Favorites")
    }

    /// One household member's comment: avatar, name + inline stars, then their note.
    private func reviewRow(_ review: RecipeReview) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(avatarUrl: review.profile?.avatarUrl, name: review.reviewerName, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(review.reviewerName)
                        .font(.subheadline.weight(.semibold))
                    if let rating = review.rating {
                        HStack(spacing: 1) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= rating ? "star.fill" : "star")
                                    .font(.caption2)
                                    .foregroundStyle(Color.brandSaffron)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                if review.hasComment, let notes = review.notes {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Cook Mode

    private func hasCookableContent(_ detail: RecipeDetail) -> Bool {
        !detail.ingredients.isEmpty || (detail.instructions?.isEmpty == false)
    }

    private func cookButton(_ detail: RecipeDetail) -> some View {
        Button {
            showingCookMode = true
        } label: {
            Label("Start Cooking", systemImage: "flame.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(Color.brandPrimary)
    }
}
