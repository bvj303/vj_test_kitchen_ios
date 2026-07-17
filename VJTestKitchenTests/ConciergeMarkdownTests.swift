import Foundation
import Testing
@testable import VJTestKitchen

struct ConciergeMarkdownTests {
    @Test func parsesHeadingsByLevelAndStripsMarker() {
        #expect(ConciergeMarkdown.parse("# Day 1") == [.heading(level: 1, text: "Day 1")])
        #expect(ConciergeMarkdown.parse("## Appetizer") == [.heading(level: 2, text: "Appetizer")])
        #expect(ConciergeMarkdown.parse("### Fresh Side") == [.heading(level: 3, text: "Fresh Side")])
    }

    @Test func stripsTrailingHashesFromHeadings() {
        #expect(ConciergeMarkdown.parse("## Day 1 ##") == [.heading(level: 2, text: "Day 1")])
    }

    @Test func requiresSpaceAfterHashSoItDoesNotFalseMatch() {
        // A "#3 pick" style line is not a heading.
        #expect(ConciergeMarkdown.parse("#3 pick") == [.paragraph(text: "#3 pick")])
    }

    @Test func parsesBulletListsWithDashAsteriskOrPlus() {
        #expect(ConciergeMarkdown.parse("- Tacos") == [.bullet(text: "Tacos")])
        #expect(ConciergeMarkdown.parse("* Salad") == [.bullet(text: "Salad")])
        #expect(ConciergeMarkdown.parse("+ Soup") == [.bullet(text: "Soup")])
    }

    @Test func parsesNumberedListsWithDotOrParen() {
        #expect(ConciergeMarkdown.parse("1. First") == [.ordered(number: 1, text: "First")])
        #expect(ConciergeMarkdown.parse("2) Second") == [.ordered(number: 2, text: "Second")])
        #expect(ConciergeMarkdown.parse("10. Tenth") == [.ordered(number: 10, text: "Tenth")])
    }

    @Test func keepsInlineMarkdownInsideBlocksForTheViewToRender() {
        // Inline **bold** is preserved in the block text (the view renders it).
        #expect(ConciergeMarkdown.parse("- **Beef Tacos** — 20 min") == [.bullet(text: "**Beef Tacos** — 20 min")])
    }

    @Test func joinsConsecutiveLinesIntoOneParagraphAndSplitsOnBlankLines() {
        let source = "Here's a plan\nfor tonight.\n\nEnjoy!"
        #expect(ConciergeMarkdown.parse(source) == [
            .paragraph(text: "Here's a plan for tonight."),
            .paragraph(text: "Enjoy!"),
        ])
    }

    @Test func parsesARealisticMenuIntoOrderedBlocks() {
        let source = """
        ## Day 1

        Here's a light start:

        - **Kale Salad** — fresh and quick
        - **Lemon Chicken** — 30 min

        ## Day 2
        1. **Veggie Stir-Fry**
        """
        #expect(ConciergeMarkdown.parse(source) == [
            .heading(level: 2, text: "Day 1"),
            .paragraph(text: "Here's a light start:"),
            .bullet(text: "**Kale Salad** — fresh and quick"),
            .bullet(text: "**Lemon Chicken** — 30 min"),
            .heading(level: 2, text: "Day 2"),
            .ordered(number: 1, text: "**Veggie Stir-Fry**"),
        ])
    }

    @Test func plainTextIsASingleParagraph() {
        #expect(ConciergeMarkdown.parse("Just a normal sentence.") == [.paragraph(text: "Just a normal sentence.")])
    }

    @Test func emptyInputYieldsNoBlocks() {
        #expect(ConciergeMarkdown.parse("") == [])
        #expect(ConciergeMarkdown.parse("\n\n   \n") == [])
    }
}
