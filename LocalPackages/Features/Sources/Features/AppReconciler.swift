import Foundation
import Domain

/// Runs the background reconciles that must happen on app foreground (§4.5, §4.6).
///
/// These belong to the app, not to any one screen: recurring occurrences must post
/// and statements must close whether or not the user visits the Ledger or a card.
@MainActor
public struct AppReconciler {
    /// Generates recurring occurrences.
    private let recurring: RecurringCoordinator
    /// Generates card statements and allocates payments.
    private let statements: StatementCoordinator
    /// Supplies the accounts whose statements need generating.
    private let accounts: any AccountRepository

    /// Creates the reconciler.
    /// - Parameters:
    ///   - transactions: Reads and writes transactions.
    ///   - rules: Reads and writes recurring rules.
    ///   - statements: Reads and writes card statements.
    ///   - accounts: Supplies accounts.
    public init(
        transactions: any TransactionRepository,
        rules: any RecurringRuleRepository,
        statements: any CardStatementRepository,
        accounts: any AccountRepository
    ) {
        self.recurring = RecurringCoordinator(transactions: transactions, rules: rules)
        self.statements = StatementCoordinator(statements: statements, transactions: transactions)
        self.accounts = accounts
    }

    /// Posts due recurring occurrences and brings every card's statements up to date.
    ///
    /// Silent by design: no prompt and no notification. Occurrences simply appear and
    /// balances update.
    ///
    /// - Parameter now: The moment to reconcile against.
    public func run(now: Date = .now) async {
        // Recurring first: the occurrences it posts can change what a statement owes.
        _ = try? await recurring.reconcile(now: now)
        guard let open = try? await accounts.accounts(includeClosed: false) else { return }
        for account in open where account.kind == .card {
            try? await statements.reconcile(account: account, now: now)
        }
    }
}
