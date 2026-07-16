import Foundation
import FoundationModels
import Vision
import PDFKit
import CoreGraphics

/// The structured recipe the on-device model extracts from a photo's text.
/// `@Generable` so `LanguageModelSession.respond(generating:)` fills it in
/// directly — no brittle JSON-string parsing. Integer fields use 0 as "unknown"
/// (the `@Generable` schema is happier with a concrete `Int` than an optional).
@Generable
struct ScannedRecipe: Equatable, Sendable {
    @Guide(description: "The recipe's title or dish name.")
    var title: String
    @Guide(description: "A one or two sentence description of the dish. Empty string if there isn't one.")
    var summary: String
    @Guide(description: "Each ingredient as its own line, exactly as written, e.g. '2 cups all-purpose flour'.")
    var ingredients: [String]
    @Guide(description: "The cooking steps, as a single block of text with steps separated by newlines.")
    var instructions: String
    @Guide(description: "Total time in minutes (prep plus cook). Use 0 if the photo doesn't say.")
    var totalMinutes: Int
    @Guide(description: "How many servings the recipe makes. Use 0 if the photo doesn't say.")
    var servings: Int

    // Explicit memberwise init: the `@Generable` macro adds its own
    // `init(_:)`, which suppresses the synthesized memberwise initializer —
    // this keeps `ScannedRecipe(...)` constructible in tests and `apply(_:)`.
    init(title: String, summary: String, ingredients: [String], instructions: String, totalMinutes: Int, servings: Int) {
        self.title = title
        self.summary = summary
        self.ingredients = ingredients
        self.instructions = instructions
        self.totalMinutes = totalMinutes
        self.servings = servings
    }
}

/// Turns a photo *or PDF/document* of a recipe (a cookbook page, a recipe card,
/// a screenshot, an exported PDF) into a structured `ScannedRecipe` the recipe
/// form can prefill — entirely on-device:
///
/// 1. **Text extraction** — a photo is OCR'd with **Vision**
///    (`RecognizeTextRequest`); a PDF's embedded text layer is read with
///    **PDFKit**, falling back to rasterizing each page with **Core Graphics**
///    and OCRing it (for scanned/image-only PDFs).
/// 2. **Apple Intelligence** (`SystemLanguageModel`) structures that text into
///    title / ingredients / steps / times via `@Generable`.
///
/// Every step is on-device and cross-platform (Vision + FoundationModels +
/// PDFKit ship on iOS and macOS 26+; the rasterization is pure Core Graphics,
/// no UIKit/AppKit — same ethos as `AvatarImageProcessor`). The two text-
/// extraction calls are injectable (`recognizeText` / `recognizeDocumentText`)
/// so the pieces around them stay unit-testable without a real image, PDF, or
/// model.
struct RecipePhotoImportService {
    /// OCR step for a single image: image bytes → recognized text. Defaults to
    /// Vision; overridable in tests.
    var recognizeText: @Sendable (Data) async throws -> String = { try await RecipePhotoImportService.visionRecognizeText($0) }

    /// Text-extraction step for a document (PDF): document bytes → text.
    /// Defaults to PDFKit-with-OCR-fallback; overridable in tests.
    var recognizeDocumentText: @Sendable (Data) async throws -> String = { try await RecipePhotoImportService.extractDocumentText($0) }

    /// Non-`nil` when on-device extraction can't run here — reuses the
    /// concierge's availability copy so the two features speak with one voice.
    var unavailableReason: String? {
        AppleIntelligenceAIService.unavailableReason(for: SystemLanguageModel.default.availability)
    }

    /// Photo path: OCR the image, then structure it.
    func importRecipe(from imageData: Data) async throws -> ScannedRecipe {
        try await structure(text: recognizeText(imageData))
    }

    /// Document path: read the PDF's text (or OCR its rendered pages), then
    /// structure it — same on-device structuring as the photo path.
    func importRecipe(fromDocument documentData: Data) async throws -> ScannedRecipe {
        try await structure(text: recognizeDocumentText(documentData))
    }

    /// Shared tail of both paths: guard availability + non-empty text, then let
    /// the on-device model fill in a `ScannedRecipe`.
    private func structure(text: String) async throws -> ScannedRecipe {
        if let reason = unavailableReason {
            throw AppleIntelligenceUnavailableError(message: reason)
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecipeScanError.noTextFound
        }
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: Self.prompt(for: text),
            generating: ScannedRecipe.self
        )
        return response.content
    }

    // MARK: - Vision OCR

    /// Default OCR implementation: runs an accurate, language-corrected text
    /// recognition pass over the image bytes and joins the recognized lines.
    static func visionRecognizeText(_ imageData: Data) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: imageData)
        return joinTranscripts(observations)
    }

    /// OCR a single already-decoded page image (CGImage). Shared by the PDF
    /// rasterization fallback.
    static func visionRecognizeText(cgImage: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: cgImage)
        return joinTranscripts(observations)
    }

    private static func joinTranscripts(_ observations: [RecognizedTextObservation]) -> String {
        observations
            .map(\.transcript)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    // MARK: - PDF / document text extraction

    /// How many pages of a document to read at most. A recipe rarely spans more
    /// than a couple of pages, and it bounds OCR work + the model's context.
    static let maxDocumentPages = 6

    /// Below this many non-whitespace characters, a PDF's embedded text layer is
    /// treated as "basically empty" (a scanned/image-only PDF) and we fall back
    /// to rendering + OCRing the pages.
    static let minEmbeddedTextChars = 40

    /// Extract text from a PDF: prefer the embedded text layer (fast, exact for
    /// digital PDFs); if it's missing/sparse, rasterize each page and OCR it.
    static func extractDocumentText(_ data: Data) async throws -> String {
        guard let document = PDFDocument(data: data) else {
            throw RecipeScanError.unsupportedDocument
        }

        let embedded = embeddedText(from: document)
        if embedded.trimmingCharacters(in: .whitespacesAndNewlines).count >= minEmbeddedTextChars {
            return embedded
        }

        // Scanned PDF (no usable text layer): render pages and OCR them.
        var ocrPages: [String] = []
        for index in 0..<min(document.pageCount, maxDocumentPages) {
            guard let page = document.page(at: index),
                  let image = rasterize(page) else { continue }
            let text = try await visionRecognizeText(cgImage: image)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ocrPages.append(text)
            }
        }
        return ocrPages.joined(separator: "\n")
    }

    /// Concatenate the first few pages' embedded text.
    private static func embeddedText(from document: PDFDocument) -> String {
        (0..<min(document.pageCount, maxDocumentPages))
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
    }

    /// Render a PDF page to a `CGImage` at ~2x for OCR clarity — pure Core
    /// Graphics so it works identically on iOS and macOS with no platform image
    /// type. Returns nil if a bitmap context can't be made.
    private static func rasterize(_ page: PDFPage, scale: CGFloat = 2) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        // White background (a transparent one OCRs poorly), then draw the page
        // scaled to fill.
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    // MARK: - Pure helpers (unit-tested)

    static let instructions = """
    You extract a single recipe from raw text that was read off a photo or PDF \
    of a cookbook page, recipe card, or screenshot. The text may have OCR noise, \
    odd line breaks, or page furniture (headers, page numbers) — ignore anything \
    that isn't part of the recipe. Only use information present in the text; \
    never invent ingredients, steps, times, or servings. If a field isn't in \
    the text, leave it empty (or 0 for the numeric fields).
    """

    static func prompt(for ocrText: String) -> String {
        """
        Extract the recipe from this text:

        \(ocrText)
        """
    }
}

enum RecipeScanError: LocalizedError {
    case noTextFound
    case unsupportedDocument

    var errorDescription: String? {
        switch self {
        case .noTextFound:
            return "Couldn't find any recipe text in that file. Try a clearer photo, or a PDF with selectable text."
        case .unsupportedDocument:
            return "That file couldn't be opened as a PDF. Try exporting the recipe as a PDF and importing again."
        }
    }
}
