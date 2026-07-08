import SwiftUI

/// Shared placeholder shown when a widget has no snapshot yet — e.g. the app
/// hasn't been opened since install, so nothing has been published to the
/// shared container. Nudges the user to open the app rather than rendering blank.
struct WidgetEmptyState: View {
    let symbol: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
