import Foundation
import PDFKit
import UIKit
import Domain

/// What the user picked to import.
///
/// The data and image cases exist so a test never needs a file on disk.
enum StatementFileSource: Sendable {
    /// A file chosen through the document picker.
    case url(URL)
    /// PDF bytes already in hand.
    case pdfData(Data)
    /// A photograph of a statement.
    case image(UIImage)
    /// A delimited export's text, already decoded from the file's bytes.
    ///
    /// Text rather than bytes because the encoding question is settled at the file boundary
    /// by ``StatementFileReader/text(at:)`` — and because a test then needs no file on disk,
    /// which is why the data and image cases exist too.
    case csv(String)
}

/// Why a statement file could not be read.
enum StatementImportError: Error, Equatable {
    /// The file is encrypted, as emailed bank statements routinely are.
    case passwordProtected
    /// The file is not a PDF or an image this device can open.
    case unreadableFile
    /// The file opened but held no pages.
    case noPages
    /// The system refused access to the picked file.
    case accessDenied
    /// Nothing legible was found on any page.
    case noTextFound
    /// The file is a delimited export whose bytes decode to no known text encoding.
    case unreadableCSV
    /// The export was read, but no header column could be matched to a date.
    case noColumnsFound
}

/// Turns a picked PDF or image into recognised text (§9.7).
///
/// Abstracted so the import chain can be tested without a file or a simulator.
protocol StatementTextReading: Sendable {
    /// Reads a statement's text.
    /// - Parameter source: What the user picked.
    /// - Returns: The recognised text, page by page.
    /// - Throws: ``StatementImportError`` when the file cannot be read.
    func read(_ source: StatementFileSource) async throws -> RecognizedStatement
}

/// Reads a statement, preferring the file's own text layer over recognition.
///
/// **The text layer is taken whenever there is one**, and almost every statement a bank
/// emails has one. It gives the exact characters, where recognition reliably confuses `5`
/// for `S` and `0` for `O` in a monospaced amount column — and unlike a receipt photo,
/// there is no second reading to cross-check a misread figure against. It is also far
/// faster, because nothing has to be rasterised.
struct StatementFileReader: StatementTextReading {

    /// Pages past this are ignored, bounding memory and model time on a long statement.
    static let pageLimit = 20

    /// How many characters a page must yield before its text layer is trusted.
    ///
    /// A scanned PDF often carries a few stray characters — a header stamp, a watermark —
    /// which would otherwise be mistaken for a real text layer and leave every row unread.
    static let minimumEmbeddedCharacters = 40

    /// How much to magnify a page before recognising it.
    static let renderScale: CGFloat = 2

    /// Reads text off an image when a page has no text layer.
    let recognizer: any ReceiptRecognizing

    /// Creates the reader.
    /// - Parameter recognizer: Reads text off an image.
    init(recognizer: any ReceiptRecognizing = VisionReceiptRecognizer()) {
        self.recognizer = recognizer
    }

    /// Reads a statement's text.
    /// - Parameter source: What the user picked.
    /// - Returns: The recognised text, page by page.
    /// - Throws: ``StatementImportError`` when the file cannot be read.
    func read(_ source: StatementFileSource) async throws -> RecognizedStatement {
        switch source {
        case .url(let url):
            return try await readFile(at: url)
        case .pdfData(let data):
            guard let document = PDFDocument(data: data) else {
                throw StatementImportError.unreadableFile
            }
            return try await read(document)
        case .image(let image):
            return RecognizedStatement(pages: [try await recognizer.recognize(image)])
        case .csv:
            // Unreachable by construction: ``StatementImporter`` diverts a delimited export
            // before it reaches a text reader, because there is nothing to recognise in one.
            // Reported rather than trapped, so a future caller that gets here is told off
            // instead of crashing the app.
            throw StatementImportError.unreadableCSV
        }
    }

    /// The encodings a bank export is tried against, in order.
    ///
    /// UTF-8 first because it is now near-universal; UTF-16 next because Excel on Windows
    /// writes it when a sheet is saved as "Unicode Text"; Latin-1 last because it is the
    /// legacy default and, decoding any byte sequence at all, it must never come first or
    /// it would silently mangle every accented merchant name in a UTF-8 file.
    static let encodings: [String.Encoding] = [.utf8, .utf16, .isoLatin1]

    /// Reads a delimited export's text off disk.
    ///
    /// The security-scoped resource must be claimed before the bytes can be read, for the
    /// reason ``readFile(at:)`` gives: without it the file reads as empty with no error at
    /// all, which looks exactly like an empty statement.
    ///
    /// - Parameter url: The picked file.
    /// - Returns: The file's text.
    /// - Throws: ``StatementImportError/unreadableCSV`` when no encoding decodes it.
    static func text(at url: URL) throws -> String {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            throw StatementImportError.accessDenied
        }
        for encoding in encodings {
            if let text = String(data: data, encoding: encoding), !text.isEmpty { return text }
        }
        throw StatementImportError.unreadableCSV
    }

    /// Reads a file the user picked.
    ///
    /// The security-scoped resource must be claimed before the bytes can be read: without
    /// it the file reads as empty with no error at all, which looks exactly like an
    /// unreadable statement.
    ///
    /// - Parameter url: The picked file.
    /// - Returns: The recognised text.
    /// - Throws: ``StatementImportError`` when the file cannot be read.
    private func readFile(at url: URL) async throws -> RecognizedStatement {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }

        if let document = PDFDocument(url: url) {
            return try await read(document)
        }
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
            throw StatementImportError.unreadableFile
        }
        return RecognizedStatement(pages: [try await recognizer.recognize(image)])
    }

    /// Reads every page of a PDF.
    /// - Parameter document: The opened document.
    /// - Returns: The recognised text, page by page.
    /// - Throws: ``StatementImportError`` when the document cannot be read.
    private func read(_ document: PDFDocument) async throws -> RecognizedStatement {
        // Banks routinely encrypt a statement with the cardholder's date of birth or the
        // card's last four digits. Saying so is the difference between a fixable problem
        // and an inexplicable failure.
        guard !document.isLocked else { throw StatementImportError.passwordProtected }
        guard document.pageCount > 0 else { throw StatementImportError.noPages }

        let pages = (0..<min(document.pageCount, Self.pageLimit)).compactMap { document.page(at: $0) }
        if pages.contains(where: { Self.hasUsableText($0.string ?? "") }) {
            return RecognizedStatement(
                pages: pages.map(Self.recognized(from:)), usedEmbeddedText: true
            )
        }

        var recognised: [RecognizedReceipt] = []
        for page in pages {
            // One unreadable page must not cost the whole statement.
            guard let image = Self.render(page),
                  let text = try? await recognizer.recognize(image) else { continue }
            recognised.append(text)
        }
        guard !recognised.isEmpty else { throw StatementImportError.noTextFound }
        return RecognizedStatement(pages: recognised)
    }

    /// Whether a page's embedded text is worth using.
    /// - Parameter text: The page's text layer.
    /// - Returns: `true` when it holds enough to read rows from.
    static func hasUsableText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= minimumEmbeddedCharacters && trimmed.contains(where: \.isNumber)
    }

    /// Reads a page's text layer back into the rows the page actually shows.
    ///
    /// **A PDF's text layer does not break lines the way the page looks.** Taking
    /// `PDFPage.string` wholesale is what cost this feature most of its rows: a statement
    /// laid out in columns emits several transactions as one run of text with their amounts
    /// stacked afterwards, and one observed page put *fourteen* transactions on a single
    /// line — which ``StatementTextParser`` reads as one row, discarding the other thirteen
    /// for having no leading date.
    ///
    /// So the rows are rebuilt from the page's own geometry. `selectionsByLine()` is asked
    /// for the page's text runs, each of which carries exact characters *and* the rectangle
    /// it occupies, and ``StatementLineAssembler`` regroups them by baseline. That is also
    /// why the runs are not read through `characterBounds(at:)`: on a real statement those
    /// indices drift out of step with `PDFPage.string`, so characters leak between rows.
    ///
    /// - Parameter page: The page to read.
    /// - Returns: The recognised page, one line per printed row.
    static func recognized(from page: PDFPage) -> RecognizedReceipt {
        let bounds = page.bounds(for: .mediaBox)
        guard let whole = page.selection(for: bounds) else {
            return recognized(fromEmbedded: page.string ?? "")
        }

        let glyphs = whole.selectionsByLine().compactMap { run -> PositionedGlyph? in
            let text = (run.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let frame = run.bounds(for: page)
            guard frame.midY.isFinite, frame.minX.isFinite, frame.maxX.isFinite else { return nil }
            return PositionedGlyph(
                text: text, minX: frame.minX, maxX: frame.maxX, midY: frame.midY
            )
        }

        let assembled = StatementLineAssembler.rows(from: glyphs)
        // A page whose runs carry no usable geometry would assemble to nothing; its reading
        // order is still better than no page at all.
        guard !assembled.isEmpty else { return recognized(fromEmbedded: page.string ?? "") }

        let height = bounds.height
        let lines = assembled.map { line in
            RecognizedLine(
                // A PDF's origin is the bottom left, so a large y is near the top — which is
                // the opposite of the top-down fraction every reader downstream expects.
                text: line.text,
                topFraction: height > 0 ? min(1, max(0, 1 - line.midY / height)) : 0
            )
        }
        return RecognizedReceipt(lines: lines)
    }

    /// Wraps a page's text layer in the shape the readers expect, line breaks and all.
    ///
    /// The fallback for a page ``recognized(from:)`` could get no geometry out of. It keeps
    /// the file's own reading order, which is wrong about where rows end but right about
    /// what the page says.
    ///
    /// - Parameter text: The page's text layer.
    /// - Returns: The recognised page.
    static func recognized(fromEmbedded text: String) -> RecognizedReceipt {
        let rows = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let lines = rows.enumerated().map { index, row in
            RecognizedLine(
                text: row.trimmingCharacters(in: .whitespaces),
                topFraction: rows.count > 1 ? Double(index) / Double(rows.count - 1) : 0
            )
        }
        return RecognizedReceipt(lines: lines, transcript: text)
    }

    /// Rasterises a page for recognition.
    /// - Parameter page: The page to render.
    /// - Returns: The image, or `nil` when the page has no drawable bounds.
    static func render(_ page: PDFPage) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let size = CGSize(width: bounds.width * renderScale, height: bounds.height * renderScale)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: Self.renderScale, y: -Self.renderScale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }
}
