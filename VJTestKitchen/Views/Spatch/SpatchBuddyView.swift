import SwiftUI

/// Spatch's floating cameo companion — a small character + speech bubble, used
/// as a pop-in on Home / Recipe Detail / Cook Mode. He pops out from a random
/// screen side (`SpatchBuddyViewModel.corner` — the four corners plus the
/// middle of either edge; apply via
/// `.overlay(alignment: viewModel.corner.alignment) { ... .padding(viewModel.corner.edgeInsets) }`),
/// sliding in from that edge with a spring and a random inward lean
/// (`viewModel.tilt`) so no two entrances look alike. He auto-hides after a
/// delay, and can be sent away early by swiping him in any direction. Tapping
/// the bubble asks for a fresh line; dragging directly on Spatch still moves
/// his eyes (see `SpatchCharacterView`) — a drag far enough dismisses him
/// either way. Spatch himself sits on the screen-edge side of his bubble and
/// is mirrored on trailing (right-side) positions, so he always reads as
/// having emerged from that edge, facing inward.
///
/// macOS also shows an explicit × button: there's no touch-swipe equivalent
/// with a mouse/trackpad, so Mac users need a click target to send him away.
struct SpatchBuddyView: View {
    var viewModel: SpatchBuddyViewModel
    /// Produces a fresh line when the bubble is tapped — each screen supplies
    /// its own content source (jokes, recipe-aware lines, etc.).
    var onRequestNewLine: () -> (String, SpatchMood)

    // Regular width (iPad, macOS) gets a noticeably bigger Spatch — 30×64
    // reads as a speck on a 13" screen. Still cameo-small relative to those
    // screens, and he auto-hides/swipes away, so bigger isn't "in the way".
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    // Optional so previews/tests without the app root's injection still work.
    // While the walkthrough is up, Spatch is *on stage there* — a cameo popping
    // in at the same time would put two of him on screen at once. Same deal
    // while a stunt flyby is playing, and none of him at all when the user has
    // turned Spatch off in Settings.
    @Environment(SpatchTutorialViewModel.self) private var tutorialViewModel: SpatchTutorialViewModel?
    @Environment(SpatchStuntCoordinator.self) private var stuntCoordinator: SpatchStuntCoordinator?
    @Environment(SettingsViewModel.self) private var settingsViewModel: SettingsViewModel?

    @State private var dragOffset: CGSize = .zero
    /// This cameo's key in the coordinator's visibility registry — each of the
    /// hosting screens (Home / Recipe Detail / Cook Mode) owns its own cameo.
    @State private var cameoId = UUID()

    /// Drag distance past which a swipe counts as "away", in points.
    private let dismissThreshold: CGFloat = 80

    var body: some View {
        let isShowing = viewModel.isVisible
            && tutorialViewModel?.isPresented != true
            && stuntCoordinator?.isPerforming != true
            && settingsViewModel?.showSpatch != false
        // The ZStack persists across visibility flips so the `if` below is
        // inserted/removed *inside* an animated container — that's what makes
        // the `.transition` actually animate. (Attaching the animation at the
        // host's overlay would work too, but every host would have to
        // remember to.)
        ZStack {
            if isShowing {
                content
                    .transition(
                        .move(edge: viewModel.corner.slideEdge)
                            .combined(with: .scale(scale: 0.6, anchor: anchor(for: viewModel.corner)))
                            .combined(with: .opacity)
                    )
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.68), value: isShowing)
        // Keep the stunt coordinator's registry in sync with what's actually
        // rendered (`isShowing`, not raw `isVisible`) so a stunt never starts
        // while this cameo is on screen. `initial: true` seeds a cameo that's
        // already visible when the view lands; `onDisappear` covers the host
        // screen being popped/dismissed with the cameo still up.
        .onChange(of: isShowing, initial: true) { _, showing in
            stuntCoordinator?.setCameoVisible(showing, id: cameoId)
        }
        .onDisappear {
            stuntCoordinator?.setCameoVisible(false, id: cameoId)
        }
        .onChange(of: viewModel.isVisible) { _, isVisible in
            // A swipe-dismiss leaves `dragOffset` at its flung 3× value; without
            // this reset the *next* pop-in would render him off-position and
            // faded out by `swipeFadeOpacity`.
            if isVisible { dragOffset = .zero }
        }
    }

    private var content: some View {
        HStack(alignment: .bottom, spacing: 6) {
            // Spatch hugs the screen edge he popped out of; the bubble sits
            // inboard of him, toward the screen center.
            if viewModel.corner.isTrailing {
                bubble
                character
                #if os(macOS)
                closeButton
                #endif
            } else {
                #if os(macOS)
                closeButton
                #endif
                character
                bubble
            }
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
    }

    private var bubble: some View {
        Button {
            let (message, mood) = onRequestNewLine()
            viewModel.cycle(to: message, mood: mood)
        } label: {
            SpatchBubbleView(text: viewModel.message)
        }
        .buttonStyle(.plain)
    }

    private var character: some View {
        // Face inward (mirrored on the right side of the screen) and lean
        // inward by the entrance's random tilt, pivoting at his handle end —
        // like he's peeking in around the screen edge.
        SpatchCharacterView(mood: viewModel.mood, isMirrored: viewModel.corner.isTrailing)
            .frame(
                width: horizontalSizeClass == .regular ? 46 : 30,
                height: horizontalSizeClass == .regular ? 98 : 64
            )
            .rotationEffect(.degrees(viewModel.tilt), anchor: .bottom)
    }

    #if os(macOS)
    private var closeButton: some View {
        Button {
            viewModel.dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
    #endif

    /// Scale the entrance from the screen side he's emerging from, so the pop
    /// visually grows out of that edge.
    private func anchor(for corner: SpatchCorner) -> UnitPoint {
        switch corner {
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .midLeading: .leading
        case .midTrailing: .trailing
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        }
    }

    private var swipeFadeOpacity: Double {
        let distance = (dragOffset.width * dragOffset.width + dragOffset.height * dragOffset.height).squareRoot()
        return 1 - min(1, distance / 260)
    }
}
