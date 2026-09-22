import Foundation
import Testing
import Domain
@testable import Features

/// Reading a real CSV file off disk end to end, in the host app (§9.7).
///
/// The Simulator has no generative assets, so the on-device header mapper declines here and
/// the deterministic one answers — which is exactly the path that has to work on every
/// device, and the reason this test is worth running in the host app rather than in Domain.
@MainActor
@Suite("CSV file reading")
struct StatementCSVPipelineTests {

    /// The clock and calendar the rows resolve against.
    private var context: StatementParseContext {
        StatementParseContext(now: Date(timeIntervalSince1970: 1_789_000_000))
    }

    /// A bank export written to a real file, as the document picker would hand it over.
    /// - Parameters:
    ///   - text: The file's contents.
    ///   - encoding: How to write the bytes.
    /// - Returns: The file's location.
    /// - Throws: Any error writing the file.
    private func file(
        _ text: String,
        encoding: String.Encoding = .utf8
    ) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).csv")
        let data = try #require(text.data(using: encoding))
        try data.write(to: url)
        return url
    }

    /// A Chase-shaped export: charges negative, a payment positive, posting dates a day on.
    private let chase = """
        Transaction Date,Post Date,Description,Category,Type,Amount
        09/08/2026,09/09/2026,BLUE BOTTLE COFFEE,Food & Drink,Sale,-6.75
        09/05/2026,09/07/2026,"SMITH, JONES & CO",Shopping,Sale,-41.20
        09/01/2026,09/02/2026,PAYMENT THANK YOU,,Payment,500.00
        """

    @Test("A CSV picked off disk is read into rows")
    func aFileOnDiskIsRead() async throws {
        let url = try file(chase)
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try StatementFileReader.text(at: url)
        let document = try await StatementImporter().read(.csv(text), context: context)

        #expect(document.rows.count == 3)
        #expect(document.rows.first?.amountCents == 675)
        #expect(document.rows.contains { $0.rawDescriptor == "SMITH, JONES & CO" })
    }

    @Test("The transaction date is taken, not the posting date a day later")
    func theTransactionDateIsCanonical() async throws {
        let url = try file(chase)
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try StatementFileReader.text(at: url)
        let document = try await StatementImporter().read(.csv(text), context: context)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let first = try #require(document.rows.first)
        #expect(calendar.component(.day, from: first.date) == 8)
    }

    @Test("A card payment is recognised so the planner can leave it out")
    func paymentsSurviveTheRoundTrip() async throws {
        let url = try file(chase)
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try StatementFileReader.text(at: url)
        let document = try await StatementImporter().read(.csv(text), context: context)

        let plan = StatementImportPlanner.plan(
            document, in: StatementImportContext(accountID: UUID())
        )
        #expect(plan.additions.count == 2)
        #expect(plan.skipped.map(\.reason) == [.cardPayment])
    }

    @Test("Importing the same export twice adds nothing the second time")
    func aReimportIsANoOp() async throws {
        let url = try file(chase)
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try StatementFileReader.text(at: url)
        let document = try await StatementImporter().read(.csv(text), context: context)
        let card = UUID()
        let first = StatementImportPlanner.plan(
            document, in: StatementImportContext(accountID: card)
        )

        let second = StatementImportPlanner.plan(
            document, in: StatementImportContext(accountID: card, existing: first.additions)
        )

        #expect(second.additions.isEmpty)
        #expect(second.conflicts.isEmpty)
    }

    @Test("A UTF-16 export, as Excel on Windows writes one, is still read")
    func alternativeEncodingsAreDecoded() throws {
        let url = try file(chase, encoding: .utf16)
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try StatementFileReader.text(at: url)

        #expect(text.contains("BLUE BOTTLE COFFEE"))
    }

    @Test("A file of bytes that decode to nothing usable is reported")
    func anUnreadableFileIsReported() throws {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).csv")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: StatementImportError.unreadableCSV) {
            try StatementFileReader.text(at: url)
        }
    }
}
