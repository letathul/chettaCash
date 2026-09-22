import Foundation
import Testing
@testable import Domain

/// Rebuilding a statement page's visual rows from positioned text (§9.7).
///
/// The shapes here are taken from a real Rogers Bank Mastercard PDF, whose text layer put
/// three transactions on one line on page 1 and fourteen on one line on page 3.
@Suite("Statement line assembly")
struct StatementLineAssemblerTests {

    /// Lays out words on one baseline, a fixed width apart.
    /// - Parameters:
    ///   - words: The words, left to right.
    ///   - midY: The baseline to place them on.
    ///   - startX: Where the first word begins.
    /// - Returns: The glyphs.
    private func row(_ words: [String], midY: Double, startX: Double = 0) -> [PositionedGlyph] {
        var glyphs: [PositionedGlyph] = []
        var left = startX
        for word in words {
            let width = Double(word.count) * 5
            glyphs.append(PositionedGlyph(text: word, minX: left, maxX: left + width, midY: midY))
            // Two points of gap: a word space, well under the column threshold.
            left += width + 2
        }
        return glyphs
    }

    @Test("Three transactions the text layer ran together come back as three rows")
    func splitsRunTogetherTransactions() {
        // Page 1 of the sample: the three descriptors sat on one baseline in the file's
        // reading order, with their amounts stacked on the lines below.
        let glyphs =
            row(["Jul", "16", "Jul", "17", "Dockside", "Restaurant"], midY: 300)
            + row(["15.25"], midY: 300, startX: 400)
            + row(["Jul", "16", "Jul", "17", "Dockside", "Restaurant"], midY: 288)
            + row(["9.30"], midY: 288, startX: 400)
            + row(["Jul", "16", "Jul", "17", "PETRO-CANADA", "30584"], midY: 276)
            + row(["71.80"], midY: 276, startX: 400)

        let lines = StatementLineAssembler.lines(from: glyphs)

        #expect(lines.count == 3, "each baseline is one transaction")
        #expect(lines[0].hasSuffix("15.25"), "the amount stays on its own row")
        #expect(lines[1].hasSuffix("9.30"))
        #expect(lines[2].hasSuffix("71.80"))
    }

    @Test("Rows come back top to bottom, not in the file's own order")
    func ordersRowsDownThePage() {
        // Deliberately supplied bottom-up: a PDF's origin is the bottom left, so the
        // largest y is the top of the page.
        let glyphs = row(["third"], midY: 100) + row(["first"], midY: 300) + row(["second"], midY: 200)

        #expect(StatementLineAssembler.lines(from: glyphs) == ["first", "second", "third"])
    }

    @Test("Baselines a fraction of a point apart are one row")
    func toleratesBaselineDrift() {
        let glyphs = [
            PositionedGlyph(text: "Jul 16", minX: 0, maxX: 30, midY: 300),
            PositionedGlyph(text: "MERCHANT", minX: 32, maxX: 90, midY: 300.6),
            PositionedGlyph(text: "13.89", minX: 200, maxX: 230, midY: 299.4)
        ]

        #expect(StatementLineAssembler.lines(from: glyphs) == ["Jul 16 MERCHANT  13.89"])
    }

    @Test("A drifting page does not chain one row into the next")
    func doesNotChainNeighbouringRows() {
        // Each baseline sits three points below the last — inside the tolerance pairwise,
        // so a "first row within tolerance" grouping would collapse all four into one.
        let glyphs = (0..<4).flatMap { index in
            row(["row\(index)"], midY: 300 - Double(index) * 3)
        }

        #expect(StatementLineAssembler.lines(from: glyphs).count >= 3, "rows stay separate")
    }

    @Test("Glyphs of one word are joined without a space")
    func joinsGlyphsOfOneWord() {
        // How PDFKit actually reports a page: one glyph per character, edge to edge.
        let glyphs = "COSTCO".enumerated().map { index, character in
            PositionedGlyph(
                text: String(character),
                minX: Double(index) * 6, maxX: Double(index) * 6 + 6, midY: 100
            )
        }

        #expect(StatementLineAssembler.lines(from: glyphs) == ["COSTCO"])
    }

    @Test("A column-width gap is kept, so the amount reads as its own cell")
    func keepsColumnGaps() {
        let glyphs = [
            PositionedGlyph(text: "MERCHANT", minX: 0, maxX: 60, midY: 100),
            PositionedGlyph(text: "42.10", minX: 300, maxX: 330, midY: 100)
        ]

        let lines = StatementLineAssembler.lines(from: glyphs)

        #expect(lines == ["MERCHANT  42.10"])
    }

    @Test("A minus sign survives, because it is what decides income from expense")
    func keepsTheSign() {
        let glyphs = [
            PositionedGlyph(text: "CashBack / Remises Rebate ON", minX: 0, maxX: 160, midY: 100),
            PositionedGlyph(text: "-93.42", minX: 300, maxX: 336, midY: 100)
        ]

        let line = StatementLineAssembler.lines(from: glyphs).first

        #expect(line?.hasSuffix("-93.42") == true)
    }

    @Test("An empty page yields no rows")
    func handlesAnEmptyPage() {
        #expect(StatementLineAssembler.lines(from: []).isEmpty)
    }

    @Test("Blank glyphs never become a row of their own")
    func dropsBlankRows() {
        let glyphs = [
            PositionedGlyph(text: "   ", minX: 0, maxX: 10, midY: 200),
            PositionedGlyph(text: "REAL", minX: 0, maxX: 30, midY: 100)
        ]

        #expect(StatementLineAssembler.lines(from: glyphs) == ["REAL"])
    }
}
