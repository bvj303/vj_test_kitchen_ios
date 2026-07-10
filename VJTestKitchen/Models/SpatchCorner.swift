import SwiftUI

/// Where one of Spatch's cameo pop-ins appears on screen — randomized each
/// time he shows up (see `SpatchBuddyViewModel`) so he doesn't camp in one
/// spot and block the same content every visit. Top corners get extra top
/// inset so he clears an inline navigation bar rather than sitting under it.
enum SpatchCorner: CaseIterable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    var alignment: Alignment {
        switch self {
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        }
    }

    /// Whether this corner sits on the right side of the screen — used to
    /// mirror `SpatchCharacterView` so he pops in "facing inward" rather than
    /// always facing the same way regardless of which side he's on.
    var isTrailing: Bool {
        self == .topTrailing || self == .bottomTrailing
    }

    var edgeInsets: EdgeInsets {
        switch self {
        case .topLeading: EdgeInsets(top: 64, leading: 12, bottom: 0, trailing: 0)
        case .topTrailing: EdgeInsets(top: 64, leading: 0, bottom: 0, trailing: 12)
        case .bottomLeading: EdgeInsets(top: 0, leading: 12, bottom: 12, trailing: 0)
        case .bottomTrailing: EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 12)
        }
    }

    /// A random corner different from `current`, so consecutive pop-ins
    /// visibly relocate rather than sometimes landing back in the same spot.
    static func random(excluding current: SpatchCorner? = nil) -> SpatchCorner {
        allCases.filter { $0 != current }.randomElement() ?? .bottomTrailing
    }
}
