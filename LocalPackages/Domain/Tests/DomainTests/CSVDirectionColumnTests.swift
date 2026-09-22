import Foundation
import Testing
@testable import Domain

/// Reading an export that names each row's direction in words (§9.7).
///
/// The layout `CSVSignConvention` cannot help with: every figure is positive, so there is no
/// sign to infer a convention from, and the file inverts wholesale under a wrong guess.
@Suite("CSV direction column")
struct CSVDirectionColumnTests {

    /// A fixed moment the dates resolve against.
    private let now = Date(timeIntervalSince1970: 1_787_000_000)

    @Test("Dr and Cr are read as debit and credit")
    func readsDirectionWords() {
        #expect(CSVSignConvention.isCredit(indicator: "Cr") == true)
        #expect(CSVSignConvention.isCredit(indicator: "DR") == false)
        #expect(CSVSignConvention.isCredit(indicator: " credit ") == true)
        #expect(CSVSignConvention.isCredit(indicator: "Withdrawal") == false)
    }

    @Test("A cell saying neither is left for the sign convention to answer")
    func unknownWordsAnswerNothing() {
        #expect(CSVSignConvention.isCredit(indicator: "") == nil)
        #expect(CSVSignConvention.isCredit(indicator: "misc") == nil)
        #expect(CSVSignConvention.isCredit(indicator: "Dr Pepper") == nil, "not a whole token")
    }

    @Test("A file of unsigned amounts reads correctly from its direction column")
    func unsignedFileReadsFromIndicator() {
        // Without the indicator every figure is positive, no line mentions a payment, and the
        // inference falls back to "negative is a charge" — which files every purchase as a
        // refund and every refund as a purchase.
        let csv = """
            Date,Description,Type,Amount
            07/15/2026,COSTCO WHOLESALE,DR,42.10
            07/16/2026,REFUND FROM SHOP,CR,15.00
            """
        let columns = CSVHeaderMatcher.columns(for: ["Date", "Description", "Type", "Amount"])

        let document = CSVStatementParser.document(
            csv: csv, columns: columns, context: StatementParseContext(now: now)
        )

        #expect(columns.directionIndicator == "Type")
        #expect(document.rows.count == 2)
        #expect(document.rows.first { $0.amountCents == 4_210 }?.kind == .charge)
        #expect(document.rows.first { $0.amountCents == 1_500 }?.kind == .refund)
    }

    @Test("A stated sign convention beats one inferred from the figures")
    func statedConventionWins() {
        // Every figure positive and no payment line, so inference would say "negative is a
        // charge" and read both rows as credits.
        let csv = """
            Date,Description,Amount
            07/15/2026,COSTCO WHOLESALE,42.10
            07/16/2026,SHELL,77.24
            """
        var columns = CSVStatementColumns(descriptor: "Description", amount: .single("Amount"))
        columns.transactionDate = "Date"
        columns.signConvention = .positiveIsCharge

        let document = CSVStatementParser.document(
            csv: csv, columns: columns, context: StatementParseContext(now: now)
        )

        #expect(document.rows.allSatisfy { $0.kind == .charge })
    }

    @Test("The direction column is not mistaken for the amount column")
    func indicatorDoesNotStealTheAmount() {
        let columns = CSVHeaderMatcher.columns(for: ["Date", "Details", "Dr/Cr", "Amount"])

        #expect(columns.directionIndicator == "Dr/Cr")
        #expect(columns.amount == .single("Amount"))
    }
}
