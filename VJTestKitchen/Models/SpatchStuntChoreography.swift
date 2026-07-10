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
