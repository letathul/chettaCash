import Foundation
import Testing
@testable import Features
import Domain

/// Leaving a review part-way, and the fallback when the on-device model declines.
@MainActor
@Suite("Statement import recovery")
struct StatementImportRecoveryTests {

    /// A fixed moment, so no test depends on the wall clock.
    private static let now = Date(timeIntervalSince1970: 1_789_000_000)

    /// A date offset from ``now``.
    /// - Parameter days: Days to offset.
    /// - Returns: The date.
    private static func day(_ days: Int) -> Date {
        now.addingTimeInterval(Double(days) * 86_400)
    }

    /// The pieces under test, wired together.
    private struct Harness {
        /// The transaction repository fake.
        let transactions: FakeTransactionRepository
        /// The model under test.
        let model: StatementImportViewModel
        /// The card the statement is for.
        let card: Domain.Account
    }

    /// Builds a harness whose statement conflicts with `count` hand-typed entries.
    /// - Parameters:
    ///   - count: How many conflicts to raise.
    ///   - adjudicator: The duplicate judge to use.
    /// - Returns: The harness.
    private func makeConflicts(
        _ count: Int,
        adjudicator: any DuplicateAdjudicating = FakeDuplicateAdjudicator()
    ) async -> Harness {
        let accounts = FakeAccountRepository()
        let transactions = FakeTransactionRepository(accounts: accounts)
        var card = Domain.Account(name: "Visa", kind: .card)
        card.last4 = "4417"
        try? await accounts.save(card)

        var rows: [StatementRow] = []
        for index in 0..<count {
            let cents = 1_000 + index * 111
            rows.append(
                StatementRow(
                    date: Self.day(-index - 1),
                    rawDescriptor: "STATEMENT WORDING \(index)",
                    amountCents: cents
                )
            )
            try? await transactions.save(
                Domain.Transaction(
                    amountCents: cents, type: .expense, accountID: card.id,
                    date: Self.day(-index - 1), merchant: "Typed \(index)"
                )
            )
        }

        let model = StatementImportViewModel(
            coordinator: StatementImportCoordinator(
                accounts: accounts,
                transactions: transactions,
                categories: FakeCategoryRepository()
            ),
            settings: AppSettings(),
            importer: Self.importer(rows: rows, adjudicator: adjudicator)
        )
        await model.begin(.pdfData(Data()))
        return Harness(transactions: transactions, model: model, card: card)
    }

    /// Builds an importer that reads a fixed set of rows.
    /// - Parameters:
    ///   - rows: The rows the statement holds.
    ///   - adjudicator: The duplicate judge to use.
    /// - Returns: The importer.
    static func importer(
        rows: [StatementRow],
        adjudicator: any DuplicateAdjudicating
    ) -> StatementImporter {
        StatementImporter(
            reader: FakeStatementReader(
                statement: RecognizedStatement(pages: [RecognizedReceipt(lines: [
                    RecognizedLine(text: "placeholder", topFraction: 0)
                ])])
            ),
            primary: FakeStatementExtractor(
                document: StatementDocument(
                    tender: ReceiptTender(last4: "4417"), rows: rows
                )
            ),
            fallback: FakeStatementExtractor(),
            adjudicator: adjudicator,
            backupAdjudicator: HeuristicDuplicateAdjudicator()
        )
    }

    @Test("Leaving the review part-way keeps every row, because nothing was written")
    func leavingTheReviewKeepsIt() async {
        let harness = await makeConflicts(3)

        // The screen closing does not touch the model; the rows are model state.
        #expect(harness.model.reviewDrafts.count == 3)
        #expect(harness.model.hasPendingReview)
        #expect(harness.model.resumeButtonTitle.contains("3 rows"))
        let stored = try? await harness.transactions.transactions(accountID: nil, in: nil)
        #expect(stored?.count == 3, "only the three hand-typed entries")
    }

    @Test("Approving the review clears it and hides the resume row")
    func approvingClearsTheReview() async {
        let harness = await makeConflicts(2)
        for draft in harness.model.reviewDrafts { draft.setTicked(true) }

        await harness.model.approve()

        #expect(harness.model.hasPendingReview == false)
        #expect(harness.model.outcome != nil)
    }

    @Test("A failed write leaves the review in place rather than losing it")
    func failedWriteKeepsTheReview() async {
        let harness = await makeConflicts(2)
        for draft in harness.model.reviewDrafts { draft.setTicked(true) }
        harness.transactions.failure = FakeFailure.write

        let approved = await harness.model.approve()

        #expect(approved == false)
        #expect(harness.model.reviewDrafts.count == 2, "the rows survive so it can be retried")
        #expect(harness.model.errorMessage != nil)
    }

    @Test("A duplicate the model declined to judge is still explained, by the fallback")
    func fallbackCoversWhatTheModelSkipped() async {
        // The model answers only the first of three; every row must still have something
        // to say for itself.
        let harness = await makeConflicts(
            3, adjudicator: FakeDuplicateAdjudicator(answerLimit: 1)
        )

        let explained = harness.model.reviewDrafts.filter {
            harness.model.rationale(for: $0) != nil
        }

        #expect(explained.count == 3)
    }

    @Test("With no model at all every duplicate still gets an explanation")
    func fallbackCoversEverything() async {
        let harness = await makeConflicts(
            3, adjudicator: FakeDuplicateAdjudicator(answerLimit: 0)
        )

        let rationales = harness.model.reviewDrafts.compactMap {
            harness.model.rationale(for: $0)
        }

        #expect(rationales.count == 3)
        #expect(rationales.allSatisfy { !$0.isEmpty })
    }

    @Test("However sure a reader is, a duplicate is never pre-ticked")
    func verdictsNeverPreTick() async {
        // An outright match used to pre-tick a row for removal. Now the row is simply
        // offered: a judgement the user did not make must never move money on its own.
        let harness = await makeConflicts(
            2, adjudicator: FakeDuplicateAdjudicator(judgement: .sameTransaction)
        )

        #expect(harness.model.tickedCount == 0)
    }

    @Test("A password-protected statement says so rather than failing vaguely")
    func passwordProtectedFilesAreNamed() async {
        let accounts = FakeAccountRepository()
        let model = StatementImportViewModel(
            coordinator: StatementImportCoordinator(
                accounts: accounts,
                transactions: FakeTransactionRepository(accounts: accounts),
                categories: FakeCategoryRepository()
            ),
            settings: AppSettings(),
            importer: StatementImporter(
                reader: FakeStatementReader(failure: .passwordProtected),
                primary: FakeStatementExtractor(),
                fallback: FakeStatementExtractor(),
                adjudicator: FakeDuplicateAdjudicator(),
                backupAdjudicator: HeuristicDuplicateAdjudicator()
            )
        )

        await model.begin(.pdfData(Data()))

        #expect(model.errorMessage?.contains("password-protected") == true)
    }
}

/// A failure a fake repository can be told to throw.
enum FakeFailure: Error {
    /// A write that did not succeed.
    case write
}
