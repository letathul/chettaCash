import Foundation
import Domain

/// A card's statement, ready for display (§4.6).
public struct StatementSummary: Identifiable, Sendable {
    /// The underlying statement.
    public let statement: Domain.CardStatement
    /// How much has been allocated against it.
    public let paidCents: Int
    /// How much is still due.
    public let outstandingCents: Int

    /// The statement's identity.
    public var id: UUID { statement.id }
    /// The figure the statement asked for, preferring the user's override.
    public var balanceCents: Int { statement.effectiveBalanceCents }
    /// Whether any payment has been allocated.
    public var isPartiallyPaid: Bool { paidCents > 0 && outstandingCents > 0 }
    /// Whether the statement is settled.
    public var isSettled: Bool { outstandingCents == 0 }

    /// Creates a summary.
    /// - Parameters:
    ///   - statement: The underlying statement.
    ///   - paidCents: How much has been allocated.
    ///   - outstandingCents: How much is still due.
    public init(statement: Domain.CardStatement, paidCents: Int, outstandingCents: Int) {
        self.statement = statement
        self.paidCents = paidCents
        self.outstandingCents = outstandingCents
    }
}

/// Applies ``StatementReconciler`` decisions to the stores (§4.6).
@MainActor
public struct StatementCoordinator {
    /// Reads and writes statements and allocations.
    private let statements: any CardStatementRepository
    /// Supplies the card's transactions.
    private let transactions: any TransactionRepository

    /// Creates the coordinator.
    /// - Parameters:
    ///   - statements: Reads and writes statements.
    ///   - transactions: Supplies transactions.
    public init(
        statements: any CardStatementRepository,
        transactions: any TransactionRepository
    ) {
        self.statements = statements
        self.transactions = transactions
    }

    /// Generates missing statements and allocates payments for one card.
    /// - Parameters:
    ///   - account: The card to reconcile.
    ///   - now: The moment deciding which periods have closed.
    /// - Throws: A persistence error if a write fails.
    public func reconcile(account: Domain.Account, now: Date = .now) async throws {
        guard account.kind == .card else { return }
        let cardTransactions = try await transactions.transactions(
            accountID: account.id, in: nil
        )
        let outcome = StatementReconciler.reconcile(
            account: account,
            transactions: cardTransactions,
            existingStatements: try await statements.statements(accountID: account.id),
            existingPayments: try await statements.payments(accountID: account.id),
            now: now
        )
        for statement in outcome.statements {
            try await statements.save(statement)
        }
        for payment in outcome.payments {
            try await statements.save(payment)
        }
    }

    /// Builds display-ready summaries for a card, newest statement first.
    ///
    /// Each statement's paid figure counts every payment made after it closed,
    /// because a statement balance rolls up everything still owed at that moment.
    ///
    /// - Parameter account: The card to summarise.
    /// - Returns: The summaries.
    /// - Throws: A persistence error if a fetch fails.
    public func summaries(for account: Domain.Account) async throws -> [StatementSummary] {
        let stored = try await statements.statements(accountID: account.id)
        let cardTransactions = try await transactions.transactions(
            accountID: account.id, in: nil
        )
        return stored
            .sorted { $0.closingDate > $1.closingDate }
            .map { statement in
                StatementSummary(
                    statement: statement,
                    paidCents: StatementEngine.settledCents(
                        of: statement, transactions: cardTransactions
                    ),
                    outstandingCents: StatementEngine.remainingCents(
                        of: statement, transactions: cardTransactions
                    )
                )
            }
    }

    /// The statement that is actually due, which is the newest closed one.
    ///
    /// Earlier statements are superseded: their balances are rolled into this one,
    /// so presenting them as separately payable would double-count the same debt.
    ///
    /// - Parameter account: The card to inspect.
    /// - Returns: The due statement, or `nil` when no period has closed.
    /// - Throws: A persistence error if a fetch fails.
    public func dueStatement(for account: Domain.Account) async throws -> StatementSummary? {
        try await summaries(for: account).first { $0.statement.isPeriodClosed }
    }

    /// Records the amount the real statement charged in interest and fees (§4.6).
    ///
    /// Entering nothing simply resolves the prompt, which then never asks again for
    /// that statement.
    ///
    /// - Parameters:
    ///   - statement: The statement being resolved.
    ///   - cents: The amount charged, or `nil` to dismiss.
    ///   - billsCategoryID: The Bills category to file the charge under.
    /// - Throws: A persistence error if a write fails.
    public func resolveInterestPrompt(
        for statement: Domain.CardStatement,
        cents: Int?,
        billsCategoryID: UUID?
    ) async throws {
        if let cents, let charge = InterestPrompt.makeCharge(
            for: statement, cents: cents, billsCategoryID: billsCategoryID
        ) {
            try await transactions.save(charge)
        }
        try await statements.save(InterestPrompt.resolved(statement))
    }

    /// Overrides a statement's balance when the real statement differs (§4.6).
    /// - Parameters:
    ///   - statement: The statement to override.
    ///   - cents: The real figure, or `nil` to fall back to the computed one.
    /// - Throws: A persistence error if the write fails.
    public func setOverride(on statement: Domain.CardStatement, cents: Int?) async throws {
        var updated = statement
        updated.overrideBalanceCents = cents
        try await statements.save(updated)
    }
}
