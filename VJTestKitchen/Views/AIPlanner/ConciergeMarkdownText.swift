import SwiftUI

/// Renders the concierge's block markdown (headers, bullet/numbered lists,
/// paragraphs) as native SwiftUI. Block structure comes from
/// `ConciergeMarkdown.parse`; inline formatting (**bold**, *italic*, `code`,
/// links) within each block is handled by `AttributedString(markdown:)`, so the
/// user never sees raw `##` / `-` characters again.
struct ConciergeMarkdownText: View {
    let content: String

    private var blocks: [ConciergeMarkdown.Block] { ConciergeMarkdown.parse(content) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .heading(level, text):
                    inlineText(text)
                        .font(headingFont(level))
                        .padding(.top, 2)
                case let .bullet(text):
                    listRow(marker: "•", text: text)
                case let .ordered(number, text):
                    listRow(marker: "\(number).", text: text)
                case let .paragraph(text):
                    inlineText(text)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A list row: a fixed-width marker aligned with a hanging indent so wrapped
    /// lines line up under the text, not the bullet.
    private func listRow(marker: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(marker)
                .foregroundStyle(Color.brandPrimary)
                .frame(minWidth: 14, alignment: .leading)
            inlineText(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Renders a block's text with inline markdown parsed; falls back to the raw
    /// string if it somehow doesn't parse.
    private func inlineText(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(text)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title3.bold()
        case 2: return .headline
        default: return .subheadline.bold()
        }
    }
}
