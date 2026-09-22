import Foundation

/// Turns a plan into something a person can read, and a review back into what to write (§9.7).
///
/// **Nothing is written until this says so.** The import used to commit its additions inside
/// the planning step, before any screen appeared, and offer the user a wizard covering only
/// the rows that collided with the ledger. Everything else — a misread amount, a charge filed
/// as income, a line dropped for having no date — reached the ledger, or failed to, without
/// ever being shown. So the plan now ends here, as a list, and ``transactions(from:)`` is the
/// only thing that produces rows to save.
///
/// Pure and synchronous, like ``StatementImportPlanner``: every decision is testable without a
/// database, a simulator or a language model.
public enum ImportReviewBuilder {

    /// Lays a plan out as one reviewable row per source line.
    ///
    /// Ordered by how much they need a person — unread lines first, then duplicates, then
    /// what cannot be imported, then the clean rows — and by date within each group.
    ///
    /// - Parameter plan: What the planner decided.
    /// - Returns: The rows to review.
    public static func rows(from plan: ImportPlan) -> [ImportReviewRow] {
        let ready = plan.additions.map { row(from: $0, status: .ready) }
        let conflicts = plan.conflicts.map { conflict in
            row(
                from: conflict.incoming,
                sourceText: conflict.row.rawDescriptor,
                status: .duplicate(existingID: conflict.existing.id, reason: conflict.reason)
            )
        }
        let skipped = plan.skipped.map { skip in
            ImportReviewRow(
                sourceText: skip.row.rawDescriptor,
                date: skip.row.date,
                merchant: skip.row.merchant,
                amountCents: skip.row.amountCents,
                isIncome: skip.row.kind == .refund,
                status: .excluded(skip.reason)
            )
        }
        let unread = plan.unread.map { line in
            ImportReviewRow(
                // The unread line's own identity, so a repairer's answer can be matched back
                // to the row it belongs to. See ``UnreadLineRepairing``.
                id: line.id,
                sourceText: line.text,
                status: .needsAttention(line.problem)
            )
        }
        return sorted(ready + conflicts + skipped + unread)
    }

    /// Sorts rows so the ones needing a person come first.
    /// - Parameter rows: The rows to sort.
    /// - Returns: The rows in review order.
    static func sorted(_ rows: [ImportReviewRow]) -> [ImportReviewRow] {
        rows.sorted { first, second in
            guard first.status.priority == second.status.priority else {
                return first.status.priority < second.status.priority
            }
            // A row with no date sorts to the top of its group: it is the one that cannot be
            // written at all, so it is the one worth reading first.
            switch (first.date, second.date) {
            case (nil, nil): return first.sourceText < second.sourceText
            case (nil, _): return true
            case (_, nil): return false
            case (let left?, let right?):
                return left == right ? first.sourceText < second.sourceText : left < right
            }
        }
    }

    /// Counts how a review's rows divide up.
    /// - Parameters:
    ///   - rows: The rows being reviewed.
    ///   - sourceLines: How many lines the statement held.
    /// - Returns: The summary.
    public static func summary(of rows: [ImportReviewRow], sourceLines: Int) -> ImportReviewSummary {
        ImportReviewSummary(
            sourceLines: sourceLines,
            ticked: rows.count(where: \.isTicked),
            duplicates: rows.count { if case .duplicate = $0.status { return true } else { return false } },
            needsAttention: rows.count {
                if case .needsAttention = $0.status { return true } else { return false }
            },
            excluded: rows.count { if case .excluded = $0.status { return true } else { return false } }
        )
    }

    /// The transactions a finished review asks to be written.
    ///
    /// **Only what the user ticked.** A row that is untickable — no date, no amount, no name —
    /// can never reach this, because ``ImportReviewRow/canBeTicked`` refuses it and the tick
    /// is cleared with it.
    ///
    /// - Parameters:
    ///   - rows: The reviewed rows.
    ///   - accountID: The card they belong to.
    /// - Returns: The transactions to save.
    public static func transactions(
        from rows: [ImportReviewRow],
        accountID: UUID
    ) -> [Transaction] {
        rows.compactMap { row in
            guard row.isTicked, row.canBeTicked, let date = row.date else { return nil }
            return Transaction(
                id: row.id,
                amountCents: row.amountCents,
                type: row.isIncome ? .income : .expense,
                categoryID: row.categoryID,
                accountID: accountID,
                date: date,
                merchant: row.merchant.trimmingCharacters(in: .whitespacesAndNewlines),
                memo: nil,
                tags: [StatementImportPlanner.originTag]
            )
        }
    }

    /// Builds a reviewable row from a transaction the planner prepared.
    /// - Parameters:
    ///   - transaction: The candidate transaction.
    ///   - sourceText: The statement's own wording. Defaults to the merchant.
    ///   - status: Why the row is in the state it is.
    /// - Returns: The row.
    static func row(
        from transaction: Transaction,
        sourceText: String? = nil,
        status: ImportReviewStatus
    ) -> ImportReviewRow {
        ImportReviewRow(
            // The planner's identifier is carried through, so a row the user ticks is written
            // as the transaction the planner already built rather than a second one.
            id: transaction.id,
            sourceText: sourceText ?? transaction.merchant,
            date: transaction.date,
            merchant: transaction.merchant,
            amountCents: transaction.amountCents,
            isIncome: transaction.type == .income,
            categoryID: transaction.categoryID,
            status: status
        )
    }
}
