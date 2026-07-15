import Foundation

/// One of Spatch's surprise stunt animations — a decorative, non-interactive
/// flyby that plays across the whole screen every so often while the app is in
/// use (scheduled by `SpatchStuntCoordinator`, drawn by `SpatchStuntStageView`).
/// Distinct from his perch commentary (`SpatchPerchViewModel`): a stunt has no
/// speech bubble and can't be tapped — he's just passing through.
enum SpatchStunt: CaseIterable, Sendable {
    /// Tumbles across the lower part of the screen in springy somersaults.
    case somersault
    /// Drifts up and off the top of the screen hanging from a bunch of balloons.
    case balloonRide
    /// Floats weightlessly across mid-screen in a bubble helmet, stars twinkling.
    case spacewalk
    /// Zips across at full speed, motion lines trailing behind.
    case dash
    /// Glides across on a paper airplane, swooping and banking as it descends.
    case paperPlane
    /// Blasts off from the bottom and accelerates off the top, flame at the handle.
    case rocketRide
    /// Drifts down the whole screen swaying under a striped parachute canopy.
    case parachuteDrop
    /// Bounces across the screen sealed inside a big soap bubble.
    case bubbleBounce
    /// Flies across witch-style astride a giant balloon whisk, bristles back.
    case whiskBroom
    /// Surfs a pepperoni pizza across the screen, carving into each wave.
    case pizzaSurf
    /// Log-rolls along the bottom of the screen balanced on a rolling pin.
    case rollingPin
    /// Pops up from the bottom edge like toast from a toaster, hangs at the
    /// apex, and drops back out of sight — the one stunt that enters and
    /// exits the same edge.
    case toastPop
    /// Sails across sitting in a steaming stockpot, rocking like a boat.
    case potSail

    /// How long the whole flyby takes, entrance to exit.
    var duration: TimeInterval {
        switch self {
        case .somersault: 4.0
        case .balloonRide: 8.0
        case .spacewalk: 9.0
        case .dash: 1.6
        case .paperPlane: 6.5
        case .rocketRide: 3.2
        case .parachuteDrop: 9.5
        case .bubbleBounce: 5.5
        case .whiskBroom: 5.5
        case .pizzaSurf: 6.0
        case .rollingPin: 4.5
        case .toastPop: 3.8
        case .potSail: 8.0
        }
    }

    /// A random stunt guaranteed to differ from `last`, so back-to-back
    /// performances never repeat.
    static func random(excluding last: SpatchStunt?) -> SpatchStunt {
        allCases.filter { $0 != last }.randomElement() ?? .somersault
    }
}

/// One scheduled performance of a stunt, with its staging randomized so no two
/// runs look identical. `id` is what the stage view keys the animation on —
/// two consecutive runs of the same stunt still restart cleanly.
struct SpatchStuntRun: Identifiable, Equatable, Sendable {
    let id: UUID
    let stunt: SpatchStunt
    /// Travel direction for horizontal stunts: trailing→leading when true.
    let isReversed: Bool
    /// 0...1 pick of the cross-axis position — which height a horizontal stunt
    /// plays at, or where along the width the balloon ride lifts off.
    let lane: CGFloat

    static func random(excluding last: SpatchStunt?) -> SpatchStuntRun {
        SpatchStuntRun(
            id: UUID(),
            stunt: .random(excluding: last),
            isReversed: Bool.random(),
            lane: .random(in: 0...1)
        )
    }
}
