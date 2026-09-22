import Foundation
import Testing
@testable import Domain

/// Reading a bank's CSV into the same document a PDF produces (§9.7).
@Suite("CSV statement parsing")
struct CSVStatementParserTests {

    /// The clock and calendar every file in this suite is read against.
    private let context = StatementParseContext(now: Fixtures.now, calendar: Fixtures.utc)

    /// Reads a file the way the importer does, mapping its header first.
    /// - Parameter csv: The file's text.
    /// - Returns: The document.
    private func read(_ csv: String) -> StatementDocument {
        let table = CSVCodec.table(csv, delimiter: CSVCodec.inferDelimiter(csv))
        return CSVStatementParser.document(
            table: table,
            columns: CSVHeaderMatcher.columns(for: table.headers),
            context: context
        )
    }

    @Test("A Chase export becomes charges dated by their transaction date")
    func chaseExportIsRead() {
        let document = read("""
            Transaction Date,Post Date,Description,Category,Type,Amount
            09/08/2026,09/09/2026,BLUE BOTTLE COFFEE,Food & Drink,Sale,-6.75
            09/05/2026,09/07/2026,AMZN Mktp US*2K4TQ,Shopping,Sale,-41.20
            """)

        #expect(document.rows.count == 2)
        let first = document.rows.first
        #expect(first?.amountCents == 675)
        #expect(first?.kind == .charge)
        #expect(first?.rawDescriptor == "BLUE BOTTLE COFFEE")
        // The transaction date, not the posting date a day later.
        #expect(Fixtures.utc.component(.day, from: first?.date ?? .now) == 8)
    }

    @Test("A card payment is read as a payment, whatever the file calls its columns")
    func paymentsAreClassified() {
        let document = read("""
            Transaction Date,Post Date,Description,Type,Amount
            09/08/2026,09/09/2026,BLUE BOTTLE,Sale,-6.75
            09/01/2026,09/02/2026,PAYMENT THANK YOU,Payment,500.00
            """)

        #expect(document.rows.map(\.kind) == [.charge, .payment])
    }

    @Test("An Amex export prints its charges positive and is read the same way")
    func amexSignConventionIsHonoured() {
        let document = read("""
            Date,Description,Amount
            09/08/2026,BLUE BOTTLE,6.75
            09/01/2026,PAYMENT RECEIVED - THANK YOU,-500.00
            """)

        #expect(document.rows.map(\.kind) == [.charge, .payment])
        #expect(document.rows.first?.amountCents == 675)
    }

    @Test("A split debit and credit pair needs no sign convention")
    func splitColumnsAreRead() {
        let document = read("""
            Date,Description,Debit,Credit
            09/08/2026,BLUE BOTTLE,6.75,
            09/02/2026,RETURNED GOODS,,20.00
            """)

        #expect(document.rows.map(\.kind) == [.charge, .refund])
        #expect(document.rows.last?.amountCents == 2_000)
    }

    @Test("A descriptor containing a comma survives the parse")
    func quotedDescriptorsAreNotSplit() {
        let document = read("""
            Date,Description,Amount
            09/08/2026,"Smith, Jones & Co",-42.10
            """)

        #expect(document.rows.first?.rawDescriptor == "Smith, Jones & Co")
        #expect(document.rows.first?.amountCents == 4_210)
    }

    @Test("A semicolon-separated European export is read without being told")
    func delimiterAndSeparatorsAreInferred() {
        let document = read("""
            Date;Description;Amount
            08/09/2026;"Muller, GmbH";-1.234,56
            """)

        #expect(document.rows.count == 1)
        #expect(document.rows.first?.amountCents == 123_456)
        #expect(document.rows.first?.rawDescriptor == "Muller, GmbH")
    }

    @Test("A byte-order mark does not cost the file its date column")
    func aByteOrderMarkIsStripped() {
        let document = read("\u{FEFF}Date,Description,Amount\n09/08/2026,BLUE BOTTLE,-6.75\n")

        #expect(document.rows.count == 1)
    }

    @Test("A row with no readable date is dropped rather than invented")
    func unreadableRowsAreDropped() {
        let document = read("""
            Date,Description,Amount
            09/08/2026,BLUE BOTTLE,-6.75
            ,PENDING CHARGE,-9.99
            09/07/2026,NO AMOUNT HERE,
            """)

        #expect(document.rows.count == 1)
        #expect(document.rows.first?.rawDescriptor == "BLUE BOTTLE")
    }

    @Test("A header with no date column yields nothing rather than a half-read file")
    func anUnusableHeaderYieldsNothing() {
        let document = read("""
            Description,Amount
            BLUE BOTTLE,-6.75
            """)

        #expect(document.isEmpty)
    }

    @Test("A file of headers alone is empty, not a crash")
    func aHeaderOnlyFileIsEmpty() {
        #expect(read("Date,Description,Amount\n").isEmpty)
    }
}
