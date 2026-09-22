import Foundation
import Domain

/// Rebuilding the Dashboard's derived figures (§7.1, §7.2).
///
/// Split from ``DashboardViewModel`` to keep each file within the 300-line limit.
extension DashboardViewModel {

    /// Recomputes every derived figure in one pass.
    ///
    /// Call after the data changes and after the display currency changes — the recent
    /// rows carry formatted amounts and resolved names.
    public func refresh() {
        accountsByID = Dictionary(
            accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        categoriesByID = Dictionary(
            categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )

        openAccounts = accounts.filter { !$0.isClosed }
        availableCashCents = BalanceEngine.availableCashCents(
            accounts: accounts, transactions: transactions
        )
        netWorthCents = BalanceEngine.netWorthCents(
            accounts: accounts, transactions: transactions
        )
        spendTrend = TrendsEngine.monthlySpend(transactions: transactions)
        netWorthTrend = TrendsEngine.monthlyNetWorth(
            accounts: accounts, transactions: transactions
        )
        activeSubscriptions = rules.filter(\.isActive).sorted { $0.name < $1.name }

        // One pass over the transactions for the next charge of every rule, rather than
        // one pass per rule from inside the subscriptions list's body.
        let now = Date.now
        var nextCharge: [UUID: Date] = [:]
        for transaction in transactions {
            guard let ruleID = transaction.recurringRuleID, transaction.date > now else {
                continue
            }
            if let existing = nextCharge[ruleID], existing <= transaction.date { continue }
            nextCharge[ruleID] = transaction.date
        }
        nextChargeByRuleID = nextCharge

        recentTransactions = transactions
            .filter { BalanceEngine.isPosted($0) }
            .sorted { $0.date > $1.date }
            .prefix(Self.recentRowLimit)
            .map { $0 }

        let currencyCode = settings.currencyCode
        recentRows = recentTransactions.map { recentRow(for: $0, currencyCode: currencyCode) }
    }

    /// Renders one Recent row.
    /// - Parameters:
    ///   - transaction: The transaction to show.
    ///   - currencyCode: The display currency.
    /// - Returns: The row model.
    private func recentRow(
        for transaction: Domain.Transaction,
        currencyCode: String
    ) -> RecentRowModel {
        let accountName = account(id: transaction.accountID)?.name ?? "No account"
        let label = category(id: transaction.categoryID)?.label
            ?? (transaction.transferGroupID != nil ? "Transfer" : "Uncategorised")
        let cents = BalanceEngine.signedAmountCents(for: transaction)
        let magnitude = CurrencyFormatter.string(
            fromCents: abs(cents), currencyCode: currencyCode
        )
        return RecentRowModel(
            id: transaction.id,
            title: transaction.merchant.isEmpty
                ? fallbackTitle(for: transaction)
                : transaction.merchant,
            subtitle: "\(label) · \(accountName)",
            amountText: cents == 0 ? magnitude : (cents < 0 ? "−" : "+") + magnitude,
            tone: transaction.type == .income ? .positive : .primary,
            transaction: transaction
        )
    }

    /// The title used when no merchant was entered.
    /// - Parameter transaction: The transaction to describe.
    /// - Returns: The stand-in title.
    private func fallbackTitle(for transaction: Domain.Transaction) -> String {
        switch transaction.type {
        case .adjustment: return "Balance adjustment"
        case .transferIn, .transferOut: return "Transfer"
        default: return "No merchant"
        }
    }
}

/// One row in the Dashboard's Recent list, with every string already rendered (§7.1).
struct RecentRowModel: Identifiable, Hashable {
    /// The row's identity, which is the transaction's.
    let id: UUID
    /// The merchant, or a stand-in when the transaction has none.
    let title: String
    /// The "Category · Account" subline.
    let subtitle: String
    /// The signed, currency-formatted amount.
    let amountText: String
    /// Which palette entry the amount reads in.
    let tone: AmountTone
    /// The transaction a tap opens, which is its read-only detail (§7.4).
    let transaction: Domain.Transaction
}
