import Foundation
import Testing
@testable import VJTestKitchen

struct IngredientAmountParserTests {
    @Test func parsesPlainInteger() {
        #expect(IngredientAmountParser.parse("200") == 200)
    }

    @Test func parsesDecimal() {
        #expect(IngredientAmountParser.parse("1.5") == 1.5)
    }

    @Test func parsesSimpleFraction() {
        #expect(IngredientAmountParser.parse("1/2") == 0.5)
    }

    @Test func parsesMixedNumber() {
        #expect(IngredientAmountParser.parse("1 1/2") == 1.5)
    }

    @Test func trimsSurroundingWhitespace() {
        #expect(IngredientAmountParser.parse("  2  ") == 2)
    }

    @Test func blankInputIsZero() {
        #expect(IngredientAmountParser.parse("") == 0)
        #expect(IngredientAmountParser.parse("   ") == 0)
    }

    @Test func unparseableTextIsNil() {
        #expect(IngredientAmountParser.parse("a pinch") == nil)
        #expect(IngredientAmountParser.parse("abc") == nil)
    }

    @Test func divideByZeroIsNil() {
        #expect(IngredientAmountParser.parse("1/0") == nil)
    }
}
