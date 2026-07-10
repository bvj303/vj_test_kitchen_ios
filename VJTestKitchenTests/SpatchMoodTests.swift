import Testing
@testable import VJTestKitchen

struct SpatchMoodTests {
    @Test func happyMoodsCurveUpward() {
        #expect(SpatchMood.happy.mouthCurve > 0)
        #expect(SpatchMood.idle.mouthCurve > 0)
    }

    @Test func sadMoodCurvesDownward() {
        #expect(SpatchMood.sad.mouthCurve < 0)
    }

    @Test func laughingAndSurprisedOpenTheMouth() {
        for mood in SpatchMood.allCases {
            #expect(mood.mouthIsOpen == (mood == .laughing || mood == .surprised))
        }
    }

    @Test func openMouthKindMatchesTheMood() {
        #expect(SpatchMood.laughing.openMouthKind == .laugh)
        #expect(SpatchMood.surprised.openMouthKind == .surprised)
        #expect(SpatchMood.happy.openMouthKind == nil)
        #expect(SpatchMood.sad.openMouthKind == nil)
    }

    @Test func onlyWinkingClosesAnEye() {
        for mood in SpatchMood.allCases {
            #expect(mood.isWinking == (mood == .winking))
        }
    }

    @Test func sadAndThinkingTiltEyebrowsInOppositeDirections() {
        #expect(SpatchMood.sad.eyebrowTilt < 0)
        #expect(SpatchMood.thinking.eyebrowTilt > 0)
    }

    @Test func surprisedHasTheStrongestEyebrowRaise() {
        let maxTilt = SpatchMood.allCases.map(\.eyebrowTilt).max()
        #expect(SpatchMood.surprised.eyebrowTilt == maxTilt)
    }

    @Test func neutralMoodsHaveNoEyebrowTilt() {
        #expect(SpatchMood.idle.eyebrowTilt == 0)
        #expect(SpatchMood.happy.eyebrowTilt == 0)
        #expect(SpatchMood.laughing.eyebrowTilt == 0)
    }
}
