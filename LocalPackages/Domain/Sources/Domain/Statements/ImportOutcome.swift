import Foundation

/// What an import actually did, for the summary the user reads afterwards (§9.4).
public struct ImportOutcome: Sendable, Equatable {
    /// How many rows the statement held.
    public var rowsProcessed: Int
    /// How many transactions were written.
    public var added: Int
    /// How many rows the ledger already held exactly.
    public var exactDuplicatesSkipped: Int
    /// How many pairs needed a decision.
    public var conflictsRaised: Int
    /// How many of those the user has resolved.
    public var conflictsResolved: Int
    /// How many card payments were left out.
    public var paymentsSkipped: Int

    /// How many conflicts are still waiting.
    public var pendingConflicts: Int { max(0, conflictsRaised - conflictsResolved) }
    /// Whether the import changed nothing and asked nothing.
    public var isNoOp: Bool { added == 0 && conflictsRaised == 0 }

    /// Creates an outcome.
    /// - Parameters:
    ///   - rowsProcessed: How many rows the statement held.
    ///   - added: How many transactions were written.
    ///   - exactDuplicatesSkipped: How many rows were already recorded.
    ///   - conflictsRaised: How many pairs needed a decision.
    ///   - conflictsResolved: How many the user has resolved.
    ///   - paymentsSkipped: How many card payments were left out.
    public init(
        rowsProcessed: Int = 0,
        added: Int = 0,
        exactDuplicatesSkipped: Int = 0,
        conflictsRaised: Int = 0,
        conflictsResolved: Int = 0,
        paymentsSkipped: Int = 0
    ) {
        self.rowsProcessed = rowsProcessed
        self.added = added
        self.exactDuplicatesSkipped = exactDuplicatesSkipped
        self.conflictsRaised = conflictsRaised
        self.conflictsResolved = conflictsResolved
        self.paymentsSkipped = paymentsSkipped
    }
}

/// Reading an outcome back to the user.
extension ImportOutcome {

    /// A one-line summary, in the shape ``BackupImporter/summary(of:)`` established.
    ///
    /// Zero clauses are omitted rather than printed as "0 skipped", so a clean import reads
    /// as one short sentence instead of a row of zeroes.
    public var summary: String {
        guard rowsProcessed > 0 else { return "Nothing to import." }
        var parts = ["\(rowsProcessed) \(rowsProcessed == 1 ? "row" : "rows")"]
        if added > 0 { parts.append("\(added) added") }
        if exactDuplicatesSkipped > 0 {
            parts.append("\(exactDuplicatesSkipped) already in your ledger")
        }
        if pendingConflicts > 0 { parts.append("\(pendingConflicts) to check") }
        if conflictsResolved > 0 { parts.append("\(conflictsResolved) resolved") }
        if added == 0 && conflictsRaised == 0 && exactDuplicatesSkipped > 0 {
            return parts.joined(separator: " · ") + " — nothing new"
        }
        return parts.joined(separator: " · ")
    }

    /// The note about card payments, or `nil` when none were skipped.
    public var paymentNote: String? {
        guard paymentsSkipped > 0 else { return nil }
        return SkipReason.cardPaymentExplanation
    }

    /// Builds an outcome from a plan.
    /// - Parameters:
    ///   - plan: The plan that was applied.
    ///   - conflictsResolved: How many conflicts the user has resolved so far.
    /// - Returns: The outcome.
    public static func of(_ plan: ImportPlan, conflictsResolved: Int = 0) -> ImportOutcome {
        ImportOutcome(
            rowsProcessed: plan.rowsProcessed,
            added: plan.additions.count,
            exactDuplicatesSkipped: plan.skipped.count { $0.reason == .exactDuplicate },
            conflictsRaised: plan.conflicts.count,
            conflictsResolved: conflictsResolved,
            paymentsSkipped: plan.skipped.count { $0.reason == .cardPayment }
        )
    }
}
