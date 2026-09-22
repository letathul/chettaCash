import Foundation
import Testing
@testable import Features
import Domain

/// Importing a bank's CSV export through the same pipeline a PDF uses (§9.7).
@Suite("CSV statement import")
@MainActor
struct StatementImportCSVTests {

    /// A Chase-shaped export: a transaction date, a posting date a day later, and charges
    /// printed negative.
    private let chase = """
        Transaction Date,Post Date,Description,Category,Type,Amount
        09/08/2026,09/09/2026,BLUE BOTTLE COFFEE,Food & Drink,Sale,-6.75
        09/05/2026,09/07/2026,AMZN Mktp US*2K4TQ,Shopping,Sale,-41.20
        09/01/2026,09/02/2026,PAYMENT THANK YOU,,Payment,500.00
        """

    /// A fixed reference moment, so the year the dates resolve to never depends on the
    /// wall clock. Falls inside the dates the fixtures print.
    private static let now = Date(timeIntervalSince1970: 1_789_000_000)

    /// A fixed calendar, so a day boundary never depends on where the test runs.
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    /// The clock and calendar every file in this suite is read against.
    private let context = StatementParseContext(now: now, calendar: utc)

    @Test("A CSV is read without the on-device mapper, by the deterministic one")
    func theFallbackMapperReadsTheFile() async throws {
        // The model declines — which is what happens in the Simulator, on an older device,
        // and any time the user has Apple Intelligence off.
        let importer = StatementImporter(
            csvMapper: FakeCSVHeaderMapper(columns: nil),
            fallbackCSVMapper: HeuristicCSVHeaderMapper()
        )

        let document = try await importer.read(.csv(chase), context: context)

        #expect(document.rows.count == 3)
        // File order, which is the order the bank listed them.
        #expect(document.rows.map(\.kind) == [.charge, .charge, .payment])
        #expect(document.rows.first?.amountCents == 675)
    }

    @Test("The on-device mapper is preferred when it answers")
    func theModelMapperWinsWhenItAnswers() async throws {
        let mapper = FakeCSVHeaderMapper(
            columns: CSVStatementColumns(
                transactionDate: "Post Date", descriptor: "Category", amount: .single("Amount")
            )
        )
        let importer = StatementImporter(
            csvMapper: mapper, fallbackCSVMapper: HeuristicCSVHeaderMapper()
        )

        let document = try await importer.read(.csv(chase), context: context)

        // It was asked, and its answer — the posting date and the category column — is what
        // came back, rather than the matcher's more sensible reading.
        #expect(mapper.wasAsked.value)
        #expect(document.rows.contains { $0.rawDescriptor == "Food & Drink" })
    }

    @Test("A CSV never reaches the text reader")
    func aCSVBypassesRecognition() async throws {
        // The reader is rigged to fail. A CSV must not touch it, so the read still succeeds.
        let importer = StatementImporter(
            reader: FakeStatementReader(failure: .noTextFound),
            csvMapper: FakeCSVHeaderMapper(columns: nil),
            fallbackCSVMapper: HeuristicCSVHeaderMapper()
        )

        let document = try await importer.read(.csv(chase), context: context)

        #expect(!document.isEmpty)
    }

    @Test("A header nothing can map is reported rather than silently read as empty")
    func anUnmappableHeaderFails() async {
        let importer = StatementImporter(
            csvMapper: FakeCSVHeaderMapper(columns: nil),
            fallbackCSVMapper: FakeCSVHeaderMapper(columns: nil)
        )

        await #expect(throws: StatementImportError.noColumnsFound) {
            try await importer.read(.csv(self.chase), context: self.context)
        }
    }

    @Test("A file with no header at all is reported as unreadable")
    func anEmptyFileFails() async {
        let importer = StatementImporter(
            csvMapper: FakeCSVHeaderMapper(columns: nil),
            fallbackCSVMapper: HeuristicCSVHeaderMapper()
        )

        await #expect(throws: StatementImportError.unreadableCSV) {
            try await importer.read(.csv("   "), context: self.context)
        }
    }

    @Test("Every CSV failure has something to tell the user")
    func everyFailureIsExplained() {
        for failure in [StatementImportError.unreadableCSV, .noColumnsFound] {
            #expect(!StatementImportViewModel.message(for: failure).isEmpty)
        }
    }
}
