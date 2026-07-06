import SwiftUI

struct AIPlannerView: View {
    @State private var viewModel = AIPlannerViewModel()
    @FocusState private var isInputFocused: Bool

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
            }

            inputBar
        }
        .navigationTitle("AI Planner")
        .navigationBarTitleDisplayMode(.inline)
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
                Text("Gemini 3.1 Flash Lite")
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
                bubbleText(message)
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                bubbleText(message)
            }
        }
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
