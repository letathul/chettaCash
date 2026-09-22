import Foundation

/// One positioned piece of text lifted off a page, before it is any kind of row.
///
/// Carries only what deciding a line needs: where the piece sits and what it says. Declared
/// in Domain with plain `Double` coordinates rather than `CGRect` so the assembler stays
/// testable in the fast `swift test` loop, with no PDFKit, no Vision and no simulator.
public struct PositionedGlyph: Sendable, Equatable {
    /// The characters this piece holds, usually one.
    public var text: String
    /// The piece's left edge, in the page's own coordinate space.
    public var minX: Double
    /// The piece's right edge.
    public var maxX: Double
    /// The vertical middle of the piece, which is what decides its row.
    public var midY: Double

    /// Creates a positioned piece.
    /// - Parameters:
    ///   - text: The characters this piece holds.
    ///   - minX: The piece's left edge.
    ///   - maxX: The piece's right edge.
    ///   - midY: The vertical middle of the piece.
    public init(text: String, minX: Double, maxX: Double, midY: Double) {
        self.text = text
        self.minX = minX
        self.maxX = maxX
        self.midY = midY
    }
}

/// Rebuilds a page's visual rows from positioned text (§9.7).
///
/// **A PDF's text layer does not break lines the way the page looks.** A statement laid out in
/// columns routinely emits several transactions as one run of text with their amounts stacked
/// afterwards — one observed page put fourteen transactions on a single line, which
/// ``StatementTextParser`` reads as one row and drops the other thirteen. The characters are
/// exact; only the line breaks are wrong, and the page's own geometry says where they belong.
///
/// So rows are decided by where text *sits*, not by where the file happens to put a newline:
/// pieces sharing a baseline are one row, ordered left to right.
///
/// Pure and synchronous, like every other reader in this folder: the geometry comes from
/// PDFKit or Vision at the edge, and every decision made from it is tested without either.
public enum StatementLineAssembler {

    /// How far apart two baselines may sit and still count as one row, in points.
    ///
    /// Four, which is under a single line's leading at any size a statement prints and wide
    /// enough to absorb the sub-point drift between a row's date and its amount.
    public static let defaultTolerance: Double = 4

    /// How wide a horizontal jump has to be to read as a column break, in points.
    ///
    /// A gap this wide gets two spaces rather than one. Nothing downstream splits on it
    /// today — ``StatementTextParser`` reads the amount off the end of the line either way —
    /// but it keeps a column layout legible in the transcript the on-device model is shown,
    /// which is the difference between a table and a run-on sentence.
    public static let columnGap: Double = 6

    /// Rebuilds a page's rows.
    ///
    /// - Parameters:
    ///   - glyphs: Every positioned piece on the page, in any order.
    ///   - tolerance: How far apart two baselines may sit and still be one row.
    /// - Returns: The rows, top to bottom, each already trimmed. Empty rows are dropped.
    public static func lines(
        from glyphs: [PositionedGlyph],
        tolerance: Double = defaultTolerance
    ) -> [String] {
        rows(from: glyphs, tolerance: tolerance).map(\.text)
    }

    /// One rebuilt row and where it sat.
    public struct AssembledLine: Sendable, Equatable {
        /// The row's text, left to right.
        public var text: String
        /// The baseline the row was grouped on.
        public var midY: Double

        /// Creates a rebuilt row.
        /// - Parameters:
        ///   - text: The row's text.
        ///   - midY: The baseline the row was grouped on.
        public init(text: String, midY: Double) {
            self.text = text
            self.midY = midY
        }
    }

    /// Rebuilds a page's rows, keeping each one's position.
    ///
    /// **Bucketed, not chained.** Grouping by "the first row within tolerance" lets a page
    /// drift: each near-miss widens the group's reach by another fraction of a point until a
    /// row swallows its neighbour's tail. Rounding each baseline to a fixed grid cannot drift,
    /// because a piece's group never depends on which pieces were read before it.
    ///
    /// - Parameters:
    ///   - glyphs: Every positioned piece on the page, in any order.
    ///   - tolerance: The grid baselines are rounded to.
    /// - Returns: The rows, top to bottom.
    public static func rows(
        from glyphs: [PositionedGlyph],
        tolerance: Double = defaultTolerance
    ) -> [AssembledLine] {
        guard tolerance > 0 else { return [] }

        var buckets: [Int: [PositionedGlyph]] = [:]
        for glyph in glyphs where !glyph.text.isEmpty {
            buckets[Int((glyph.midY / tolerance).rounded()), default: []].append(glyph)
        }

        // Descending, because a PDF's origin is the *bottom* left: the largest y is the top
        // of the page, and a statement's rows must arrive in the order they were printed.
        return buckets.keys.sorted(by: >).compactMap { key in
            guard let bucket = buckets[key] else { return nil }
            let text = joined(bucket.sorted { $0.minX < $1.minX })
            guard !text.isEmpty else { return nil }
            return AssembledLine(text: text, midY: Double(key) * tolerance)
        }
    }

    /// Joins one row's pieces left to right, spacing them as the page did.
    ///
    /// A piece that begins where the last one ended is joined outright — that is one word
    /// split across several glyphs, and inserting a space would break every merchant name.
    /// A small gap becomes a space, and a column-width gap becomes two.
    ///
    /// - Parameter glyphs: The row's pieces, already ordered left to right.
    /// - Returns: The row's text, trimmed.
    static func joined(_ glyphs: [PositionedGlyph]) -> String {
        var text = ""
        var previousMaxX: Double?

        for glyph in glyphs {
            if let previousMaxX {
                let gap = glyph.minX - previousMaxX
                if gap >= columnGap {
                    text += "  "
                } else if gap > 0 || glyph.text.first == " " {
                    text += " "
                }
            }
            text += glyph.text
            previousMaxX = max(glyph.maxX, previousMaxX ?? glyph.maxX)
        }
        // Collapsed rather than merely trimmed: a glyph that already carried a space would
        // otherwise double it, and a run of spaces inside a descriptor is not information.
        return collapsed(text)
    }

    /// Reduces every run of whitespace to at most two spaces and trims the ends.
    /// - Parameter text: The joined row.
    /// - Returns: The tidied row.
    static func collapsed(_ text: String) -> String {
        var result = ""
        var spaces = 0
        for character in text {
            guard character == " " || character == "\t" || character == "\u{00A0}" else {
                result.append(character)
                spaces = 0
                continue
            }
            spaces += 1
            if spaces <= 2 { result.append(" ") }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
