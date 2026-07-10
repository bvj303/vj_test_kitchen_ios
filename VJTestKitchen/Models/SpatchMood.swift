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

    /// Mouth curvature: negative curves down (frown), positive curves up
    /// (smile). Consumed directly as a control-point offset by `MouthShape`.
    var mouthCurve: CGFloat {
        switch self {
        case .idle: 0.35
        case .happy: 0.75
        case .laughing: 1.0
        case .thinking: 0.1
        case .winking: 0.6
        case .sad: -0.6
        }
    }

    /// Whether the mouth renders as an open "laugh" oval instead of a closed
    /// curved line.
    var mouthIsOpen: Bool {
        self == .laughing
    }

    /// Whether one eye should render shut in a deliberate wink, independent of
    /// the idle blink animation.
    var isWinking: Bool {
        self == .winking
    }
}
