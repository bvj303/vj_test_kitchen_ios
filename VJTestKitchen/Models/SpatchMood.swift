import SwiftUI

/// Spatch's current emotional state, driving both his facial expression
/// (`SpatchCharacterView`) and which line of dialogue accompanies him. Pure and
/// stateless — same shape as `MealTypeStyle`/`HolidayProvider` — so it's fully
/// unit-testable with no view dependency.
enum SpatchMood: String, CaseIterable, Sendable, Equatable {
    case idle
    case happy
    case laughing
    case thinking
    case winking
    case sad
    case surprised

    /// A mouth that's open rather than a closed curved line — and which shape
    /// of "open" (see `SpatchCharacterView.mouth`).
    enum OpenMouthKind: Sendable, Equatable {
        case laugh
        case surprised
    }

    /// Mouth curvature: negative curves down (frown), positive curves up
    /// (smile). Consumed directly as a control-point offset by `MouthShape`.
    /// Meaningless (but harmless) when `openMouthKind` is non-nil.
    var mouthCurve: CGFloat {
        switch self {
        case .idle: 0.35
        case .happy: 0.75
        case .laughing: 1.0
        case .thinking: 0.1
        case .winking: 0.6
        case .sad: -0.6
        case .surprised: 0
        }
    }

    /// Which open-mouth shape to render, or nil for a closed curved mouth.
    var openMouthKind: OpenMouthKind? {
        switch self {
        case .laughing: .laugh
        case .surprised: .surprised
        default: nil
        }
    }

    /// Whether the mouth renders open at all (either `OpenMouthKind`).
    var mouthIsOpen: Bool {
        openMouthKind != nil
    }

    /// Eyebrow tilt: positive raises the outer edge (curious/surprised),
    /// negative angles the inner edge up (worried/sad). 0 is neutral.
    var eyebrowTilt: CGFloat {
        switch self {
        case .sad: -0.5
        case .thinking: 0.3
        case .surprised: 0.7
        case .winking: 0.2
        default: 0
        }
    }

    /// Whether one eye should render shut in a deliberate wink, independent of
    /// the idle blink animation.
    var isWinking: Bool {
        self == .winking
    }
}
