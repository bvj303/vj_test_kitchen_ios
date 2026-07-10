import SwiftUI

/// First-launch walkthrough: a bottom-anchored card overlaid on the real app
/// (see `MainTabView`), which follows `SpatchTutorialViewModel.targetTab` to
/// actually switch tabs as the tour advances — so each step narrates over the
/// real screen it's introducing rather than a static mockup. "Send Spatch
/// Away" visibly makes him sad before the card closes. Shown at most once
/// (`SpatchTutorialViewModel.maybePresentOnLaunch()`); replayable from
/// Settings via `restart()`.
struct SpatchTutorialView: View {
    @Environment(SpatchTutorialViewModel.self) private var viewModel

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            card
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .task { viewModel.onAppear() }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                SpatchCharacterView(mood: viewModel.mood)
                    .frame(width: 50, height: 106)

                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.isLeaving ? "Aw, okay…" : viewModel.currentStep.title)
                        .font(.title3.bold())
                    Text(viewModel.isLeaving ? SpatchContent.sadGoodbyeLine : viewModel.currentStep.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .animation(.default, value: viewModel.stepIndex)

                Spacer(minLength: 0)
            }

            if !viewModel.isLeaving {
                pageDots
                controls
            }
        }
        .padding(18)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.tint(Color.brandSage.opacity(0.2)), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(viewModel.steps.indices, id: \.self) { index in
                Circle()
                    .fill(index == viewModel.stepIndex ? Color.brandSage : Color.brandSage.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var controls: some View {
        HStack {
            if !viewModel.isFirstStep {
                Button("Back") { viewModel.goBack() }
            }
            Button("Send Spatch Away", role: .destructive) { viewModel.sendAway() }
                .font(.footnote)
            Spacer()
            Button(viewModel.isLastStep ? "Let's Cook!" : "Next") { viewModel.advance() }
                .buttonStyle(.glassProminent)
        }
    }
}

#Preview {
    SpatchTutorialView()
        .environment(SpatchTutorialViewModel())
}
