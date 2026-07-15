import SwiftUI

/// Spatch's single fixed **perch** — the non-blocking replacement for the old
/// random-corner pop-in cameo. He sits in one place (bottom-trailing, above the
/// tab bar), always the same anchor, and *every* screen routes its commentary
/// through the shared `SpatchPerchViewModel` instead of hosting its own overlay.
/// Because the perch lives in a fixed corner and a tip never forces its bubble
/// open, it structurally cannot land over a card title or stat tile the way the
/// floating cameo did — that whole class of overlap bug is designed out rather
/// than patched per screen.
///
/// Collapsed, he's a small character with a subtle "unread tip" dot when a screen
/// has offered a new line. Tap him to open a speech bubble that grows *upward*
/// (toward screen center, away from the tab bar); tap the bubble for a fresh
/// line; tap him again — or wait — to tuck it away. Personality and animation
/// (breathing, eye-tracking, the release bop) come from `SpatchCharacterView`
/// unchanged; a small bounce plays when a new tip arrives.
///
/// Respects the same gates as before: hidden entirely when "Show Spatch" is off,
/// and yielded to the tutorial and to stunt flybys so only one Spatch is ever on
/// screen. While the bubble is open it reports itself into the stunt
/// coordinator's registry so a flyby won't start over an open bubble.
struct SpatchPerchView: View {
    var viewModel: SpatchPerchViewModel
    /// Extra bottom padding so the perch clears whatever sits at the bottom of
    /// the host. Defaults to the floating tab bar's height on iPhone; surfaces
    /// without a tab bar (e.g. Cook Mode) pass a small value.
    var bottomClearance: CGFloat? = nil

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    // Optional so previews / tests without the app root's injection still work.
    @Environment(SpatchTutorialViewModel.self) private var tutorialViewModel: SpatchTutorialViewModel?
    @Environment(SpatchStuntCoordinator.self) private var stuntCoordinator: SpatchStuntCoordinator?
    @Environment(SettingsViewModel.self) private var settingsViewModel: SettingsViewModel?

    @State private var perchId = UUID()
    @State private var bounce = false

    private var isShowing: Bool {
        settingsViewModel?.showSpatch != false
            && tutorialViewModel?.isPresented != true
            && stuntCoordinator?.isPerforming != true
    }

    private var characterSize: CGSize {
        horizontalSizeClass == .regular ? CGSize(width: 52, height: 110) : CGSize(width: 40, height: 84)
    }

    var body: some View {
        ZStack {
            if isShowing {
                perch
                    .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        // Lift clear of the floating tab bar so the perch sits above it, never
        // over a tab button.
        .padding(.trailing, 16)
        .padding(.bottom, (bottomClearance ?? (horizontalSizeClass == .regular ? 20 : 68)) + viewModel.extraBottomInset)
        .animation(.easeInOut(duration: 0.25), value: viewModel.extraBottomInset)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isShowing)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: viewModel.isExpanded)
        // Only an *open* bubble blocks a stunt (a collapsed perch just hides for
        // the flyby's duration via `isShowing`), mirroring the old cameo's
        // stage-yielding without pinning the stage permanently.
        .onChange(of: viewModel.isExpanded, initial: true) { _, expanded in
            stuntCoordinator?.setCameoVisible(expanded && isShowing, id: perchId)
        }
        .onChange(of: isShowing) { _, showing in
            stuntCoordinator?.setCameoVisible(viewModel.isExpanded && showing, id: perchId)
        }
        .onDisappear { stuntCoordinator?.setCameoVisible(false, id: perchId) }
        // A one-shot nudge when a fresh tip is posted, so he draws the eye without
        // opening over content.
        .onChange(of: viewModel.attentionNonce) { _, _ in
            guard !viewModel.isExpanded else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.45)) { bounce = true }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.2)) { bounce = false }
        }
    }

    private var perch: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if viewModel.isExpanded {
                bubble
                    .transition(.move(edge: .bottom).combined(with: .scale(scale: 0.7, anchor: .bottomTrailing)).combined(with: .opacity))
            }
            character
        }
    }

    private var bubble: some View {
        Button {
            viewModel.cycle(to: SpatchContent.randomJoke(), mood: [.laughing, .surprised].randomElement() ?? .laughing)
        } label: {
            SpatchBubbleView(text: viewModel.message)
        }
        .buttonStyle(.plain)
    }

    private var character: some View {
        Button {
            viewModel.toggle()
        } label: {
            // Bottom-trailing, so he faces inward (mirrored) toward the content.
            SpatchCharacterView(mood: viewModel.mood, isMirrored: true)
                .frame(width: characterSize.width, height: characterSize.height)
                .scaleEffect(bounce ? 1.12 : 1, anchor: .bottom)
                .overlay(alignment: .topLeading) {
                    if viewModel.hasUnreadTip {
                        Circle()
                            .fill(Color.brandPrimary)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.surfaceBackground, lineWidth: 2))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.isExpanded ? "Hide Spatch's tip" : (viewModel.hasUnreadTip ? "Spatch has a tip" : "Spatch"))
        .accessibilityHint(viewModel.isExpanded ? "Double tap to dismiss" : "Double tap to see what Spatch has to say")
    }
}
