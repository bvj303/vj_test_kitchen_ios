import Testing
@testable import VJTestKitchen

struct SpatchMoodTests {
    @Test func happyMoodsCurveUpward() {
        #expect(SpatchMood.happy.mouthCurve > 0)
        #expect(SpatchMood.laughing.mouthCurve > 0)
        #expect(SpatchMood.idle.mouthCurve > 0)
    }

    @Test func sadMoodCurvesDownward() {
        #expect(SpatchMood.sad.mouthCurve < 0)
    }

    @Test func onlyLaughingOpensTheMouth() {
        for mood in SpatchMood.allCases {
            #expect(mood.mouthIsOpen == (mood == .laughing))
        }
    }

    @Test func onlyWinkingClosesAnEye() {
        for mood in SpatchMood.allCases {
            #expect(mood.isWinking == (mood == .winking))
        }
    }
}
