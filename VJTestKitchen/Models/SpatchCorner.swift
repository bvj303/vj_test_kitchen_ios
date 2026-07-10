import SwiftUI

/// Where one of Spatch's cameo pop-ins appears on screen — randomized each
/// time he shows up (see `SpatchBuddyViewModel`) so he doesn't camp in one
/// spot and block the same content every visit. Besides the four corners he
/// can also peek in from the middle of either side edge, so consecutive
/// visits genuinely come from different sides of the screen. Top positions
/// get extra top inset so he clears an inline navigation bar rather than
/// sitting under it.
enum SpatchCorner: CaseIterable, Sendable {
    case topLeading
    case topTrailing
    case midLeading
    case midTrailing
    case bottomLeading
    case bottomTrailing

    var alignment: Alignment {
        switch self {
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .midLeading: .leading
        case .midTrailing: .trailing
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        }
    }

    /// Whether this position sits on the right side of the screen — used to
    /// mirror `SpatchCharacterView` so he pops in "facing inward" rather than
    /// always facing the same way regardless of which side he's on.
    var isTrailing: Bool {
        switch self {
        case .topTrailing, .midTrailing, .bottomTrailing: true
        case .topLeading, .midLeading, .bottomLeading: false
        }
    }

    /// The screen side this position hugs — his entrance slides in from this
    /// edge (`.transition(.move(edge:))` in `SpatchBuddyView`), so he reads as
    /// popping out from behind that side of the screen.
    var slideEdge: Edge {
        switch self {
        case .topLeading, .topTrailing: .top
        case .bottomLeading, .bottomTrailing: .bottom
        case .midLeading: .leading
        case .midTrailing: .trailing
        }
    }

    var edgeInsets: EdgeInsets {
        switch self {
        case .topLeading: EdgeInsets(top: 64, leading: 12, bottom: 0, trailing: 0)
        case .topTrailing: EdgeInsets(top: 64, leading: 0, bottom: 0, trailing: 12)
        case .midLeading: EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 0)
        case .midTrailing: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 8)
        case .bottomLeading: EdgeInsets(top: 0, leading: 12, bottom: 12, trailing: 0)
        case .bottomTrailing: EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 12)
        }
    }

    /// A random position different from `current`, so consecutive pop-ins
    /// visibly relocate rather than sometimes landing back in the same spot.
    static func random(excluding current: SpatchCorner? = nil) -> SpatchCorner {
        allCases.filter { $0 != current }.randomElement() ?? .bottomTrailing
    }
}
