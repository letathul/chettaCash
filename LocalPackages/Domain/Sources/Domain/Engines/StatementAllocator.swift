import Foundation

/// The result of allocating card payments across statements (§4.6).
public struct AllocationPlan: Equatable, Sendable {
    /// Allocation records to insert.
    public var payments: [StatementPayment]
    /// Payment amounts that found no open statement to settle, keyed by transaction.
    ///
    /// Overflow is not an error: it reduces the current balance without being
    /// allocated, which is what paying more than the statement asked for means.
    public var overflowCentsByTransaction: [UUID: Int]

    /// Creates a plan.
    /// - Parameters:
    ///   - payments: Allocation records to insert.
    ///   - overflowCentsByTransaction: Unallocated amounts, keyed by transaction.
    public init(
        payments: [StatementPayment] = [],
        overflowCentsByTransaction: [UUID: Int] = [:]
    ) {
        self.payments = payments
        self.overflowCentsByTransaction = overflowCentsByTransaction
    }
}

/// Allocates card payments to statements (§4.6).
///
/// A `transferIn` to a card account allocates to the **oldest open statement first**.
/// Anything beyond the statement balance reduces the current balance without being
/// allocated, so overpaying never invents a credit against a future statement.
public enum StatementAllocator {

    /// Allocates every unrecorded payment across the card's open statements.
    ///
    /// - Parameters:
    ///   - paymentTransactions: `transferIn` transactions on the card, any order.
    ///   - statements: The card's statements, any order.
    ///   - existingPayments: Allocations already recorded, so a rerun is idempotent.
    /// - Returns: The allocations to insert and any overflow.
    public static func allocate(
        paymentTransactions: [Transaction],
        statements: [CardStatement],
        existingPayments: [StatementPayment] = []
    ) -> AllocationPlan {
        let openStatements = statements
            .filter { $0.isPeriodClosed }
            .sorted { $0.closingDate < $1.closingDate }
        let pending = paymentTransactions
            .filter { $0.type == .transferIn }
            .filter { transaction in
                !existingPayments.contains { $0.transactionID == transaction.id }
            }
            .sorted { $0.date < $1.date }

        var allocatedByStatement = Dictionary(
            grouping: existingPayments, by: { $0.statementID ?? UUID() }
        ).mapValues { $0.reduce(0) { $0 + $1.amountCents } }
        var plan = AllocationPlan()

        for payment in pending {
            var remaining = payment.amountCents
            for statement in openStatements {
                guard remaining > 0 else { break }
                // A payment cannot settle a statement that had not closed when it was made.
                guard payment.date > statement.closingDate else { continue }

                let alreadyPaid = allocatedByStatement[statement.id] ?? 0
                let outstanding = max(0, statement.effectiveBalanceCents - alreadyPaid)
                guard outstanding > 0 else { continue }

                let applied = min(remaining, outstanding)
                plan.payments.append(
                    StatementPayment(
                        statementID: statement.id,
                        transactionID: payment.id,
                        amountCents: applied
                    )
                )
                allocatedByStatement[statement.id] = alreadyPaid + applied
                remaining -= applied
            }
            if remaining > 0 {
                plan.overflowCentsByTransaction[payment.id] = remaining
            }
        }
        return plan
    }
}
