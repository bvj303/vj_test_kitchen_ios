import SwiftUI

/// A `LabelStyle` that tightens the gap between a label's icon and its title.
/// The default `Label` spacing looks too airy for the small caption metadata in
/// recipe rows / cards (clock → prep time, person → servings), leaving an
/// awkwardly wide gap after the icon.
struct CompactLabelStyle: LabelStyle {
    var spacing: CGFloat = 4

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
            configuration.title
        }
    }
}

extension LabelStyle where Self == CompactLabelStyle {
    /// `.labelStyle(.compact)` — a tighter icon-to-title gap for caption metadata.
    static var compact: CompactLabelStyle { CompactLabelStyle() }
}
