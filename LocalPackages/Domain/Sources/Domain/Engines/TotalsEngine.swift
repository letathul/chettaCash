import Foundation

/// Computes spend, income and net totals for the Ledger banner and Trends charts.
///
/// Three exclusions apply to every total here and are the reason this lives in one
/// place rather than in each view model:
///
/// - Unposted transactions are inert until their date arrives (§4.2).
/// - Both transfer legs are excluded. A card payment moves money without being new
///   spending; counting it would double-count every card purchase — once when
///   swiped, once when paid (§4.3).
/// - Adjustments are excluded. A correction is not spending (§4.4).
public enum TotalsEngine {

    /// Reports whether a transaction contributes to spend, income and net totals.
    ///
    /// - Parameters:
    ///   - transaction: The transaction to test.
    ///   - asOf: The moment to evaluate posting against. Defaults to now.
    /// - Returns: `true` when the transaction is posted and is neither a transfer
    ///   leg nor an adjustment.
    public static func countsTowardTotals(_ transaction: Transaction, asOf: Date = .now) -> Bool {
        guard BalanceEngine.isPosted(transaction, asOf: asOf) else { return false }
        switch transaction.type {
        case .expense, .income:
            return true
        case .transferIn, .transferOut, .adjustment:
            return false
        }
    }

    /// Totals expense transactions over an optional date range.
    ///
    /// - Parameters:
    ///   - transactions: The transactions to consider.
    ///   - range: Restricts the total to this range. `nil` totals all history.
    ///   - asOf: The moment to evaluate posting against. Defaults to now.
    /// - Returns: Total spend in cents, as a positive magnitude.
    public static func spendTotalCents(
        transactions: [Transaction],
        in range: ClosedRange<Date>? = nil,
        asOf: Date = .now
    ) -> Int {
        eligible(transactions, in: range, asOf: asOf)
            .filter { $0.type == .expense }
            .reduce(0) { $0 + $1.amountCents }
    }

    /// Totals income transactions over an optional date range.
    ///
    /// - Parameters:
    ///   - transactions: The transactions to consider.
    ///   - range: Restricts the total to this range. `nil` totals all history.
    ///   - asOf: The moment to evaluate posting against. Defaults to now.
    /// - Returns: Total income in cents, as a positive magnitude.
    public static func incomeTotalCents(
        transactions: [Transaction],
        in range: ClosedRange<Date>? = nil,
        asOf: Date = .now
    ) -> Int {
        eligible(transactions, in: range, asOf: asOf)
            .filter { $0.type == .income }
            .reduce(0) { $0 + $1.amountCents }
    }

    /// Returns income minus spend over an optional date range.
    ///
    /// - Parameters:
    ///   - transactions: The transactions to consider.
    ///   - range: Restricts the total to this range. `nil` totals all history.
    ///   - asOf: The moment to evaluate posting against. Defaults to now.
    /// - Returns: Net flow in cents, negative when spend exceeds income.
    public static func netTotalCents(
        transactions: [Transaction],
        in range: ClosedRange<Date>? = nil,
        asOf: Date = .now
    ) -> Int {
        incomeTotalCents(transactions: transactions, in: range, asOf: asOf)
            - spendTotalCents(transactions: transactions, in: range, asOf: asOf)
    }

    /// Filters to the transactions that may contribute to a total.
    /// - Parameters:
    ///   - transactions: The transactions to filter.
    ///   - range: Optional date range restriction.
    ///   - asOf: The moment to evaluate posting against.
    /// - Returns: Transactions that are posted, in range, and not excluded by type.
    private static func eligible(
        _ transactions: [Transaction],
        in range: ClosedRange<Date>?,
        asOf: Date
    ) -> [Transaction] {
        transactions.filter { transaction in
            guard countsTowardTotals(transaction, asOf: asOf) else { return false }
            guard let range else { return true }
            return range.contains(transaction.date)
        }
    }
}
