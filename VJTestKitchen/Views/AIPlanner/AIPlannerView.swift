import SwiftUI

struct AIPlannerView: View {
    @State private var viewModel = AIPlannerViewModel()
    @FocusState private var isInputFocused: Bool
    /// The recipe whose "Add to Calendar" sheet is open, if any.
    @State private var calendarTarget: AIRecipeRef?
    /// A write awaiting the user's explicit confirmation — nothing is applied
    /// until the confirmation dialog is confirmed.
    @State private var pendingConfirmation: PendingConfirmation?

    /// Chat bubbles stay a readable width on wide screens (iPad, iPhone Duo's
    /// inner display) instead of stretching edge to edge.
    private static let readableWidth: CGFloat = 760

    private enum PendingConfirmation: Identifiable {
        case action(AIChatAction)
        /// Every not-yet-added meal of one reply, added after one confirmation.
        case wholePlan(AIPlannerViewModel.ChatMessage)

        var id: String {
            switch self {
            case let .action(action): return action.id
            case let .wholePlan(message): return "plan-\(message.id)"
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if viewModel.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.messages) { message in
                            messageView(message)
                                .id(message.id)
                        }
                    }
                    if viewModel.isSending {
                        thinkingIndicator
                            .id(Self.thinkingAnchor)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.isSending) { _, sending in
                if sending { withAnimation { proxy.scrollTo(Self.thinkingAnchor, anchor: .bottom) } }
            }
            // A restored conversation opens at its latest message.
            .onAppear { scrollToBottom(proxy, animated: false) }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { inputBar }
        }
        // On a partially folded iPhone Duo the whole chat — transcript and input
        // bar together — moves onto one side of the fold so no message line or
        // the text field runs across the crease.
        .foldAwareColumn(maxWidth: Self.readableWidth)
        .screenBackground()
        .navigationTitle("AI Planner")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .platformPrimaryAction) {
                Button("New Chat", systemImage: "square.and.pencil") {
                    viewModel.clearChat()
                    isInputFocused = false
                }
                .disabled(viewModel.messages.isEmpty || viewModel.isSending)
            }
            .platformVisibilityPriority(.high)
        }
        .task { await viewModel.loadMissingRecipeInfo() }
        .dismissesKeyboardOnBackgroundTap()
        .keyboardDoneButton()
        .sheet(item: $calendarTarget) { recipe in
            AddToCalendarSheet(recipeId: recipe.id, recipeTitle: recipe.title)
                .platformMediumLargeDetents()
        }
        .confirmationDialog(
            pendingConfirmation.map(confirmTitle) ?? "",
            isPresented: Binding(
                get: { pendingConfirmation != nil },
                set: { if !$0 { pendingConfirmation = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingConfirmation
        ) { confirmation in
            Button(confirmButtonLabel(confirmation)) {
                pendingConfirmation = nil
                Task {
                    switch confirmation {
                    case let .action(action): await viewModel.apply(action)
                    case let .wholePlan(message): await viewModel.applyAllMealPlans(in: message)
                    }
                }
            }
            Button("Cancel", role: .cancel) { pendingConfirmation = nil }
        } message: { confirmation in
            if case let .wholePlan(message) = confirmation {
                Text(viewModel.unappliedMealPlans(in: message)
                    .map { "\(Self.friendlyDate($0.date)) \($0.mealType.capitalized): \($0.recipeTitle)" }
                    .joined(separator: "\n"))
            }
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

    private static let thinkingAnchor = "thinking"

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard let last = viewModel.messages.last else { return }
        if animated {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.title)
                    .foregroundStyle(Color.brandPrimary)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular.tint(Color.brandPrimary.opacity(0.14)), in: Circle())
                Text("Kitchen Concierge")
                    .font(.title3.bold())
                Text("Plans meals from your recipes, adds them to your calendar, and builds your grocery list.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            // Always two columns — an even count, so the grid splits cleanly at
            // iPhone Duo's fold instead of a lone chip trailing a row of three.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(ConciergePrompts.starters) { starter in
                    promptChip(starter, fillsWidth: true)
                }
            }

            Text("Kitchen Concierge may occasionally generate inaccurate information. Please verify cooking times.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 24)
    }

    /// A tap-to-send prompt: a starter in the empty state, or a follow-up chip.
    private func promptChip(_ prompt: ConciergePrompts.Prompt, fillsWidth: Bool = false) -> some View {
        Button {
            isInputFocused = false
            Task { await viewModel.send(prompt.prompt) }
        } label: {
            Label(prompt.label, systemImage: prompt.systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.brandPrimary)
                .lineLimit(fillsWidth ? 2 : 1)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: fillsWidth ? 40 : nil, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Color.brandPrimary.opacity(0.08)).interactive(), in: Capsule())
        .disabled(viewModel.isSending)
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Looking through your recipes…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Messages

    @ViewBuilder
    private func messageView(_ message: AIPlannerViewModel.ChatMessage) -> some View {
        if message.role == .assistant {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    bubbleText(message)
                    ForEach(message.recipes) { recipe in
                        recipeCard(recipe, plannedAs: Self.plannedAction(for: recipe, in: message))
                    }
                    let mealPlans = message.actions.filter(\.isMealPlan)
                    if mealPlans.count > 1 {
                        wholePlanButton(message, total: mealPlans.count)
                    }
                    // A proposed meal for a recipe that has a card lives on that
                    // card; only the rest (grocery additions, meals without a
                    // card) get their own row — so a plan isn't listed twice.
                    ForEach(Self.standaloneActions(in: message)) { action in
                        actionControl(action)
                    }
                    let followUps = viewModel.followUps(for: message)
                    if !followUps.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(followUps) { promptChip($0) }
                            }
                            .padding(.vertical, 2)
                        }
                        .scrollClipDisabled()
                    }
                }
                Spacer(minLength: 40)
            }
        } else {
            VStack(alignment: .trailing, spacing: 6) {
                HStack {
                    Spacer(minLength: 40)
                    bubbleText(message)
                }
                if let reason = message.failureReason {
                    failureNotice(reason)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// Shown under a user message that didn't go through — the message stays
    /// in the chat and one tap re-sends it.
    private func failureNotice(_ reason: String) -> some View {
        HStack(spacing: 8) {
            Label(reason, systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.trailing)
            Button("Try Again", systemImage: "arrow.clockwise") {
                Task { await viewModel.retry() }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.plain)
            .foregroundStyle(Color.brandPrimary)
            .disabled(viewModel.isSending)
        }
    }

    /// The meal the reply proposes for `recipe`, if any — shown on its card.
    private static func plannedAction(for recipe: AIRecipeRef, in message: AIPlannerViewModel.ChatMessage) -> AIChatAction? {
        message.actions.first { action in
            if case let .addToMealPlan(proposal) = action { return proposal.recipeId == recipe.id }
            return false
        }
    }

    private static func standaloneActions(in message: AIPlannerViewModel.ChatMessage) -> [AIChatAction] {
        let carded = Set(message.recipes.compactMap { plannedAction(for: $0, in: message)?.id })
        return message.actions.filter { !carded.contains($0.id) }
    }

    /// A tappable card for a recipe the assistant recommended: open its detail,
    /// and either confirm the day the reply proposed for it (`plannedAs`) or pick
    /// a day yourself — so the chat isn't a dead end.
    private func recipeCard(_ recipe: AIRecipeRef, plannedAs plannedAction: AIChatAction? = nil) -> some View {
        let info = viewModel.recipeInfo[recipe.id]
        return VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: recipe.id) {
                HStack(spacing: 12) {
                    RecipeThumbnail(imageUrl: info?.imageUrl)
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if let info {
                            HStack(spacing: 12) {
                                if let prep = PrepTimeFormat.label(minutes: info.prepTime) {
                                    Label(prep, systemImage: "clock")
                                }
                                if let servings = info.servings, servings > 0 {
                                    Label("\(servings)", systemImage: "person.2")
                                }
                                if let rating = info.atkRating {
                                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .labelStyle(.compact)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let plannedAction, case let .addToMealPlan(proposal) = plannedAction {
                let applied = viewModel.hasApplied(plannedAction)
                let slot = "\(Self.friendlyDate(proposal.date)) \(proposal.mealType.capitalized)"
                Button {
                    pendingConfirmation = .action(plannedAction)
                } label: {
                    HStack(spacing: 6) {
                        Label(applied ? "On your calendar · \(slot)" : "Add to \(slot)",
                              systemImage: applied ? "checkmark.circle.fill" : "calendar.badge.plus")
                            .font(.caption.weight(.semibold))
                        if viewModel.applyingActionId == plannedAction.id { ProgressView().controlSize(.mini) }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.brandSage)
                .disabled(applied || viewModel.applyingActionId != nil || viewModel.isApplyingPlan)
            } else {
                Button {
                    calendarTarget = recipe
                } label: {
                    Label("Add to Calendar", systemImage: "calendar.badge.plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.brandSage)
            }
        }
        .padding(12)
        .glassEffect(.regular.tint(Color.brandPrimary.opacity(0.10)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// One confirmation for every meal of a multi-day plan, instead of a dialog
    /// per meal.
    private func wholePlanButton(_ message: AIPlannerViewModel.ChatMessage, total: Int) -> some View {
        let remaining = viewModel.unappliedMealPlans(in: message).count
        return Button {
            pendingConfirmation = .wholePlan(message)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: remaining == 0 ? "checkmark.circle.fill" : "calendar.badge.plus")
                Text(remaining == 0
                     ? "Whole plan added to calendar"
                     : remaining == total ? "Add all \(total) meals to calendar" : "Add the other \(remaining) meals")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if viewModel.isApplyingPlan { ProgressView() }
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(remaining == 0 ? Color.brandSage : .white)
        .disabled(remaining == 0 || viewModel.isApplyingPlan || viewModel.applyingActionId != nil)
        .glassEffect(
            .regular.tint(remaining == 0 ? Color.brandSage.opacity(0.10) : Color.brandPrimary.opacity(0.85)),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    /// A confirm-to-apply control for a proposed write action. Tapping opens a
    /// confirmation dialog — nothing is written until the user confirms — and
    /// once applied it shows a persistent "Added ✓" state.
    @ViewBuilder
    private func actionControl(_ action: AIChatAction) -> some View {
        let applied = viewModel.hasApplied(action)
        let applying = viewModel.applyingActionId == action.id
        Button {
            pendingConfirmation = .action(action)
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
        .disabled(applied || applying || viewModel.isApplyingPlan)
        .glassEffect(.regular.tint(Color.brandSage.opacity(applied ? 0.06 : 0.14)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func confirmTitle(_ confirmation: PendingConfirmation) -> String {
        switch confirmation {
        case let .action(action): return Self.confirmTitle(action)
        case let .wholePlan(message):
            let n = viewModel.unappliedMealPlans(in: message).count
            return "Add \(n) meal\(n == 1 ? "" : "s") to your calendar?"
        }
    }

    private func confirmButtonLabel(_ confirmation: PendingConfirmation) -> String {
        switch confirmation {
        case let .action(action): return Self.confirmButtonLabel(action)
        case .wholePlan: return "Add to Calendar"
        }
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
        let canSend = !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isSending

        return HStack(alignment: .bottom, spacing: 12) {
            TextField("Ask for a plan, a recipe, or a grocery list", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit { Task { await viewModel.send() } }
                .padding(.vertical, 6)

            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(canSend ? Color.brandPrimary : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
