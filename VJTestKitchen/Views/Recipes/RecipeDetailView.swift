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
    @Environment(SpatchPerchViewModel.self) private var spatchPerch
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
            // Cap the content to a readable column so a long recipe doesn't run
            // edge-to-edge across a wide iPad/Mac window.
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        // "Start Cooking" is pinned to the bottom so it stays reachable while
        // scrolling through ingredients and steps, instead of scrolling away
        // mid-page. `.safeAreaInset` keeps it above the home indicator and tab
        // bar automatically.
        .safeAreaInset(edge: .bottom) {
            if let detail = viewModel.detail, hasCookableContent(detail) {
                cookBar(detail)
            }
        }
        // The full title now leads the content (below the image), so the nav bar
        // carries only a compact inline title rather than a second large one.
        .navigationTitle(viewModel.detail?.title ?? "Recipe")
        .inlineNavigationTitle()
        // Lift Spatch's perch above the pinned cook bar while it's shown so he
        // never sits over the "Start Cooking" button.
        .onChange(of: cookBarShown, initial: true) { _, shows in
            spatchPerch.extraBottomInset = shows ? 76 : 0
        }
        .onDisappear { spatchPerch.extraBottomInset = 0 }
        .dismissesKeyboardOnBackgroundTap()
        .keyboardDoneButton()
        .toolbar {
            // Any signed-in user can schedule any recipe onto their own
            // (RLS-scoped) calendar — this isn't gated on ownership the way
            // Edit is. Shown once the recipe has loaded, since the sheet needs
            // its title.
            if viewModel.detail != nil {
                ToolbarItem(placement: .platformPrimaryAction) {
                    Button {
                        showingAddToCalendar = true
                    } label: {
                        Label("Add to Calendar", systemImage: "calendar.badge.plus")
                    }
                }
            }
            if isOwnedByCurrentUser {
                ToolbarItem(placement: .platformPrimaryAction) {
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
                    .platformMediumLargeDetents()
            }
        }
        .platformFullScreenCover(isPresented: $showingCookMode) {
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
        // Offer Spatch a recipe-aware line shortly after load — routed to the
        // shared perch (he stays put; the user taps to read it), not floated
        // over the recipe.
        .task(id: viewModel.detail?.id) {
            guard let detail = viewModel.detail else { return }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, Double.random(in: 0...1) < 0.6 else { return }
            spatchPerch.post(
                SpatchContent.recipeCameoLine(prepTime: detail.prepTime, tag: detail.tagNames.first),
                mood: .happy
            )
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

    /// The Servings stat rendered as an interactive stepper — the "stat becomes a
    /// control". Stepping nudges the whole-servings count (via
    /// `RecipeServingsScaler`), which drives `scale`, which recomputes every
    /// ingredient amount through the same `IngredientAmount` formatter the
    /// grocery list uses. Replaces the old toolbar ½/2/3× menu.
    private func servingsStepper(base: Int) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "person.2").foregroundStyle(Color.brandPrimary)
            HStack(spacing: 12) {
                Button {
                    withAnimation(.snappy) {
                        scale = RecipeServingsScaler.steppedScale(base: base, scale: scale, delta: -1)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill").font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(RecipeServingsScaler.canDecrease(base: base, scale: scale) ? Color.brandPrimary : Color.secondary)
                .disabled(!RecipeServingsScaler.canDecrease(base: base, scale: scale))
                .accessibilityLabel("Fewer servings")

                Text("\(RecipeServingsScaler.displayedServings(base: base, scale: scale))")
                    .font(.headline)
                    .frame(minWidth: 22)
                    .contentTransition(.numericText())

                Button {
                    withAnimation(.snappy) {
                        scale = RecipeServingsScaler.steppedScale(base: base, scale: scale, delta: 1)
                    }
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.brandPrimary)
                .accessibilityLabel("More servings")
            }
            Text(scale == 1 ? "Servings" : "Servings (\(scaleLabel))")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .surface(.card)
        .accessibilityElement(children: .contain)
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

            // The full recipe title leads the content directly under the image —
            // wrapping freely, never truncated, however long the name is.
            Text(detail.title)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

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

    /// Whether the pinned cook bar is currently shown (drives the perch lift).
    private var cookBarShown: Bool {
        viewModel.detail.map(hasCookableContent) ?? false
    }

    /// The core "how to cook it" metadata — prep time and (interactive) servings,
    /// inline directly under the title. The ATK rating moved down to the Ratings
    /// & Reviews card, where a rating belongs.
    @ViewBuilder
    private func statsRow(_ detail: RecipeDetail) -> some View {
        HStack(spacing: 16) {
            if let prepLabel = PrepTimeFormat.label(minutes: detail.prepTime) {
                statTile(icon: "clock", value: prepLabel, label: "Prep Time")
            }
            if let servings = detail.servings {
                servingsStepper(base: servings)
            }
        }
    }

    /// America's Test Kitchen's average rating, shown in the Ratings & Reviews
    /// card above the household's own ratings.
    private func atkRatingRow(rating: Double, count: Int?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill").font(.subheadline).foregroundStyle(Color.brandSaffron)
            Text("America's Test Kitchen").font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Text(String(format: "%.1f", rating)).font(.subheadline.weight(.bold))
            if let count, count > 0 {
                Text("· \(count) \(count == 1 ? "review" : "reviews")")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func statTile(icon: String, value: String, label: String, tint: Color = .brandPrimary) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .surface(.card)
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
                        .font(.callout.weight(.medium))
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
                        Task {
                            if viewModel.isInGroceryList(ingredient) {
                                await viewModel.removeIngredientFromGroceryList(ingredient)
                            } else {
                                await viewModel.addIngredientToGroceryList(ingredient, scale: scale)
                            }
                        }
                    } label: {
                        Image(systemName: viewModel.isInGroceryList(ingredient) ? "checkmark.circle.fill" : "plus.circle")
                            .font(.title3)
                            .foregroundStyle(Color.brandSage)
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .accessibilityLabel(
                        viewModel.isInGroceryList(ingredient)
                            ? "Remove \(amount.name) from Grocery List"
                            : "Add \(amount.name) to Grocery List"
                    )
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

            // America's Test Kitchen's own rating — a rating, so it lives with
            // the ratings rather than up in the cook-metadata row.
            if let atkRating = viewModel.detail?.atkRating {
                atkRatingRow(rating: atkRating, count: viewModel.detail?.atkRatingCount)
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
        .surface(.card, radius: Surface.Radius.large)
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

    /// The pinned bottom action bar: a full-width "Start Cooking" over a
    /// translucent bar so scrolling content stays legible beneath it. Capped to
    /// the same readable column as the content on wide screens.
    private func cookBar(_ detail: RecipeDetail) -> some View {
        Button {
            showingCookMode = true
        } label: {
            Label("Start Cooking", systemImage: "flame.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(Color.brandPrimary)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }
}
