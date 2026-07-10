import Foundation
import Testing
@testable import VJTestKitchen

struct SpatchStuntTests {
    @Test func everyStuntHasAPositiveDuration() {
        for stunt in SpatchStunt.allCases {
            #expect(stunt.duration > 0)
        }
    }

    @Test func randomExcludingNeverRepeatsTheLastStunt() {
        // Deterministic, not just eventual — `random(excluding:)` filters the
        // pool before picking, so back-to-back stunts always differ.
        for stunt in SpatchStunt.allCases {
            for _ in 0..<20 {
                #expect(SpatchStunt.random(excluding: stunt) != stunt)
            }
        }
    }

    @Test func randomWithNoExclusionStillPicksAValidStunt() {
        #expect(SpatchStunt.allCases.contains(SpatchStunt.random(excluding: nil)))
    }

    @Test func runsCarryAStuntAndRandomizedStaging() {
        let run = SpatchStuntRun.random(excluding: nil)
        #expect(SpatchStunt.allCases.contains(run.stunt))
        #expect((0.0...1.0).contains(run.lane))
    }

    @Test func distinctRunsGetDistinctIdentities() {
        // The stage view keys its keyframe trigger on the run id, so two
        // consecutive runs of the *same* stunt must still restart the animation.
        #expect(SpatchStuntRun.random(excluding: nil).id != SpatchStuntRun.random(excluding: nil).id)
    }
}

struct SpatchStuntChoreographyTests {
    private let stage = CGSize(width: 393, height: 852)
    private let performer = CGSize(width: 110, height: 180)

    private func run(_ stunt: SpatchStunt, isReversed: Bool = false, lane: CGFloat = 0.5) -> SpatchStuntRun {
        SpatchStuntRun(id: UUID(), stunt: stunt, isReversed: isReversed, lane: lane)
    }

    /// True when the performer's (unrotated) bounds sit entirely beyond a
    /// stage edge — i.e. nothing of the rig is visible.
    private func isOffstage(_ placement: SpatchStuntChoreography.Placement) -> Bool {
        placement.x + performer.width / 2 <= 0
            || placement.x - performer.width / 2 >= stage.width
            || placement.y + performer.height / 2 <= 0
            || placement.y - performer.height / 2 >= stage.height
    }

    @Test func everyStuntStartsAndEndsOffstage() {
        for stunt in SpatchStunt.allCases {
            for isReversed in [false, true] {
                for lane: CGFloat in [0, 0.5, 1] {
                    let run = run(stunt, isReversed: isReversed, lane: lane)
                    let entrance = SpatchStuntChoreography.placement(run: run, progress: 0, stage: stage, performer: performer)
                    let exit = SpatchStuntChoreography.placement(run: run, progress: 1, stage: stage, performer: performer)
                    #expect(isOffstage(entrance), "\(stunt) should enter from offstage")
                    #expect(isOffstage(exit), "\(stunt) should exit offstage")
                }
            }
        }
    }

    @Test func somersaultLandsUpright() {
        // Whole turns only — he never exits mid-roll.
        for isReversed in [false, true] {
            let exit = SpatchStuntChoreography.placement(
                run: run(.somersault, isReversed: isReversed), progress: 1, stage: stage, performer: performer
            )
            #expect(exit.rotationDegrees.truncatingRemainder(dividingBy: 360) == 0)
        }
    }

    @Test func midwayThroughEveryStuntHeIsOnStage() {
        for stunt in SpatchStunt.allCases {
            let midpoint = SpatchStuntChoreography.placement(
                run: run(stunt), progress: 0.5, stage: stage, performer: performer
            )
            #expect((0...stage.width).contains(midpoint.x), "\(stunt) should cross the visible stage")
            #expect((0...stage.height).contains(midpoint.y), "\(stunt) should stay on the visible stage midway")
        }
    }

    @Test func verticalStuntsTravelTheRightWay() {
        // Up-and-away stunts must exit off the top; the parachute must fall
        // off the bottom — a sign flip here would look absurd, not just wrong.
        for (stunt, travelsUp) in [
            (SpatchStunt.balloonRide, true),
            (.rocketRide, true),
            (.parachuteDrop, false),
        ] {
            let run = run(stunt)
            let entrance = SpatchStuntChoreography.placement(run: run, progress: 0, stage: stage, performer: performer)
            let exit = SpatchStuntChoreography.placement(run: run, progress: 1, stage: stage, performer: performer)
            #expect((exit.y < entrance.y) == travelsUp, "\(stunt) travels the wrong way")
        }
    }

    @Test func rocketAcceleratesAsItClimbs() {
        // The launch should ease in: the first half of the ride covers less
        // ground than the second.
        let run = run(.rocketRide)
        let start = SpatchStuntChoreography.placement(run: run, progress: 0, stage: stage, performer: performer)
        let mid = SpatchStuntChoreography.placement(run: run, progress: 0.5, stage: stage, performer: performer)
        let end = SpatchStuntChoreography.placement(run: run, progress: 1, stage: stage, performer: performer)
        #expect(abs(mid.y - start.y) < abs(end.y - mid.y))
    }

    @Test func progressIsClampedToTheAnimationRange() {
        let run = run(.somersault)
        let below = SpatchStuntChoreography.placement(run: run, progress: -0.5, stage: stage, performer: performer)
        let atStart = SpatchStuntChoreography.placement(run: run, progress: 0, stage: stage, performer: performer)
        #expect(below == atStart)
    }
}
