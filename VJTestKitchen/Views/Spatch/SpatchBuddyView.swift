import SwiftUI

/// Spatch's floating cameo companion — a small character + speech bubble, used
/// as Home's persistent companion and as an occasional pop-in on Recipe Detail
/// / Cook Mode. Tapping the bubble asks for a fresh line; tapping Spatch
/// himself just makes him wobble (handled inside `SpatchCharacterView`).
struct SpatchBuddyView: View {
    var viewModel: SpatchBuddyViewModel
    /// Produces a fresh line when the bubble is tapped — each screen supplies
    /// its own content source (jokes, recipe-aware lines, etc.).
    var onRequestNewLine: () -> (String, SpatchMood)
    /// Shows an explicit close button — on for cameos (Recipe/Cook Mode), off
    /// for Home's persistent companion.
    var dismissible = false

    var body: some View {
        if viewModel.isVisible {
            HStack(alignment: .bottom, spacing: 6) {
                Button {
                    let (message, mood) = onRequestNewLine()
                    viewModel.cycle(to: message, mood: mood)
                } label: {
                    SpatchBubbleView(text: viewModel.message)
                }
                .buttonStyle(.plain)

                SpatchCharacterView(mood: viewModel.mood)
                    .frame(width: 44, height: 64)

                if dismissible {
                    Button {
                        viewModel.dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }
}
