import Foundation

/// Block-level markdown parsing for the Kitchen Concierge chat.
///
/// SwiftUI's `Text(LocalizedStringKey(...))` only renders INLINE markdown
/// (**bold**, *italic*, `code`, links) — it leaves block syntax like `## `
/// headers and `- ` bullet lists as raw characters on screen. The concierge
/// replies in exactly that block markdown (headers per day/course, bullet and
/// numbered lists for menus), so we parse the block structure ourselves here
/// (pure + unit-tested) and let the view render each block, delegating the
/// inline formatting inside a block back to AttributedString(markdown:).
enum ConciergeMarkdown {
    /// One block of rendered markdown. `text` is the block's content with its
    /// leading marker (`## `, `- `, `1. `) stripped — inline markdown within it
    /// is preserved for the view to render.
    enum Block: Equatable {
        case heading(level: Int, text: String)
        case bullet(text: String)
        case ordered(number: Int, text: String)
        case paragraph(text: String)
    }

    /// Parses `source` into an ordered list of blocks. Consecutive non-blank,
    /// non-structural lines are joined into a single paragraph; blank lines
    /// separate blocks. Robust to the loose markdown an LLM emits.
    static func parse(_ source: String) -> [Block] {
        var blocks: [Block] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            let joined = paragraphLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { blocks.append(.paragraph(text: joined)) }
            paragraphLines.removeAll()
        }

        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                continue
            }
            if let heading = parseHeading(line) {
                flushParagraph()
                blocks.append(heading)
                continue
            }
            if let bullet = parseBullet(line) {
                flushParagraph()
                blocks.append(bullet)
                continue
            }
            if let ordered = parseOrdered(line) {
                flushParagraph()
                blocks.append(ordered)
                continue
            }
            paragraphLines.append(line)
        }
        flushParagraph()
        return blocks
    }

    // MARK: - Line parsers

    /// `#`…`######` followed by a space. Levels are clamped to 1...6.
    private static func parseHeading(_ line: String) -> Block? {
        var hashes = 0
        for ch in line {
            if ch == "#" { hashes += 1 } else { break }
        }
        guard hashes >= 1, hashes <= 6 else { return nil }
        let rest = line.dropFirst(hashes)
        guard let first = rest.first, first == " " else { return nil }
        let text = rest.drop(while: { $0 == " " })
        // Strip a trailing run of hashes ("## Day 1 ##" → "Day 1"), a common style.
        let cleaned = String(text).replacingOccurrences(of: #"\s*#+\s*$"#, with: "", options: .regularExpression)
        return .heading(level: hashes, text: cleaned.trimmingCharacters(in: .whitespaces))
    }

    /// `- ` / `* ` / `+ ` bullet marker.
    private static func parseBullet(_ line: String) -> Block? {
        guard let marker = line.first, marker == "-" || marker == "*" || marker == "+" else { return nil }
        let rest = line.dropFirst()
        guard let space = rest.first, space == " " else { return nil }
        let text = rest.drop(while: { $0 == " " })
        guard !text.isEmpty else { return nil }
        return .bullet(text: String(text))
    }

    /// `1.` / `2)` ordered-list marker.
    private static func parseOrdered(_ line: String) -> Block? {
        var digits = ""
        var index = line.startIndex
        while index < line.endIndex, line[index].isNumber {
            digits.append(line[index])
            index = line.index(after: index)
        }
        guard !digits.isEmpty, let number = Int(digits), index < line.endIndex else { return nil }
        let delimiter = line[index]
        guard delimiter == "." || delimiter == ")" else { return nil }
        let afterDelimiter = line[line.index(after: index)...]
        guard let space = afterDelimiter.first, space == " " else { return nil }
        let text = afterDelimiter.drop(while: { $0 == " " })
        guard !text.isEmpty else { return nil }
        return .ordered(number: number, text: String(text))
    }
}
