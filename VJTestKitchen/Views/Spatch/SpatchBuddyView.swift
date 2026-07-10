import SwiftUI

/// Spatch's floating cameo companion — a small character + speech bubble, used
/// as a pop-in on Home / Recipe Detail / Cook Mode. He shows up at a random
/// corner (`SpatchBuddyViewModel.corner` — apply via
/// `.overlay(alignment: viewModel.corner.alignment) { ... .padding(viewModel.corner.edgeInsets) }`),
/// auto-hides after a delay, and can be sent away early by swiping him in any
/// direction. Tapping the bubble asks for a fresh line; dragging directly on
/// Spatch still moves his eyes (see `SpatchCharacterView`) — a drag far
/// enough dismisses him either way. He's mirrored on trailing (right-side)
/// corners so he faces inward rather than always facing the same way
/// regardless of which side he popped in on.
///
/// macOS also shows an explicit × button: there's no touch-swipe equivalent
/// with a mouse/trackpad, so Mac users need a click target to send him away.
struct SpatchBuddyView: View {
    var viewModel: SpatchBuddyViewModel
    /// Produces a fresh line when the bubble is tapped — each screen supplies
    /// its own content source (jokes, recipe-aware lines, etc.).
    var onRequestNewLine: () -> (String, SpatchMood)

    @State private var dragOffset: CGSize = .zero

    /// Drag distance past which a swipe counts as "away", in points.
    private let dismissThreshold: CGFloat = 80

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

                // Face inward: mirrored on the right side of the screen,
                // upright on the left, rather than always facing one way.
                SpatchCharacterView(mood: viewModel.mood, isMirrored: viewModel.corner.isTrailing)
                    .frame(width: 30, height: 64)

                #if os(macOS)
                Button {
                    viewModel.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                #endif
            }
            .offset(dragOffset)
            .opacity(swipeFadeOpacity)
            // `simultaneousGesture` so this coexists with SpatchCharacterView's
            // own zero-distance drag (eye-tracking) instead of stealing it.
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { dragOffset = $0.translation }
                    .onEnded { value in
                        let distance = (value.translation.width * value.translation.width
                            + value.translation.height * value.translation.height).squareRoot()
                        if distance > dismissThreshold {
                            withAnimation(.easeOut(duration: 0.2)) {
                                dragOffset = CGSize(width: value.translation.width * 3, height: value.translation.height * 3)
                            }
                            viewModel.dismiss()
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                dragOffset = .zero
                            }
                        }
                    }
            )
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }

    private var swipeFadeOpacity: Double {
        let distance = (dragOffset.width * dragOffset.width + dragOffset.height * dragOffset.height).squareRoot()
        return 1 - min(1, distance / 260)
    }
}
