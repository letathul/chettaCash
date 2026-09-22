import Foundation
import Testing
@testable import Domain

/// Laying an import out for review, and reading a finished review back (§9.7).
@Suite("Import review")
struct ImportReviewBuilderTests {

    /// The card the rows are filed against.
    private let account = UUID()
    /// A fixed moment the rows sit around.
    private let now = Date(timeIntervalSince1970: 1_787_000_000)

    /// Builds a candidate transaction.
    /// - Parameters:
    ///   - merchant: The name it carries.
    ///   - cents: The magnitude in cents.
    ///   - type: Expense or income.
    /// - Returns: The transaction.
    private func candidate(
        _ merchant: String,
        cents: Int = 1_000,
        type: TransactionType = .expense
    ) -> Transaction {
        Transaction(
            amountCents: cents, type: type, accountID: account, date: now, merchant: merchant
        )
    }

    /// Builds a statement row.
    /// - Parameters:
    ///   - descriptor: The descriptor as printed.
    ///   - cents: The magnitude in cents.
    ///   - kind: What kind of line it is.
    /// - Returns: The row.
    private func statementRow(
        _ descriptor: String,
        cents: Int = 1_000,
        kind: StatementRowKind = .charge
    ) -> StatementRow {
        StatementRow(date: now, rawDescriptor: descriptor, amountCents: cents, kind: kind)
    }

    @Test("Every source line becomes exactly one reviewable row")
    func everyLineBecomesARow() {
        let plan = ImportPlan(
            additions: [candidate("COSTCO"), candidate("SHELL")],
            conflicts: [
                DuplicateConflict(
                    incoming: candidate("AMZN"), row: statementRow("AMZN"),
                    existing: candidate("Amazon"), reason: .sameDaySameAmount
                )
            ],
            skipped: [SkippedRow(row: statementRow("PAYMENT", kind: .payment), reason: .cardPayment)],
            unread: [UnreadLine(text: "9.30", lineNumber: 4, problem: .noDate)],
            rowsProcessed: 5
        )

        let rows = ImportReviewBuilder.rows(from: plan)

        #expect(rows.count == 5, "two additions, one conflict, one skip and one unread line")
    }

    @Test("The rows that need a person come first")
    func needsAttentionSortsFirst() {
        let plan = ImportPlan(
            additions: [candidate("COSTCO")],
            conflicts: [
                DuplicateConflict(
                    incoming: candidate("AMZN"), row: statementRow("AMZN"),
                    existing: candidate("Amazon"), reason: .sameDaySameAmount
                )
            ],
            skipped: [SkippedRow(row: statementRow("PAYMENT", kind: .payment), reason: .cardPayment)],
            unread: [UnreadLine(text: "9.30", lineNumber: 4, problem: .noDate)]
        )

        let statuses = ImportReviewBuilder.rows(from: plan).map(\.status.priority)

        #expect(statuses == statuses.sorted(), "review order runs from most to least urgent")
    }

    @Test("Only a clean row starts ticked")
    func onlyCleanRowsStartTicked() {
        let plan = ImportPlan(
            additions: [candidate("COSTCO")],
            conflicts: [
                DuplicateConflict(
                    incoming: candidate("AMZN"), row: statementRow("AMZN"),
                    existing: candidate("Amazon"), reason: .sameDaySameAmount
                )
            ],
            skipped: [SkippedRow(row: statementRow("PAYMENT", kind: .payment), reason: .cardPayment)],
            unread: [UnreadLine(text: "9.30", lineNumber: 4, problem: .noDate)]
        )

        let ticked = ImportReviewBuilder.rows(from: plan).filter(\.isTicked)

        #expect(ticked.count == 1)
        #expect(ticked.first?.merchant == "COSTCO")
    }

    @Test("A line with no date can never be ticked, however it is asked")
    func undatedRowRefusesToBeTicked() {
        let row = ImportReviewRow(
            sourceText: "9.30", status: .needsAttention(.noDate), isTicked: true
        )

        #expect(row.canBeTicked == false)
        #expect(row.isTicked == false, "a tick that cannot be honoured is not recorded")
    }

    @Test("A zero-amount row cannot be ticked either")
    func zeroAmountRefusesToBeTicked() {
        let row = ImportReviewRow(
            sourceText: "FREE SAMPLE", date: Date(), merchant: "Shop",
            amountCents: 0, isTicked: true
        )

        #expect(row.isTicked == false)
    }

    @Test("Approving writes the ticked rows and nothing else")
    func writesOnlyTickedRows() {
        let rows = [
            ImportReviewRow(
                sourceText: "COSTCO", date: now, merchant: "COSTCO", amountCents: 1_000
            ),
            ImportReviewRow(
                sourceText: "AMZN", date: now, merchant: "AMZN", amountCents: 2_000,
                status: .duplicate(existingID: UUID(), reason: .sameDaySameAmount)
            )
        ]

        let written = ImportReviewBuilder.transactions(from: rows, accountID: account)

        #expect(written.count == 1)
        #expect(written.first?.merchant == "COSTCO")
        #expect(written.first?.accountID == account)
        #expect(written.first?.tags == [StatementImportPlanner.originTag])
    }

    @Test("A row marked as income is written as income")
    func incomeDirectionSurvives() {
        let rows = [
            ImportReviewRow(
                sourceText: "REFUND", date: now, merchant: "UNIQLO",
                amountCents: 8_900, isIncome: true
            )
        ]

        let written = ImportReviewBuilder.transactions(from: rows, accountID: account)

        #expect(written.first?.type == .income)
        #expect(written.first?.amountCents == 8_900, "the magnitude stays unsigned")
    }

    @Test("A duplicate the user ticks is written after all")
    func tickedDuplicateIsWritten() {
        var row = ImportReviewRow(
            sourceText: "AMZN", date: now, merchant: "AMZN", amountCents: 2_000,
            status: .duplicate(existingID: UUID(), reason: .sameDaySameAmount)
        )
        row.isTicked = true

        #expect(ImportReviewBuilder.transactions(from: [row], accountID: account).count == 1)
    }

    @Test("The summary counts each group once")
    func summaryCounts() {
        let plan = ImportPlan(
            additions: [candidate("COSTCO"), candidate("SHELL")],
            conflicts: [
                DuplicateConflict(
                    incoming: candidate("AMZN"), row: statementRow("AMZN"),
                    existing: candidate("Amazon"), reason: .sameDaySameAmount
                )
            ],
            skipped: [SkippedRow(row: statementRow("PAYMENT", kind: .payment), reason: .cardPayment)],
            unread: [UnreadLine(text: "9.30", lineNumber: 4, problem: .noDate)],
            rowsProcessed: 9
        )
        let rows = ImportReviewBuilder.rows(from: plan)

        let summary = ImportReviewBuilder.summary(of: rows, sourceLines: plan.rowsProcessed)

        #expect(summary.sourceLines == 9)
        #expect(summary.ticked == 2)
        #expect(summary.duplicates == 1)
        #expect(summary.needsAttention == 1)
        #expect(summary.excluded == 1)
        #expect(summary.headline.contains("9 lines"))
    }
}
