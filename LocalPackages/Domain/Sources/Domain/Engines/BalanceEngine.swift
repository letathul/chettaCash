import Foundation

/// Derives account balances from transaction history (§4.1, §4.2).
///
/// Balances are never stored as the source of truth. `Account.cachedBalanceCents`
/// is a denormalised cache of ``currentBalanceCents(account:transactions:asOf:)``,
/// rebuilt whenever a transaction changes.
public enum BalanceEngine {

    /// Returns the sign-corrected value a transaction contributes to a balance.
    ///
    /// The sign always comes from `Transaction.type`. Card accounts are not
    /// special-cased here: a card expense is negative like any other expense, and
    /// a card payment is a `transferIn` that moves the balance toward zero (§4.1).
    ///
    /// - Parameter transaction: The transaction to evaluate.
    /// - Returns: The signed contribution in cents. An `adjustment` with no
    ///   `signedOverrideCents` contributes nothing.
    public static func signedAmountCents(for transaction: Transaction) -> Int {
        switch transaction.type {
        case .expense, .transferOut:
            return -transaction.amountCents
        case .income, .transferIn:
            return transaction.amountCents
        case .adjustment:
            return transaction.signedOverrideCents ?? 0
        }
    }

    /// Reports whether a transaction has taken effect (§4.2).
    ///
    /// A transaction dated in the future exists in the database but is inert. Every
    /// aggregate must filter through this rather than comparing dates inline.
    ///
    /// - Parameters:
    ///   - transaction: The transaction to test.
    ///   - asOf: The moment to evaluate against. Defaults to now.
    /// - Returns: `true` when the transaction's date has arrived.
    public static func isPosted(_ transaction: Transaction, asOf: Date = .now) -> Bool {
        transaction.date <= asOf
    }

    /// Computes an account's balance from its opening figure plus posted history.
    ///
    /// - Parameters:
    ///   - account: The account to evaluate.
    ///   - transactions: Transactions to consider. Entries belonging to other
    ///     accounts and entries not yet posted are ignored.
    ///   - asOf: The moment to evaluate against. Defaults to now.
    /// - Returns: The derived balance in cents, negative when a card owes money.
    public static func currentBalanceCents(
        account: Account,
        transactions: [Transaction],
        asOf: Date = .now
    ) -> Int {
        let delta = transactions.reduce(0) { running, transaction in
            guard transaction.accountID == account.id,
                  isPosted(transaction, asOf: asOf) else { return running }
            return running + signedAmountCents(for: transaction)
        }
        return account.openingBalanceCents + delta
    }

    /// Recomputes the value that belongs in `Account.cachedBalanceCents`.
    ///
    /// This is the pure half of the "Recalculate balances" maintenance action;
    /// persisting the result is the Data layer's responsibility.
    ///
    /// - Parameters:
    ///   - account: The account whose cache is being rebuilt.
    ///   - transactions: Transactions to consider.
    /// - Returns: The balance in cents to store in the cache.
    public static func recalculatedCacheCents(account: Account, transactions: [Transaction]) -> Int {
        currentBalanceCents(account: account, transactions: transactions)
    }

    /// Sums the balances of every open spending account (§4.1).
    ///
    /// Credit cards are excluded: Available Cash answers "what can I spend".
    ///
    /// - Parameters:
    ///   - accounts: All accounts, open and closed.
    ///   - transactions: All transactions across those accounts.
    ///   - asOf: The moment to evaluate against. Defaults to now.
    /// - Returns: Available Cash in cents.
    public static func availableCashCents(
        accounts: [Account],
        transactions: [Transaction],
        asOf: Date = .now
    ) -> Int {
        sumBalances(
            of: accounts.filter { !$0.isClosed && $0.kind == .account },
            transactions: transactions,
            asOf: asOf
        )
    }

    /// Sums the balances of every open account including credit cards (§4.1).
    ///
    /// Card balances are negative when money is owed, so debt reduces this figure.
    ///
    /// - Parameters:
    ///   - accounts: All accounts, open and closed.
    ///   - transactions: All transactions across those accounts.
    ///   - asOf: The moment to evaluate against. Defaults to now.
    /// - Returns: Net Worth in cents.
    public static func netWorthCents(
        accounts: [Account],
        transactions: [Transaction],
        asOf: Date = .now
    ) -> Int {
        sumBalances(of: accounts.filter { !$0.isClosed }, transactions: transactions, asOf: asOf)
    }

    /// Normalises a typed opening balance for the account's kind (§7.9).
    ///
    /// A card's opening balance is stored negative regardless of the sign the user
    /// typed, because a card balance is negative when money is owed. This applies
    /// to the opening balance only — the running balance's sign always comes from
    /// transaction types.
    ///
    /// - Parameters:
    ///   - cents: The value the user entered, in cents.
    ///   - kind: The account's kind.
    /// - Returns: The value to store as the opening balance.
    public static func normalizedOpeningBalanceCents(_ cents: Int, kind: AccountKind) -> Int {
        switch kind {
        case .account: return cents
        case .card: return -abs(cents)
        }
    }

    /// Sums derived balances across a set of accounts.
    /// - Parameters:
    ///   - accounts: The accounts to total.
    ///   - transactions: Transactions to consider.
    ///   - asOf: The moment to evaluate against.
    /// - Returns: The combined balance in cents.
    private static func sumBalances(
        of accounts: [Account],
        transactions: [Transaction],
        asOf: Date
    ) -> Int {
        accounts.reduce(0) { running, account in
            running + currentBalanceCents(account: account, transactions: transactions, asOf: asOf)
        }
    }
}
