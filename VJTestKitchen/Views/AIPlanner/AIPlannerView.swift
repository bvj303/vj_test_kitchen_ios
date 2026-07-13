import SwiftUI

struct AIPlannerView: View {
    @State private var viewModel = AIPlannerViewModel()
    @FocusState private var isInputFocused: Bool
    /// The recipe whose "Add to Calendar" sheet is open, if any.
    @State private var calendarTarget: AIRecipeRef?

    private static let suggestions: [(label: String, prompt: String, icon: String)] = [
        ("Plan healthy dinners", "Plan a 3-day healthy dinner menu", "calendar"),
        ("Find something new", "Find me a recipe for Beef Wellington", "magnifyingglass"),
        ("What can I cook tonight?", "What can I cook tonight with common pantry ingredients?", "fork.knife"),
    ]

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            header

            if let reason = viewModel.unavailableReason {
                unavailableState(reason)
            } else {
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
        }
        .task { viewModel.refreshAvailability() }
        .navigationTitle("AI Planner")
        .inlineNavigationTitle()
        .dismissesKeyboardOnBackgroundTap()
        .keyboardDoneButton()
        .sheet(item: $calendarTarget) { recipe in
            AddToCalendarSheet(recipeId: recipe.id, recipeTitle: recipe.title)
                .platformMediumLargeDetents()
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

    /// Shown instead of the chat when the on-device model can't run here
    /// (device not eligible, or Apple Intelligence turned off). Kitchen
    /// Concierge is fully on-device now, so there's no cloud fallback.
    private func unavailableState(_ reason: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles.slash")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Kitchen Concierge Unavailable")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text(reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
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

    private func bubbleText(_ message: AIPlannerViewModel.ChatMessage) -> some View {
        let isUser = message.role == .user
        return Text(LocalizedStringKey(message.content))
            .foregroundStyle(isUser ? .white : .primary)
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
