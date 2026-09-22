import Foundation
import Testing
@testable import Features
import Domain

/// Importing a statement, and resolving what it conflicts with (§4.2, §9.7).
@MainActor
@Suite("Statement import")
struct StatementImportViewModelTests {

    /// The pieces under test, wired together.
    private struct Harness {
        /// The account repository fake.
        let accounts: FakeAccountRepository
        /// The transaction repository fake.
        let transactions: FakeTransactionRepository
        /// The model under test.
        let model: StatementImportViewModel
        /// The card the statement is for.
        let card: Domain.Account
    }

    /// A fixed moment, so no test depends on the wall clock.
    private static let now = Date(timeIntervalSince1970: 1_789_000_000)

    /// A date offset from ``now``.
    /// - Parameter days: Days to offset.
    /// - Returns: The date.
    private static func day(_ days: Int) -> Date {
        now.addingTimeInterval(Double(days) * 86_400)
    }

    /// Builds a statement of the given rows.
    /// - Parameters:
    ///   - rows: The rows the statement holds.
    ///   - last4: The digits the statement printed.
    /// - Returns: The document.
    private func statement(_ rows: [StatementRow], last4: String? = "4417") -> StatementDocument {
        StatementDocument(tender: ReceiptTender(last4: last4, network: .visa), rows: rows)
    }

    /// Builds a harness whose reader returns the given statement.
    /// - Parameters:
    ///   - document: What the statement says.
    ///   - existing: What the ledger already holds.
    ///   - adjudicator: The duplicate judge to use.
    /// - Returns: The harness.
    private func makeHarness(
        document: StatementDocument,
        existing: [Domain.Transaction] = [],
        adjudicator: any DuplicateAdjudicating = FakeDuplicateAdjudicator()
    ) async -> Harness {
        let accounts = FakeAccountRepository()
        let transactions = FakeTransactionRepository(accounts: accounts)
        var card = Domain.Account(name: "Visa", kind: .card)
        card.last4 = "4417"
        card.cardNetwork = .visa
        try? await accounts.save(card)
        for transaction in existing { try? await transactions.save(transaction) }

        let importer = StatementImporter(
            reader: FakeStatementReader(
                statement: RecognizedStatement(pages: [RecognizedReceipt(lines: [
                    RecognizedLine(text: "placeholder", topFraction: 0)
                ])])
            ),
            primary: FakeStatementExtractor(document: document),
            fallback: FakeStatementExtractor(),
            adjudicator: adjudicator,
            backupAdjudicator: HeuristicDuplicateAdjudicator()
        )
        let model = StatementImportViewModel(
            coordinator: StatementImportCoordinator(
                accounts: accounts,
                transactions: transactions,
                categories: FakeCategoryRepository()
            ),
            settings: AppSettings(),
            importer: importer
        )
        return Harness(accounts: accounts, transactions: transactions, model: model, card: card)
    }

    /// Builds a statement row.
    /// - Parameters:
    ///   - descriptor: The descriptor as printed.
    ///   - cents: Positive magnitude in cents.
    ///   - days: Days from ``now``.
    /// - Returns: The row.
    private func row(_ descriptor: String, cents: Int, days: Int) -> StatementRow {
        StatementRow(date: Self.day(days), rawDescriptor: descriptor, amountCents: cents)
    }

    @Test("Reading a statement writes nothing until it is approved")
    func nothingIsWrittenBeforeApproval() async {
        let harness = await makeHarness(document: statement([
            row("BLUE BOTTLE", cents: 675, days: -3),
            row("UNIQLO", cents: 8_900, days: -2)
        ]))

        await harness.model.begin(.pdfData(Data()))

        let stored = try? await harness.transactions.transactions(accountID: nil, in: nil)
        #expect(stored?.isEmpty == true, "the review has not been approved yet")
        #expect(harness.model.reviewDrafts.count == 2)
        #expect(harness.model.tickedCount == 2, "clean rows start ticked")
    }

    @Test("Approving writes exactly the rows that are ticked")
    func approvalWritesTickedRows() async {
        let harness = await makeHarness(document: statement([
            row("BLUE BOTTLE", cents: 675, days: -3),
            row("UNIQLO", cents: 8_900, days: -2)
        ]))
        await harness.model.begin(.pdfData(Data()))
        harness.model.reviewDrafts.last?.setTicked(false)

        let approved = await harness.model.approve()

        #expect(approved)
        let stored = try? await harness.transactions.transactions(accountID: nil, in: nil)
        #expect(stored?.count == 1)
        #expect(stored?.first?.merchant == "BLUE BOTTLE")
    }

    @Test("A row already in the ledger is offered, unticked, rather than written again")
    func exactDuplicateIsOfferedUnticked() async {
        var existing = Domain.Transaction(
            amountCents: 675, type: .expense, date: Self.day(-3), merchant: "BLUE BOTTLE"
        )
        let harness = await makeHarness(
            document: statement([row("BLUE BOTTLE", cents: 675, days: -3)])
        )
        existing.accountID = harness.card.id
        try? await harness.transactions.save(existing)

        await harness.model.begin(.pdfData(Data()))

        #expect(harness.model.tickedCount == 0, "nothing new to add")
        #expect(harness.model.reviewDrafts.count == 1, "the row is still shown, not hidden")
    }

    @Test("A differently worded entry is flagged as a possible duplicate")
    func differentWordingBecomesADuplicate() async {
        var existing = Domain.Transaction(
            amountCents: 675, type: .expense, date: Self.day(-3), merchant: "Blue Bottle Coffee"
        )
        let harness = await makeHarness(
            document: statement([row("SQ *BLUE BOTTLE 1042", cents: 675, days: -3)])
        )
        existing.accountID = harness.card.id
        try? await harness.transactions.save(existing)

        await harness.model.begin(.pdfData(Data()))

        let statuses = harness.model.reviewDrafts.map(\.status)
        #expect(statuses.contains { if case .duplicate = $0 { return true } else { return false } })
        #expect(harness.model.tickedCount == 0, "a duplicate is never pre-ticked")
    }

    @Test("Ticking a flagged duplicate writes it after all")
    func tickedDuplicateIsWritten() async {
        var existing = Domain.Transaction(
            amountCents: 675, type: .expense, date: Self.day(-3), merchant: "Blue Bottle Coffee"
        )
        let harness = await makeHarness(
            document: statement([row("SQ *BLUE BOTTLE 1042", cents: 675, days: -3)])
        )
        existing.accountID = harness.card.id
        try? await harness.transactions.save(existing)
        await harness.model.begin(.pdfData(Data()))

        harness.model.reviewDrafts.first?.setTicked(true)
        await harness.model.approve()

        let stored = try? await harness.transactions.transactions(accountID: nil, in: nil)
        #expect(stored?.count == 2, "the user said they were different purchases")
    }

    @Test("A card payment is shown but never ticked")
    func cardPaymentIsShownUnticked() async {
        let payment = StatementRow(
            date: Self.day(-1), rawDescriptor: "PAYMENT - THANK YOU",
            amountCents: 50_000, kind: .payment
        )
        let harness = await makeHarness(document: statement([payment]))

        await harness.model.begin(.pdfData(Data()))

        #expect(harness.model.reviewDrafts.count == 1)
        #expect(harness.model.tickedCount == 0)
    }

    @Test("Edits made on the review reach the saved transaction")
    func editsSurviveApproval() async {
        let harness = await makeHarness(
            document: statement([row("SQ *BLUE BOTTLE 1042", cents: 675, days: -3)])
        )
        await harness.model.begin(.pdfData(Data()))

        harness.model.reviewDrafts.first?.merchant = "Blue Bottle"
        harness.model.reviewDrafts.first?.amountText = "7.25"
        await harness.model.approve()

        let stored = try? await harness.transactions.transactions(accountID: nil, in: nil)
        #expect(stored?.first?.merchant == "Blue Bottle")
        #expect(stored?.first?.amountCents == 725)
    }

    @Test("Flipping a row's direction files it as income")
    func flippingDirectionWritesIncome() async {
        let harness = await makeHarness(
            document: statement([row("UNIQLO RETURN", cents: 8_900, days: -2)])
        )
        await harness.model.begin(.pdfData(Data()))

        guard let draft = harness.model.reviewDrafts.first else { return }
        harness.model.flipDirection(for: draft)
        await harness.model.approve()

        let stored = try? await harness.transactions.transactions(accountID: nil, in: nil)
        #expect(stored?.first?.type == .income)
        #expect(stored?.first?.amountCents == 8_900, "the magnitude stays unsigned")
    }

    @Test("Approving twice does not write the rows twice")
    func approvingIsIdempotent() async {
        let harness = await makeHarness(
            document: statement([row("BLUE BOTTLE", cents: 675, days: -3)])
        )
        await harness.model.begin(.pdfData(Data()))

        await harness.model.approve()
        await harness.model.approve()

        let stored = try? await harness.transactions.transactions(accountID: nil, in: nil)
        #expect(stored?.count == 1)
    }

    @Test("The summary counts the statement's own lines, not the rows that parsed")
    func summaryCountsSourceLines() async {
        var document = statement([row("BLUE BOTTLE", cents: 675, days: -3)])
        document.unread = [UnreadLine(text: "9.30", lineNumber: 4, problem: .noDate)]
        document.sourceLineCount = 12
        let harness = await makeHarness(document: document)

        await harness.model.begin(.pdfData(Data()))

        #expect(harness.model.reviewSummary.sourceLines == 12)
        #expect(harness.model.reviewSummary.needsAttention == 1)
    }
}
