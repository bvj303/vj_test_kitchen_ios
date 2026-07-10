import Foundation
import CoreGraphics

/// Pure math mapping a stunt run + animation progress (0...1) to where Spatch
/// is on the stage and how he's rotated — kept out of the view (like
/// `HolidayProvider`/`MealTypeStyle`) so the paths are unit-testable: every
/// stunt must start and end fully offstage, and the somersault must land
/// upright (whole turns only).
enum SpatchStuntChoreography {
    struct Placement: Equatable {
        /// Center of the performer (Spatch + any props), in stage coordinates.
        var x: CGFloat
        var y: CGFloat
        var rotationDegrees: Double
    }

    /// `performer` is the full prop assembly's size (e.g. balloons included),
    /// so "offstage" math clears the stage edge with the whole rig, not just
    /// the character.
    static func placement(
        run: SpatchStuntRun,
        progress: CGFloat,
        stage: CGSize,
        performer: CGSize
    ) -> Placement {
        let p = min(max(progress, 0), 1)
        switch run.stunt {
        case .somersault:
            var placement = horizontalTravel(run: run, progress: p, stage: stage, performer: performer)
            // Three springy hops along the way; lane picks how low he tumbles.
            let baseY = stage.height * (0.60 + 0.20 * run.lane)
            placement.y = baseY - abs(sin(p * .pi * 3)) * stage.height * 0.09
            // Three full forward rolls — whole turns, so he exits upright.
            placement.rotationDegrees = Double(p) * 1080 * travelSign(run)
            return placement

        case .dash:
            var placement = horizontalTravel(run: run, progress: p, stage: stage, performer: performer)
            placement.y = stage.height * (0.55 + 0.25 * run.lane)
            // A constant forward lean into the sprint.
            placement.rotationDegrees = 16 * travelSign(run)
            return placement

        case .spacewalk:
            var placement = horizontalTravel(run: run, progress: p, stage: stage, performer: performer)
            // A slow weightless bob around mid-screen with a lazy end-over tilt
            // that returns to level by exit.
            let baseY = stage.height * (0.22 + 0.30 * run.lane)
            placement.y = baseY + sin(p * .pi * 3) * stage.height * 0.06
            placement.rotationDegrees = sin(Double(p) * .pi * 2) * 24 * travelSign(run)
            return placement

        case .balloonRide:
            // Rises from below the bottom edge to above the top one, swaying
            // side to side and rocking gently like a real balloon rig.
            let baseX = stage.width * (0.22 + 0.56 * run.lane)
            let sway = sin(p * .pi * 4) * stage.width * 0.05
            let startY = stage.height + performer.height / 2
            let endY = -performer.height / 2
            return Placement(
                x: baseX + sway,
                y: startY + (endY - startY) * p,
                rotationDegrees: sin(Double(p) * .pi * 3) * 6
            )

        case .paperPlane:
            var placement = horizontalTravel(run: run, progress: p, stage: stage, performer: performer)
            // A glide that loses a little altitude overall, with swoops on the
            // way and a matching bank into each one.
            let baseY = stage.height * (0.22 + 0.28 * run.lane)
            let descent: CGFloat = p * stage.height * 0.16
            let swoop: CGFloat = sin(p * .pi * 2.4) * stage.height * 0.05
            placement.y = baseY + descent + swoop
            placement.rotationDegrees = (8 + cos(Double(p) * .pi * 2.4) * 10) * travelSign(run)
            return placement

        case .rocketRide:
            // Straight up with a tiny thrust wiggle, accelerating as he climbs
            // (squared progress: slow off the pad, flat out by the top).
            let eased = p * p
            let baseX = stage.width * (0.25 + 0.50 * run.lane)
            let wiggle = sin(p * .pi * 6) * stage.width * 0.015
            let startY = stage.height + performer.height / 2
            let endY = -performer.height / 2
            return Placement(
                x: baseX + wiggle,
                y: startY + (endY - startY) * eased,
                rotationDegrees: sin(Double(p) * .pi * 5) * 3
            )

        case .parachuteDrop:
            // The balloon ride's mirror image: in from above the top edge,
            // out below the bottom, swinging like a pendulum under the canopy
            // — the tilt tracks the swing so canopy and rig lean together.
            let baseX = stage.width * (0.25 + 0.50 * run.lane)
            let swing = sin(p * .pi * 3) * stage.width * 0.06
            let startY = -performer.height / 2
            let endY = stage.height + performer.height / 2
            return Placement(
                x: baseX + swing,
                y: startY + (endY - startY) * p,
                rotationDegrees: sin(Double(p) * .pi * 3) * 9
            )

        case .bubbleBounce:
            var placement = horizontalTravel(run: run, progress: p, stage: stage, performer: performer)
            // Two-and-a-half big lazy arcs — floatier and slower than the
            // somersault's hops — with a gentle roll inside the bubble.
            let baseY = stage.height * (0.55 + 0.25 * run.lane)
            placement.y = baseY - abs(sin(p * .pi * 2.5)) * stage.height * 0.17
            placement.rotationDegrees = sin(Double(p) * .pi * 2.5) * 12 * travelSign(run)
            return placement

        case .whiskBroom:
            var placement = horizontalTravel(run: run, progress: p, stage: stage, performer: performer)
            // A witch's cruise: a smooth bob with a steady nose-down lean into
            // the flight, plus a little flutter on top.
            let baseY = stage.height * (0.24 + 0.30 * run.lane)
            placement.y = baseY + sin(p * .pi * 3) * stage.height * 0.035
            placement.rotationDegrees = (-7 + sin(Double(p) * .pi * 6) * 4) * travelSign(run)
            return placement

        case .pizzaSurf:
            var placement = horizontalTravel(run: run, progress: p, stage: stage, performer: performer)
            // Surfing: bigger waves than the broom, carving (max tilt) right
            // where each wave is steepest — rotation is the bob's cosine.
            let baseY = stage.height * (0.35 + 0.30 * run.lane)
            placement.y = baseY + sin(p * .pi * 4) * stage.height * 0.05
            placement.rotationDegrees = cos(Double(p) * .pi * 4) * 9 * travelSign(run)
            return placement

        case .rollingPin:
            var placement = horizontalTravel(run: run, progress: p, stage: stage, performer: performer)
            // Log-rolling near the floor: quick tiny jitters, arms-out wobble.
            let baseY = stage.height * (0.72 + 0.12 * run.lane)
            placement.y = baseY - abs(sin(p * .pi * 5)) * stage.height * 0.012
            placement.rotationDegrees = sin(Double(p) * .pi * 5) * 4 * travelSign(run)
            return placement

        case .toastPop:
            // Ballistic pop from the bottom edge: sin(p·π) is fastest at the
            // ends and hangs at the apex, so it reads as a real toaster launch
            // — up, hover, drop back out of sight. lane picks the slot.
            let baseX = stage.width * (0.25 + 0.50 * run.lane)
            // A few points of slack below the edge: sin(π) isn't exactly zero
            // in floating point, and the endpoints must be decisively offstage.
            let startY = stage.height + performer.height / 2 + 8
            let rise = stage.height * 0.62 + performer.height
            return Placement(
                x: baseX,
                y: startY - sin(p * .pi) * rise,
                rotationDegrees: sin(Double(p) * .pi * 2) * 6
            )

        case .potSail:
            var placement = horizontalTravel(run: run, progress: p, stage: stage, performer: performer)
            // A slow cruise on gentle swells, rocking harder than it bobs.
            let baseY = stage.height * (0.55 + 0.25 * run.lane)
            placement.y = baseY + sin(p * .pi * 2.4) * stage.height * 0.02
            placement.rotationDegrees = sin(Double(p) * .pi * 3.2) * 7 * travelSign(run)
            return placement
        }
    }

    /// +1 when traveling leading→trailing, -1 reversed — signs rotations so
    /// rolls and leans always point the way he's moving.
    private static func travelSign(_ run: SpatchStuntRun) -> Double {
        run.isReversed ? -1 : 1
    }

    /// Linear x travel that starts and ends with the whole performer beyond
    /// the stage edges. y/rotation are filled in per stunt.
    private static func horizontalTravel(
        run: SpatchStuntRun,
        progress: CGFloat,
        stage: CGSize,
        performer: CGSize
    ) -> Placement {
        // Extra clearance so rotation (which sweeps the diagonal) never peeks
        // a corner onto the stage at the endpoints.
        let clearance = max(performer.width, performer.height) / 2 + 8
        let startX = run.isReversed ? stage.width + clearance : -clearance
        let endX = run.isReversed ? -clearance : stage.width + clearance
        return Placement(x: startX + (endX - startX) * progress, y: 0, rotationDegrees: 0)
    }
}
