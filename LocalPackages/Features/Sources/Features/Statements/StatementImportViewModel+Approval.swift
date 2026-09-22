import Foundation
import Domain

/// Running the import and writing what the review approved (§9.7).
///
/// Split from ``StatementImportViewModel`` to keep each file within the 300-line limit.
extension StatementImportViewModel {

    /// Plans the import and lays it out for review. Writes nothing.
    /// - Parameter accountID: The card to import against.
    func runImport(accountID: UUID) async {
        guard let document else { return }
        self.accountID = accountID
        do {
            importer.report(.matching)
            let planned = try await coordinator.plan(document, accountID: accountID)

            let verdicts = await importer.adjudicate(
                planned.conflicts,
                context: DuplicateAdjudicationContext(
                    accountName: accounts.first { $0.id == accountID }?.name ?? ""
                )
            )
            importer.report(.idle)
            stageForReview(planned, verdicts: verdicts)
        } catch {
            importer.report(.idle)
            errorMessage = "Could not read that statement."
        }
    }

    /// Writes every ticked row, and nothing else.
    ///
    /// **One store write for the additions.** A row the user chose to put in place of an
    /// existing entry deletes that entry first, so the replacement cannot briefly double the
    /// card's balance.
    ///
    /// - Returns: `true` when the write succeeded.
    @discardableResult
    public func approve() async -> Bool {
        guard let accountID, !isApproving else { return false }
        isApproving = true
        defer { isApproving = false }

        let reviewed = drafts.map(\.edited)
        let replacements = drafts.compactMap { draft in
            draft.isTicked ? draft.replacesExistingID : nil
        }
        do {
            importer.report(.writing)
            for existingID in replacements {
                try await coordinator.delete(id: existingID)
            }
            let written = ImportReviewBuilder.transactions(from: reviewed, accountID: accountID)
            try await coordinator.commit(ImportPlan(additions: written))
            importer.report(.idle)
            outcome = Self.outcome(of: reviewed, sourceLines: sourceLineCount)
            drafts = []
            return true
        } catch {
            importer.report(.idle)
            errorMessage = "Could not save those transactions."
            return false
        }
    }

    /// Discards the review without writing anything.
    public func discardReview() {
        reset()
    }

    /// Summarises what a finished review wrote.
    /// - Parameters:
    ///   - rows: The rows as the user left them.
    ///   - sourceLines: How many lines the statement held.
    /// - Returns: The outcome.
    static func outcome(of rows: [ImportReviewRow], sourceLines: Int) -> ImportOutcome {
        ImportOutcome(
            rowsProcessed: sourceLines,
            added: rows.count(where: \.isTicked),
            exactDuplicatesSkipped: rows.count { row in
                guard case .excluded(.exactDuplicate) = row.status else { return false }
                return true
            },
            conflictsRaised: rows.count { row in
                guard case .duplicate = row.status else { return false }
                return true
            },
            conflictsResolved: rows.count { row in
                guard case .duplicate = row.status else { return false }
                return true
            },
            paymentsSkipped: rows.count { row in
                guard case .excluded(.cardPayment) = row.status else { return false }
                return true
            }
        )
    }
}
