import Foundation
import Domain

/// Applies ``RecurringEngine`` and ``SeriesPlanner`` decisions to the stores (§4.5).
///
/// The engine and planner are pure; this is the thin layer that persists what they
/// decide. Reconcile runs on app foreground and after any rule edit.
@MainActor
public struct RecurringCoordinator {
    /// Reads and writes ledger transactions.
    private let transactions: any TransactionRepository
    /// Reads and writes recurring rules.
    private let rules: any RecurringRuleRepository

    /// Creates the coordinator.
    /// - Parameters:
    ///   - transactions: Reads and writes transactions.
    ///   - rules: Reads and writes recurring rules.
    public init(transactions: any TransactionRepository, rules: any RecurringRuleRepository) {
        self.transactions = transactions
        self.rules = rules
    }

    /// Generates any missed occurrences and the next future one for every active rule.
    ///
    /// Posting is silent: no prompt, no notification. The occurrences simply appear
    /// and balances update.
    ///
    /// - Parameter now: The moment deciding what has posted.
    /// - Returns: How many occurrences were written.
    /// - Throws: A persistence error if a write fails.
    @discardableResult
    public func reconcile(now: Date = .now) async throws -> Int {
        let allRules = try await rules.rules(activeOnly: false)
        guard !allRules.isEmpty else { return 0 }
        let existing = try await transactions.transactions(accountID: nil, in: nil)

        let outcome = RecurringEngine.reconcile(
            rules: allRules, existingTransactions: existing, now: now
        )
        for rule in outcome.updatedRules {
            try await rules.save(rule)
        }
        for occurrence in outcome.newTransactions {
            try await transactions.save(occurrence)
        }
        return outcome.newTransactions.count
    }

    /// Applies a scoped edit to a series.
    /// - Parameters:
    ///   - rule: The rule the target belongs to.
    ///   - target: The occurrence the user opened.
    ///   - scope: How far the edit reaches.
    ///   - edited: The target carrying the user's new values.
    /// - Throws: A persistence error if a write fails.
    public func applyEdit(
        rule: Domain.RecurringRule,
        target: Domain.Transaction,
        scope: SeriesScope,
        edited: Domain.Transaction
    ) async throws {
        let series = try await series(of: rule)
        let plan = SeriesPlanner.planEdit(
            series: series, target: target, scope: scope, edited: edited
        )
        try await apply(plan)
    }

    /// Applies a scoped delete to a series.
    /// - Parameters:
    ///   - rule: The rule the target belongs to.
    ///   - target: The occurrence the user opened.
    ///   - scope: How far the delete reaches.
    /// - Throws: A persistence error if a write fails.
    public func applyDelete(
        rule: Domain.RecurringRule,
        target: Domain.Transaction,
        scope: SeriesScope
    ) async throws {
        let series = try await series(of: rule)
        let plan = SeriesPlanner.planDelete(series: series, target: target, scope: scope)
        try await apply(plan)
    }

    /// Fetches a rule together with every occurrence it generated, oldest first.
    /// - Parameter rule: The rule to list.
    /// - Returns: The series.
    /// - Throws: A persistence error if the fetch fails.
    private func series(of rule: Domain.RecurringRule) async throws -> RecurringSeries {
        let occurrences = try await transactions.transactions(accountID: nil, in: nil)
            .filter { $0.recurringRuleID == rule.id }
            .sorted { $0.date < $1.date }
        return RecurringSeries(rule: rule, occurrences: occurrences)
    }

    /// Writes a plan in an order that never leaves a dangling reference.
    /// - Parameter plan: The writes to apply.
    /// - Throws: A persistence error if a write fails.
    private func apply(_ plan: SeriesPlan) async throws {
        // Rules first, so re-pointed transactions always find their new rule.
        for rule in plan.updatedRules {
            try await rules.save(rule)
        }
        for transaction in plan.updatedTransactions {
            try await transactions.save(transaction)
        }
        for id in plan.deletedTransactionIDs {
            try await transactions.delete(id: id)
        }
        // Rules last, once nothing points at them any more.
        for id in plan.deletedRuleIDs {
            try await rules.delete(id: id)
        }
    }
}
