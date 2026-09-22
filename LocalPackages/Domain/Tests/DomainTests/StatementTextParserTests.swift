import Foundation
import Testing
@testable import Domain

/// Reading rows off a statement's text without a model (§9.7).
@Suite("Reading statement rows")
struct StatementTextParserTests {

    /// The clock and calendar every date in this suite resolves against.
    private let context = StatementParseContext(now: Fixtures.now, calendar: Fixtures.utc)

    /// Parses one line.
    /// - Parameter text: The line's text.
    /// - Returns: The row, if the line held one.
    private func row(_ text: String) -> StatementRow? {
        StatementTextParser.row(from: text, context: context)
    }

    @Test("A date, a descriptor and a trailing amount become a row")
    func ordinaryChargeLine() throws {
        let parsed = try #require(row("03/09  SQ *BLUE BOTTLE 1042   6.75"))

        #expect(parsed.rawDescriptor == "SQ *BLUE BOTTLE 1042")
        #expect(parsed.amountCents == 675)
        #expect(parsed.kind == .charge)
    }

    @Test("Every date form a statement prints is read")
    func dateForms() {
        let lines = [
            "2026-03-09 COFFEE 6.75",
            "03/09/2026 COFFEE 6.75",
            "03-09-26 COFFEE 6.75",
            "03/09 COFFEE 6.75",
            "Mar 9 COFFEE 6.75"
        ]

        let parsed = lines.compactMap { row($0) }

        #expect(parsed.count == lines.count)
    }

    @Test("A day above twelve is read as the day, not refused")
    func dayFirstIsTolerated() throws {
        let parsed = try #require(row("25/12 COFFEE 6.75"))

        let month = Fixtures.utc.component(.month, from: parsed.date)
        let day = Fixtures.utc.component(.day, from: parsed.date)
        #expect(month == 12)
        #expect(day == 25)
    }

    @Test("A trailing CR marks a credit")
    func creditSuffix() throws {
        let parsed = try #require(row("03/09  UNIQLO RETURN  41.20 CR"))

        #expect(parsed.kind == .refund)
        #expect(parsed.amountCents == 4_120)
    }

    @Test("A parenthesised or negative amount marks a credit")
    func otherCreditForms() throws {
        let bracketed = try #require(row("03/09  UNIQLO RETURN  (41.20)"))
        let negative = try #require(row("03/09  UNIQLO RETURN  -41.20"))

        #expect(bracketed.kind == .refund)
        #expect(negative.kind == .refund)
    }

    @Test("A payment credit is classified as a payment, not a refund")
    func paymentLine() throws {
        let parsed = try #require(row("03/09  PAYMENT - THANK YOU  500.00 CR"))

        #expect(parsed.kind == .payment)
    }

    @Test("A line with no date is not a transaction")
    func headerLinesAreIgnored() {
        #expect(row("Statement of account") == nil)
        #expect(row("Account number 4417 0000 0000 1234") == nil)
    }

    @Test("A line with a date but no amount is not a transaction")
    func datedHeadingsAreIgnored() {
        #expect(row("03/09 Statement closing date") == nil)
    }

    @Test("A line with no descriptor left is refused rather than imported blank")
    func emptyDescriptorIsRefused() {
        #expect(row("03/09  6.75") == nil)
    }

    @Test("A date years away from now is not a date")
    func implausibleDatesAreRefused() {
        // Guards against reading part of an account number as a date.
        #expect(row("01/01/1998 SOMETHING 6.75") == nil)
    }

    @Test("Rows are read from every page of a statement")
    func readsAcrossPages() {
        let statement = RecognizedStatement(pages: [
            RecognizedReceipt(lines: [
                RecognizedLine(text: "03/09 COFFEE 6.75", topFraction: 0.1)
            ]),
            RecognizedReceipt(lines: [
                RecognizedLine(text: "03/10 BOOKS 12.00", topFraction: 0.1)
            ])
        ])

        let rows = StatementTextParser.rows(from: statement, context: context)

        #expect(rows.count == 2)
    }
}
