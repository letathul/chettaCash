import Foundation

/// Reads and writes accounts and their groups.
public protocol AccountRepository: Sendable {
    /// Fetches accounts in sort order.
    /// - Parameter includeClosed: Whether closed accounts are returned. Pickers pass
    ///   `false`; the Ledger's account filter passes `true` so history stays browsable.
    /// - Returns: The matching accounts.
    /// - Throws: A persistence error if the fetch fails.
    func accounts(includeClosed: Bool) async throws -> [Account]

    /// Fetches a single account.
    /// - Parameter id: The account's identifier.
    /// - Returns: The account, or `nil` if no account has that identifier.
    /// - Throws: A persistence error if the fetch fails.
    func account(id: UUID) async throws -> Account?

    /// Inserts or updates an account, refreshing its balance cache.
    /// - Parameter account: The account to persist.
    /// - Throws: A persistence error if the write fails.
    func save(_ account: Account) async throws

    /// Fetches all account groups in sort order.
    /// - Returns: The groups.
    /// - Throws: A persistence error if the fetch fails.
    func groups() async throws -> [AccountGroup]

    /// Inserts or updates an account group.
    /// - Parameter group: The group to persist.
    /// - Throws: A persistence error if the write fails.
    func save(_ group: AccountGroup) async throws

    /// Rebuilds every account's balance cache from its full transaction history (§4.1).
    /// - Throws: A persistence error if the rebuild fails.
    func recalculateAllBalances() async throws
}

/// Reads and writes ledger transactions.
///
/// Implementations must uphold two invariants.
///
/// The transfer invariant from §4.3: a half-transfer must never exist in the database,
/// so deleting either leg deletes both.
///
/// The account invariant: a transaction naming an account that does not exist must be
/// refused with ``TransactionRepositoryError/unknownAccount(_:)``, never written with the
/// relationship silently left empty. A row filed against nothing still appears in the
/// Ledger and still counts toward spend totals while moving no balance, which is worse
/// than a refusal because nothing announces it. A `nil` ``Transaction/accountID`` is a
/// different thing and stays legal — that is a §15.5 parked entry, which is unassigned on
/// purpose.
public protocol TransactionRepository: Sendable {
    /// Fetches transactions, newest first.
    /// - Parameters:
    ///   - accountID: Restricts results to one account. `nil` returns all accounts.
    ///   - range: Restricts results to a date range. `nil` returns all history.
    /// - Returns: The matching transactions, including unposted ones.
    /// - Throws: A persistence error if the fetch fails.
    func transactions(accountID: UUID?, in range: ClosedRange<Date>?) async throws -> [Transaction]

    /// Fetches both legs of a transfer.
    /// - Parameter groupID: The shared transfer group identifier.
    /// - Returns: The transfer's legs, normally two.
    /// - Throws: A persistence error if the fetch fails.
    func transferLegs(groupID: UUID) async throws -> [Transaction]

    /// Inserts or updates a transaction and refreshes its account's balance cache.
    /// - Parameter transaction: The transaction to persist.
    /// - Throws: A persistence error if the write fails.
    func save(_ transaction: Transaction) async throws

    /// Inserts or updates many transactions in one write.
    ///
    /// Each affected account's balance cache is refreshed once rather than once per row.
    /// A statement import is the only caller that writes hundreds of transactions at a
    /// time, and refreshing per row makes it quadratic: every refresh reduces over the
    /// account's whole history.
    ///
    /// - Parameter transactions: The transactions to persist.
    /// - Throws: A persistence error if the write fails.
    func saveAll(_ transactions: [Transaction]) async throws

    /// Persists both legs of a transfer atomically.
    /// - Parameters:
    ///   - outLeg: The outflow leg on the source account.
    ///   - inLeg: The inflow leg on the destination account.
    /// - Throws: A persistence error if the write fails.
    func saveTransfer(outLeg: Transaction, inLeg: Transaction) async throws

    /// Deletes a transaction, or both legs when it belongs to a transfer.
    /// - Parameter id: The transaction's identifier.
    /// - Throws: A persistence error if the delete fails.
    func delete(id: UUID) async throws

    /// Deletes both legs of a transfer.
    /// - Parameter groupID: The shared transfer group identifier.
    /// - Throws: A persistence error if the delete fails.
    func deleteTransfer(groupID: UUID) async throws
}

/// A correct but unoptimised bulk write.
extension TransactionRepository {

    /// Saves each transaction in turn.
    ///
    /// Supplied so an implementation only overrides this when it can do better than a
    /// loop — a store-backed one can, an in-memory test double has nothing to gain.
    ///
    /// - Parameter transactions: The transactions to persist.
    /// - Throws: A persistence error if a write fails.
    public func saveAll(_ transactions: [Transaction]) async throws {
        for transaction in transactions {
            try await save(transaction)
        }
    }
}

/// Reads and writes categories.
public protocol CategoryRepository: Sendable {
    /// Fetches the categories a picker should offer.
    ///
    /// Excludes archived categories and the system categories in ``SystemCategoryID``.
    /// Pickers must be built from this rather than from any hardcoded list (§4.8).
    ///
    /// - Parameter context: Which picker the categories are for.
    /// - Returns: The selectable categories in sort order.
    /// - Throws: A persistence error if the fetch fails.
    func selectableCategories(context: CategoryContext) async throws -> [Category]

    /// Fetches every category, including archived and system ones.
    /// - Returns: All categories in sort order.
    /// - Throws: A persistence error if the fetch fails.
    func allCategories() async throws -> [Category]

    /// Inserts or updates a category.
    /// - Parameter category: The category to persist.
    /// - Throws: A persistence error if the write fails.
    func save(_ category: Category) async throws

    /// Archives a category, hiding it from pickers while leaving history intact (§4.8).
    /// - Parameter id: The category's identifier.
    /// - Throws: A persistence error if the write fails.
    func archive(id: UUID) async throws
}

/// Reads and writes recurring rules.
///
/// Phase 5 creates and edits rules from the transaction form; the lazy generation
/// engine that turns them into occurrences arrives in Phase 6 (§4.5).
public protocol RecurringRuleRepository: Sendable {
    /// Fetches rules.
    /// - Parameter activeOnly: Whether to return only rules still generating occurrences.
    /// - Returns: The matching rules.
    /// - Throws: A persistence error if the fetch fails.
    func rules(activeOnly: Bool) async throws -> [RecurringRule]

    /// Fetches a single rule.
    /// - Parameter id: The rule's identifier.
    /// - Returns: The rule, or `nil` if none matches.
    /// - Throws: A persistence error if the fetch fails.
    func rule(id: UUID) async throws -> RecurringRule?

    /// Inserts or updates a rule.
    /// - Parameter rule: The rule to persist.
    /// - Throws: A persistence error if the write fails.
    func save(_ rule: RecurringRule) async throws

    /// Deletes a rule, leaving any transactions it already generated in place.
    /// - Parameter id: The rule's identifier.
    /// - Throws: A persistence error if the delete fails.
    func delete(id: UUID) async throws
}

/// Reads and writes credit-card statements and their payment allocations.
public protocol CardStatementRepository: Sendable {
    /// Fetches a card's statements, oldest first.
    /// - Parameter accountID: The card to list, or `nil` for every card.
    /// - Returns: The matching statements.
    /// - Throws: A persistence error if the fetch fails.
    func statements(accountID: UUID?) async throws -> [CardStatement]

    /// Fetches payment allocations.
    /// - Parameter accountID: The card to list, or `nil` for every card.
    /// - Returns: The matching allocations.
    /// - Throws: A persistence error if the fetch fails.
    func payments(accountID: UUID?) async throws -> [StatementPayment]

    /// Inserts or updates a statement.
    /// - Parameter statement: The statement to persist.
    /// - Throws: A persistence error if the write fails.
    func save(_ statement: CardStatement) async throws

    /// Inserts a payment allocation.
    /// - Parameter payment: The allocation to persist.
    /// - Throws: A persistence error if the write fails.
    func save(_ payment: StatementPayment) async throws
}

/// Reads and writes products, which always belong to a transaction (§7.3, §7.8).
public protocol ProductRepository: Sendable {
    /// Fetches every product.
    /// - Returns: Every product, newest purchase first.
    /// - Throws: A persistence error if the fetch fails.
    func products() async throws -> [Product]

    /// Fetches the products belonging to one purchase, in their display order.
    /// - Parameter transactionID: The purchase's identifier.
    /// - Returns: That purchase's products, ordered by `sortIndex`.
    /// - Throws: A persistence error if the fetch fails.
    func products(transactionID: UUID) async throws -> [Product]

    /// Fetches a single product.
    /// - Parameter id: The product's identifier.
    /// - Returns: The product, or `nil` if none matches.
    /// - Throws: A persistence error if the fetch fails.
    func product(id: UUID) async throws -> Product?

    /// Inserts or updates a product.
    ///
    /// Implementations must reject a product whose `transactionID` matches no
    /// transaction rather than persisting an orphan: a product only exists as part of
    /// a purchase (§7.8).
    ///
    /// - Parameter product: The product to persist.
    /// - Throws: ``ProductRepositoryError/unknownTransaction(_:)`` when the purchase does
    ///   not exist, or a persistence error if the write fails.
    func save(_ product: Product) async throws

    /// Deletes a product, leaving its purchase in place.
    ///
    /// The purchase stays because it records money that was really spent, and its
    /// receipt may still cover sibling products.
    ///
    /// - Parameter id: The product's identifier.
    /// - Throws: A persistence error if the delete fails.
    func delete(id: UUID) async throws
}

/// Reads and writes merchant-to-category pins (§4.8).
///
/// A pin is keyed by ``MerchantCategoryIndex/key(for:)``, not by the raw merchant
/// name, so implementations must upsert on `merchantKey` rather than on `id`: pinning
/// `Whole Foods Mkt` after pinning `WHOLE FOODS MKT #10234` must replace that pin, not
/// add a second one that never wins.
public protocol MerchantCategoryRuleRepository: Sendable {
    /// Fetches every pin, most recently updated first.
    /// - Returns: The pins.
    /// - Throws: A persistence error if the fetch fails.
    func rules() async throws -> [MerchantCategoryRule]

    /// Fetches the pin for one normalised merchant key.
    /// - Parameter merchantKey: The key, from ``MerchantCategoryIndex/key(for:)``.
    /// - Returns: The pin, or `nil` when the merchant has none.
    /// - Throws: A persistence error if the fetch fails.
    func rule(merchantKey: String) async throws -> MerchantCategoryRule?

    /// Inserts or updates a pin, replacing any pin sharing its `merchantKey`.
    /// - Parameter rule: The pin to persist.
    /// - Throws: A persistence error if the write fails.
    func save(_ rule: MerchantCategoryRule) async throws

    /// Deletes a pin, leaving every transaction it ever categorised alone.
    /// - Parameter id: The pin's identifier.
    /// - Throws: A persistence error if the delete fails.
    func delete(id: UUID) async throws
}

/// Reads and writes saved price comparisons.
public protocol ComparisonRepository: Sendable {
    /// Fetches comparisons in sort order.
    /// - Returns: Every saved comparison.
    /// - Throws: A persistence error if the fetch fails.
    func comparisons() async throws -> [Comparison]

    /// Inserts or updates a comparison.
    /// - Parameter comparison: The comparison to persist.
    /// - Throws: A persistence error if the write fails.
    func save(_ comparison: Comparison) async throws

    /// Deletes a comparison.
    ///
    /// Callers must check ``ComparisonEvaluator/canRemove(id:from:)`` first: the last
    /// remaining comparison can never be deleted (§7.5).
    ///
    /// - Parameter id: The comparison's identifier.
    /// - Throws: A persistence error if the delete fails.
    func delete(id: UUID) async throws
}
