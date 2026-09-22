import Foundation
import PDFKit
import Testing
import Domain
@testable import Features

/// Reading a statement whose amounts sit in their own column (§9.7).
///
/// The regression guard for the bug this feature was reported with: a real card statement
/// imported a fraction of its rows and filed a few charges as income, because the PDF's text
/// layer ran several transactions onto one line and stranded their amounts on the next ones.
@MainActor
@Suite("Columnar statement reading")
struct ColumnarStatementTests {

    /// The clock the rows resolve against. Inside the fixture's own year, so no date is
    /// refused for being implausibly far from now.
    private var context: StatementParseContext {
        StatementParseContext(now: Date(timeIntervalSince1970: 1_787_000_000))
    }

    /// Reads the fixture the way the importer does.
    /// - Returns: The recognised statement.
    private func recognised() async throws -> RecognizedStatement {
        try await StatementFileReader().read(.pdfData(ColumnarStatementFixture.pdfData()))
    }

    @Test("The text layer really does run the rows together, or this suite proves nothing")
    func fixtureReproducesTheLayout() throws {
        let document = try #require(PDFDocument(data: ColumnarStatementFixture.pdfData()))
        let page = try #require(document.page(at: 0))
        let text = page.string ?? ""

        // Two descriptors on one line is the defect; if a future PDFKit stops doing this the
        // fixture has stopped testing anything and should be rewritten, not deleted.
        let runsTogether = text
            .split(separator: "\n")
            .contains { $0.components(separatedBy: "Dockside").count > 2 }
        let amountsStranded = text
            .split(separator: "\n")
            .contains { $0.trimmingCharacters(in: .whitespaces) == "9.30" }

        #expect(runsTogether || amountsStranded, "the fixture must reproduce the broken layout")
    }

    @Test("Every printed row is recovered, not just the first of each run")
    func everyRowIsRecovered() async throws {
        let rows = StatementTextParser.rows(from: try await recognised(), context: context)

        #expect(
            rows.count == ColumnarStatementFixture.expectedRowCount,
            "expected \(ColumnarStatementFixture.expectedRowCount) rows, read \(rows.count)"
        )
    }

    @Test("Each row keeps its own amount rather than a neighbour's")
    func amountsStayWithTheirRow() async throws {
        let rows = StatementTextParser.rows(from: try await recognised(), context: context)

        for expected in ColumnarStatementFixture.rows {
            let matches = rows.filter { $0.amountCents == expected.cents }
            #expect(!matches.isEmpty, "no row carried \(expected.amount)")
        }
    }

    @Test("A charge is never filed as income because its sign drifted")
    func chargesAreNeverIncome() async throws {
        let rows = StatementTextParser.rows(from: try await recognised(), context: context)

        let charges = rows.filter { $0.kind == .charge }

        #expect(charges.count == ColumnarStatementFixture.chargeCount)
        // Every credit in the fixture was printed with a minus sign; nothing else may be one.
        for row in rows where row.kind != .charge {
            let printed = ColumnarStatementFixture.rows.first {
                $0.cents == row.amountCents
            }
            #expect(printed?.isCredit == true, "\(row.rawDescriptor) was not a credit")
        }
    }

    @Test("Two identical purchases on one day both survive the readers' merge")
    func keepsGenuineRepeats() async throws {
        let statement = try await recognised()
        let heuristic = await HeuristicStatementExtractor().extract(from: statement, context: context)

        let merged = StatementDocument().completed(with: heuristic)
        let prestoFares = merged.rows.count { $0.rawDescriptor.contains("PRESTO AUTO") }
        let mcdonalds = merged.rows.count { $0.amountCents == 654 }

        #expect(prestoFares == 2, "two 20.00 fares on one day are two fares")
        #expect(mcdonalds == 2, "two 6.54 meals on one day are two meals")
    }

    @Test("The card payment is recognised so it is never imported as income")
    func paymentIsClassified() async throws {
        let rows = StatementTextParser.rows(from: try await recognised(), context: context)

        #expect(rows.count { $0.kind == .payment } == 1)
    }
}
