import SwiftUI

/// First-launch walkthrough: Spatch introduces the app one tab at a time, with
/// Back/Next controls and a "Send Spatch Away" skip that visibly makes him sad
/// before the sheet closes. Shown at most once (see
/// `SpatchTutorialViewModel.maybePresentOnLaunch()` / `MainTabView`); replayable
/// from Settings via `restart()`.
struct SpatchTutorialView: View {
    @Environment(SpatchTutorialViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)

            SpatchCharacterView(mood: viewModel.mood)
                .frame(width: 130, height: 190)

            VStack(spacing: 10) {
                Text(viewModel.isLeaving ? "Aw, okay…" : viewModel.currentStep.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(viewModel.isLeaving ? SpatchContent.sadGoodbyeLine : viewModel.currentStep.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
            .animation(.default, value: viewModel.stepIndex)

            if !viewModel.isLeaving {
                pageDots
            }

            Spacer(minLength: 0)

            if !viewModel.isLeaving {
                controls
            }
        }
        .padding(24)
        .frame(maxWidth: 460, maxHeight: .infinity)
        .task { viewModel.onAppear() }
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
        VStack(spacing: 12) {
            HStack {
                if !viewModel.isFirstStep {
                    Button("Back") { viewModel.goBack() }
                }
                Spacer()
                Button(viewModel.isLastStep ? "Let's Cook!" : "Next") { viewModel.advance() }
                    .buttonStyle(.glassProminent)
            }
            Button("Send Spatch Away", role: .destructive) { viewModel.sendAway() }
                .font(.footnote)
        }
    }
}

#Preview {
    SpatchTutorialView()
        .environment(SpatchTutorialViewModel())
}
