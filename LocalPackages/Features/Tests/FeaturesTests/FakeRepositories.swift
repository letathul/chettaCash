import Foundation
@testable import Features
import Domain

/// An in-memory ``AccountRepository`` that mirrors the balance-cache behaviour of
/// the SwiftData implementation, so view-model tests need no persistence stack.
@MainActor
final class FakeAccountRepository: AccountRepository {
    /// Stored accounts, keyed by identifier.
    var accountsByID: [UUID: Domain.Account] = [:]
    /// Stored groups, keyed by identifier.
    var groupsByID: [UUID: Domain.AccountGroup] = [:]
    /// Transactions used to derive balance caches.
    var transactions: [Domain.Transaction] = []
    /// When set, the next call throws it.
    var failure: (any Error)?

    func accounts(includeClosed: Bool) async throws -> [Domain.Account] {
        try failIfNeeded()
        return accountsByID.values
            .filter { includeClosed || !$0.isClosed }
            .sorted { ($0.sortIndex, $0.name) < ($1.sortIndex, $1.name) }
    }

    func account(id: UUID) async throws -> Domain.Account? {
        try failIfNeeded()
        return accountsByID[id]
    }

    func save(_ account: Domain.Account) async throws {
        try failIfNeeded()
        var stored = account
        stored.cachedBalanceCents = BalanceEngine.recalculatedCacheCents(
            account: account, transactions: transactions
        )
        accountsByID[account.id] = stored
    }

    func groups() async throws -> [Domain.AccountGroup] {
        try failIfNeeded()
        return groupsByID.values.sorted { ($0.sortIndex, $0.name) < ($1.sortIndex, $1.name) }
    }

    func save(_ group: Domain.AccountGroup) async throws {
        try failIfNeeded()
        groupsByID[group.id] = group
    }

    func recalculateAllBalances() async throws {
        try failIfNeeded()
        for (id, account) in accountsByID {
            accountsByID[id]?.cachedBalanceCents = BalanceEngine.recalculatedCacheCents(
                account: account, transactions: transactions
            )
        }
    }

    /// Throws and clears any queued failure.
    private func failIfNeeded() throws {
        if let failure { self.failure = nil; throw failure }
    }
}

/// An in-memory ``TransactionRepository`` that keeps the account repository's
/// derived balances in step, so the close flow can be exercised end to end.
@MainActor
final class FakeTransactionRepository: TransactionRepository {
    /// The account repository whose caches are refreshed after each write.
    private let accounts: FakeAccountRepository
    /// When set, the next write throws it.
    var failure: (any Error)?

    /// Creates the fake.
    /// - Parameter accounts: The account repository to keep in step.
    init(accounts: FakeAccountRepository) {
        self.accounts = accounts
    }

    /// Throws and clears any queued failure.
    private func failIfNeeded() throws {
        if let failure { self.failure = nil; throw failure }
    }

    func transactions(
        accountID: UUID?,
        in range: ClosedRange<Date>?
    ) async throws -> [Domain.Transaction] {
        accounts.transactions
            .filter { accountID == nil || $0.accountID == accountID }
            .filter { range?.contains($0.date) ?? true }
    }

    func transferLegs(groupID: UUID) async throws -> [Domain.Transaction] {
        accounts.transactions.filter { $0.transferGroupID == groupID }
    }

    /// Upserts by identifier, matching ``SwiftDataTransactionRepository``: saving an
    /// edited transaction must replace the stored one, never append a duplicate.
    func save(_ transaction: Domain.Transaction) async throws {
        try failIfNeeded()
        upsert(transaction)
        try await accounts.recalculateAllBalances()
    }

    func saveTransfer(outLeg: Domain.Transaction, inLeg: Domain.Transaction) async throws {
        upsert(outLeg)
        upsert(inLeg)
        try await accounts.recalculateAllBalances()
    }

    /// Replaces the stored transaction with the same identifier, or appends it.
    /// - Parameter transaction: The transaction to store.
    private func upsert(_ transaction: Domain.Transaction) {
        if let index = accounts.transactions.firstIndex(where: { $0.id == transaction.id }) {
            accounts.transactions[index] = transaction
        } else {
            accounts.transactions.append(transaction)
        }
    }

    func delete(id: UUID) async throws {
        guard let target = accounts.transactions.first(where: { $0.id == id }) else { return }
        if let groupID = target.transferGroupID {
            try await deleteTransfer(groupID: groupID)
        } else {
            accounts.transactions.removeAll { $0.id == id }
            try await accounts.recalculateAllBalances()
        }
    }

    func deleteTransfer(groupID: UUID) async throws {
        accounts.transactions.removeAll { $0.transferGroupID == groupID }
        try await accounts.recalculateAllBalances()
    }
}

/// An ``AppSettingsStore`` that records whether a save happened.
@MainActor
final class FakeSettingsStore: AppSettingsStore {
    /// How many times ``save(_:)`` was called.
    var saveCount = 0

    func load(into settings: AppSettings) {}

    func save(_ settings: AppSettings) {
        saveCount += 1
    }
}

/// An in-memory ``CategoryRepository``.
@MainActor
final class FakeCategoryRepository: CategoryRepository {
    /// Stored categories, keyed by identifier.
    var categoriesByID: [UUID: Domain.Category] = [:]

    func selectableCategories(context: CategoryContext) async throws -> [Domain.Category] {
        try await allCategories()
            .filter { $0.context == context && !$0.isArchived }
            .filter { !SystemCategoryID.isSystem($0.id) }
    }

    func allCategories() async throws -> [Domain.Category] {
        categoriesByID.values.sorted { ($0.sortIndex, $0.label) < ($1.sortIndex, $1.label) }
    }

    func save(_ category: Domain.Category) async throws {
        categoriesByID[category.id] = category
    }

    func archive(id: UUID) async throws {
        categoriesByID[id]?.isArchived = true
    }
}

/// An in-memory ``RecurringRuleRepository``.
@MainActor
final class FakeRecurringRuleRepository: RecurringRuleRepository {
    /// Stored rules, keyed by identifier.
    var rulesByID: [UUID: Domain.RecurringRule] = [:]

    func rules(activeOnly: Bool) async throws -> [Domain.RecurringRule] {
        rulesByID.values
            .filter { !activeOnly || $0.isActive }
            .sorted { $0.startDate < $1.startDate }
    }

    func rule(id: UUID) async throws -> Domain.RecurringRule? {
        rulesByID[id]
    }

    func save(_ rule: Domain.RecurringRule) async throws {
        rulesByID[rule.id] = rule
    }

    func delete(id: UUID) async throws {
        rulesByID[id] = nil
    }
}

/// An in-memory ``CardStatementRepository``.
@MainActor
final class FakeCardStatementRepository: CardStatementRepository {
    /// Stored statements, keyed by identifier.
    var statementsByID: [UUID: Domain.CardStatement] = [:]
    /// Stored allocations, keyed by identifier.
    var paymentsByID: [UUID: Domain.StatementPayment] = [:]

    func statements(accountID: UUID?) async throws -> [Domain.CardStatement] {
        statementsByID.values
            .filter { accountID == nil || $0.accountID == accountID }
            .sorted { $0.closingDate < $1.closingDate }
    }

    func payments(accountID: UUID?) async throws -> [Domain.StatementPayment] {
        let scoped = try await statements(accountID: accountID).map(\.id)
        return paymentsByID.values.filter { payment in
            guard accountID != nil else { return true }
            guard let statementID = payment.statementID else { return false }
            return scoped.contains(statementID)
        }
    }

    func save(_ statement: Domain.CardStatement) async throws {
        statementsByID[statement.id] = statement
    }

    func save(_ payment: Domain.StatementPayment) async throws {
        paymentsByID[payment.id] = payment
    }
}

/// An in-memory ``ProductRepository``.
///
/// Upholds the same invariant the SwiftData repository does: a product whose purchase
/// is unknown is refused rather than stored. A fake that accepted orphans would let a
/// test pass on a write the real store rejects.
@MainActor
final class FakeProductRepository: ProductRepository {
    /// Stored products, keyed by identifier.
    var productsByID: [UUID: Domain.Product] = [:]
    /// Identifiers of the transactions that exist, when the fake is policing them.
    ///
    /// Left `nil` by default so tests that do not care need no setup.
    var knownTransactionIDs: Set<UUID>?
    /// An error the next call throws, then clears.
    var failure: (any Error)?

    func products() async throws -> [Domain.Product] {
        try failIfNeeded()
        return productsByID.values.sorted { $0.sortIndex < $1.sortIndex }
    }

    func products(transactionID: UUID) async throws -> [Domain.Product] {
        try failIfNeeded()
        return productsByID.values
            .filter { $0.transactionID == transactionID }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    func product(id: UUID) async throws -> Domain.Product? {
        try failIfNeeded()
        return productsByID[id]
    }

    func save(_ product: Domain.Product) async throws {
        try failIfNeeded()
        if let knownTransactionIDs, !knownTransactionIDs.contains(product.transactionID) {
            throw ProductRepositoryError.unknownTransaction(product.transactionID)
        }
        // Upsert by id, like the SwiftData repository: appending would make an edit
        // look like a duplicate.
        productsByID[product.id] = product
    }

    func delete(id: UUID) async throws {
        try failIfNeeded()
        productsByID[id] = nil
    }

    /// Throws the queued failure, if one is set, and clears it.
    /// - Throws: The queued error.
    private func failIfNeeded() throws {
        if let failure {
            self.failure = nil
            throw failure
        }
    }
}
