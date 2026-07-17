import SwiftUI

struct AIPlannerView: View {
    @State private var viewModel = AIPlannerViewModel()
    @FocusState private var isInputFocused: Bool
    /// The recipe whose "Add to Calendar" sheet is open, if any.
    @State private var calendarTarget: AIRecipeRef?
    /// A proposed action awaiting the user's explicit confirmation before it's
    /// written — nothing is applied until the confirmation dialog is confirmed.
    @State private var pendingAction: AIChatAction?

    private static let suggestions: [(label: String, prompt: String, icon: String)] = [
        ("Plan healthy dinners", "Plan a 3-day healthy dinner menu", "calendar"),
        ("Find something new", "Find me a recipe for Beef Wellington", "magnifyingglass"),
        ("What can I cook tonight?", "What can I cook tonight with common pantry ingredients?", "fork.knife"),
    ]

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if viewModel.messages.isEmpty {
                            emptyState
                        } else {
                            ForEach(viewModel.messages) { message in
                                messageBubble(message)
                                    .id(message.id)
                            }
                        }
                        if viewModel.isSending {
                            HStack {
                                ProgressView()
                                Text("Thinking...").foregroundStyle(.secondary)
                            }
                            .padding()
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages) { _, _ in
                    if let last = viewModel.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }

            inputBar
        }
        .navigationTitle("AI Planner")
        .inlineNavigationTitle()
        .dismissesKeyboardOnBackgroundTap()
        .keyboardDoneButton()
        .sheet(item: $calendarTarget) { recipe in
            AddToCalendarSheet(recipeId: recipe.id, recipeTitle: recipe.title)
                .platformMediumLargeDetents()
        }
        .confirmationDialog(
            pendingAction.map(Self.confirmTitle) ?? "",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            Button(Self.confirmButtonLabel(action)) {
                pendingAction = nil
                Task { await viewModel.apply(action) }
            }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        }
        .alert(
            "Done",
            isPresented: Binding(
                get: { viewModel.actionResultMessage != nil },
                set: { if !$0 { viewModel.actionResultMessage = nil } }
            )
        ) {
            Button("OK") { viewModel.actionResultMessage = nil }
        } message: {
            Text(viewModel.actionResultMessage ?? "")
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

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .padding(10)
                .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Kitchen Concierge").font(.headline)
                Text("Your recipe & meal-planning assistant")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Spacer()

            if !viewModel.messages.isEmpty {
                Button("Clear", role: .destructive) { viewModel.clearChat() }
                    .font(.caption)
            }
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("What would you like to cook?")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            ForEach(Self.suggestions, id: \.label) { suggestion in
                Button {
                    viewModel.inputText = suggestion.prompt
                    Task { await viewModel.send() }
                } label: {
                    HStack {
                        Image(systemName: suggestion.icon)
                            .foregroundStyle(Color.brandPrimary)
                        Text(suggestion.label)
                        Spacer()
                    }
                    .padding()
                }
                .glassEffect(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text("Kitchen Concierge may occasionally generate inaccurate information. Please verify cooking times.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
        .padding(.top, 40)
    }

    @ViewBuilder
    private func messageBubble(_ message: AIPlannerViewModel.ChatMessage) -> some View {
        HStack {
            if message.role == .assistant {
                VStack(alignment: .leading, spacing: 10) {
                    bubbleText(message)
                    if !message.recipes.isEmpty {
                        ForEach(message.recipes) { recipe in
                            recipeCard(recipe)
                        }
                    }
                    if !message.actions.isEmpty {
                        ForEach(message.actions) { action in
                            actionControl(action)
                        }
                    }
                }
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                bubbleText(message)
            }
        }
    }

    /// A tappable card for a recipe the assistant recommended: open its detail,
    /// or add it straight to the calendar — so the chat isn't a dead end.
    private func recipeCard(_ recipe: AIRecipeRef) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: recipe.id) {
                HStack(spacing: 10) {
                    Image(systemName: "book.pages")
                        .foregroundStyle(Color.brandPrimary)
                    Text(recipe.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                calendarTarget = recipe
            } label: {
                Label("Add to Calendar", systemImage: "calendar.badge.plus")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.brandSage)
        }
        .padding(12)
        .glassEffect(.regular.tint(Color.brandPrimary.opacity(0.10)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// A confirm-to-apply control for a proposed write action. Tapping opens a
    /// confirmation dialog — nothing is written until the user confirms — and
    /// once applied it shows a persistent "Added ✓" state.
    @ViewBuilder
    private func actionControl(_ action: AIChatAction) -> some View {
        let applied = viewModel.hasApplied(action)
        let applying = viewModel.applyingActionId == action.id
        Button {
            pendingAction = action
        } label: {
            HStack(spacing: 10) {
                Image(systemName: applied ? "checkmark.circle.fill" : Self.actionIcon(action))
                    .foregroundStyle(applied ? Color.brandSage : Color.brandPrimary)
                Text(applied ? Self.appliedLabel(action) : Self.actionLabel(action))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if applying {
                    ProgressView()
                } else if !applied {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .padding(12)
        }
        .buttonStyle(.plain)
        .disabled(applied || applying)
        .glassEffect(.regular.tint(Color.brandSage.opacity(applied ? 0.06 : 0.14)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private static func actionIcon(_ action: AIChatAction) -> String {
        switch action {
        case .addToMealPlan: return "calendar.badge.plus"
        case .addToGroceryList: return "cart.badge.plus"
        case .unknown: return "questionmark"
        }
    }

    private static func actionLabel(_ action: AIChatAction) -> String {
        switch action {
        case let .addToMealPlan(p):
            return "Add \(p.recipeTitle) to \(friendlyDate(p.date)) \(p.mealType.capitalized)"
        case let .addToGroceryList(p):
            let n = p.items.count
            let suffix = p.recipeTitle.map { " for \($0)" } ?? ""
            return "Add \(n) ingredient\(n == 1 ? "" : "s")\(suffix) to grocery list"
        case .unknown:
            return "Unsupported action"
        }
    }

    private static func appliedLabel(_ action: AIChatAction) -> String {
        switch action {
        case .addToMealPlan: return "Added to calendar"
        case .addToGroceryList: return "Added to grocery list"
        case .unknown: return "Done"
        }
    }

    /// Confirmation-dialog title summarizing exactly what will be written.
    private static func confirmTitle(_ action: AIChatAction) -> String {
        switch action {
        case let .addToMealPlan(p):
            return "Add \(p.recipeTitle) to \(friendlyDate(p.date)) \(p.mealType.capitalized)?"
        case let .addToGroceryList(p):
            let n = p.items.count
            return "Add \(n) ingredient\(n == 1 ? "" : "s") to your grocery list?"
        case .unknown:
            return ""
        }
    }

    private static func confirmButtonLabel(_ action: AIChatAction) -> String {
        switch action {
        case .addToMealPlan: return "Add to Calendar"
        case .addToGroceryList: return "Add to Grocery List"
        case .unknown: return "OK"
        }
    }

    /// "2026-07-20" → "Mon, Jul 20". Falls back to the raw string if unparsable.
    private static func friendlyDate(_ iso: String) -> String {
        guard let date = MealPlan.dateFormatter.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.calendar = Calendar(identifier: .gregorian)
        out.timeZone = TimeZone(identifier: "UTC")
        out.dateFormat = "EEE, MMM d"
        return out.string(from: date)
    }

    @ViewBuilder
    private func bubbleText(_ message: AIPlannerViewModel.ChatMessage) -> some View {
        let isUser = message.role == .user
        Group {
            if isUser {
                // The user's own typed text — render plain (no markdown surprises).
                Text(message.content)
                    .foregroundStyle(.white)
            } else {
                // The assistant replies in block markdown (headers, lists) — render
                // it properly instead of showing raw ## / - characters.
                ConciergeMarkdownText(content: message.content)
                    .foregroundStyle(.primary)
            }
        }
        .padding(12)
        .glassEffect(
            isUser ? .regular.tint(Color.brandPrimary.opacity(0.85)) : .regular,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private var inputBar: some View {
        @Bindable var viewModel = viewModel

        return HStack(spacing: 12) {
            TextField("Ask me for a plan or to find a new recipe", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .onSubmit { Task { await viewModel.send() } }

            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSending)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(in: Capsule())
        .padding()
    }
}
