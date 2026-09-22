import Foundation
import SwiftData
import Domain

/// SwiftData-backed ``TransactionRepository``.
///
/// Upholds the transfer invariant from §4.3: deleting either leg deletes both, so a
/// half-transfer can never exist in the database regardless of which caller asks.
@ModelActor
public actor SwiftDataTransactionRepository: TransactionRepository {

    /// Fetches transactions, newest first.
    /// - Parameters:
    ///   - accountID: Restricts results to one account, or `nil` for all.
    ///   - range: Restricts results to a date range, or `nil` for all history.
    /// - Returns: The matching transactions, including unposted ones.
    /// - Throws: A persistence error if the fetch fails.
    public func transactions(
        accountID: UUID?,
        in range: ClosedRange<Date>?
    ) async throws -> [Domain.Transaction] {
        let descriptor = FetchDescriptor<TransactionRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
            .filter { accountID == nil || $0.account?.id == accountID }
            .filter { range?.contains($0.date) ?? true }
            .map { $0.toDomain() }
    }

    /// Fetches both legs of a transfer.
    /// - Parameter groupID: The shared transfer group identifier.
    /// - Returns: The transfer's legs.
    /// - Throws: A persistence error if the fetch fails.
    public func transferLegs(groupID: UUID) async throws -> [Domain.Transaction] {
        try legRecords(groupID: groupID).map { $0.toDomain() }
    }

    /// Inserts or updates a transaction and refreshes its account's balance cache.
    /// - Parameter transaction: The transaction to persist.
    /// - Throws: A persistence error if the write fails.
    public func save(_ transaction: Domain.Transaction) async throws {
        try rolledBack {
            try upsert(transaction)
            try refreshCache(accountID: transaction.accountID)
            try modelContext.save()
        }
    }

    /// Inserts or updates many transactions in one store write.
    ///
    /// One commit and one cache refresh per affected account, rather than one of each per
    /// row: ``save(_:)`` recomputes an account's balance from its whole history, so a
    /// statement import routed through it would be quadratic in the card's transaction
    /// count.
    ///
    /// - Parameter transactions: The transactions to persist.
    /// - Throws: A persistence error if the write fails.
    public func saveAll(_ transactions: [Domain.Transaction]) async throws {
        guard !transactions.isEmpty else { return }
        try rolledBack {
            for transaction in transactions {
                try upsert(transaction)
            }
            for accountID in Set(transactions.compactMap(\.accountID)) {
                try refreshCache(accountID: accountID)
            }
            try modelContext.save()
        }
    }

    /// Persists both legs of a transfer together.
    /// - Parameters:
    ///   - outLeg: The outflow leg on the source account.
    ///   - inLeg: The inflow leg on the destination account.
    /// - Throws: A persistence error if the write fails.
    public func saveTransfer(outLeg: Domain.Transaction, inLeg: Domain.Transaction) async throws {
        try rolledBack {
            try upsert(outLeg)
            try upsert(inLeg)
            try refreshCache(accountID: outLeg.accountID)
            try refreshCache(accountID: inLeg.accountID)
            try modelContext.save()
        }
    }

    /// Deletes a transaction, or both legs when it belongs to a transfer.
    /// - Parameter id: The transaction's identifier.
    /// - Throws: A persistence error if the delete fails.
    public func delete(id: UUID) async throws {
        guard let target = try record(id: id) else { return }
        if let groupID = target.transferGroupID {
            try await deleteTransfer(groupID: groupID)
            return
        }
        let affected = target.account?.id
        // The products cascade with the purchase, but their billing rules are only
        // nullified, so a deleted subscription would keep generating occurrences.
        // Take the rules out first, while the products are still reachable.
        for product in target.products ?? [] {
            if let rule = product.recurringRule { modelContext.delete(rule) }
        }
        modelContext.delete(target)
        // Save before rebuilding: until the delete is committed, the account's
        // `transactions` relationship still contains the deleted row and the cache
        // would be recomputed from stale history.
        try modelContext.save()
        try refreshCache(accountID: affected)
        try modelContext.save()
    }

    /// Deletes every leg of a transfer.
    /// - Parameter groupID: The shared transfer group identifier.
    /// - Throws: A persistence error if the delete fails.
    public func deleteTransfer(groupID: UUID) async throws {
        let legs = try legRecords(groupID: groupID)
        let affected = Set(legs.compactMap { $0.account?.id })
        for leg in legs {
            modelContext.delete(leg)
        }
        // Save before rebuilding, for the same reason as in `delete(id:)`.
        try modelContext.save()
        for accountID in affected {
            try refreshCache(accountID: accountID)
        }
        try modelContext.save()
    }

    /// Inserts or updates one transaction without saving.
    ///
    /// A named account must exist. Resolving it to `nil` instead would file the row
    /// against nothing: it would still appear in the Ledger and still count toward spend
    /// totals, while no balance moved and nothing said so. A saved Shortcut holds a picked
    /// account's identifier for months, so a restored backup is enough to produce one.
    ///
    /// A `nil` ``Domain/Transaction/accountID`` is the other case entirely and stays
    /// legal — that is a §15.5 parked entry, unassigned on purpose until the user says
    /// where it belongs.
    ///
    /// - Parameter transaction: The transaction to persist.
    /// - Throws: ``Domain/TransactionRepositoryError/unknownAccount(_:)`` when the named
    ///   account is absent, or a persistence error if the fetch fails.
    private func upsert(_ transaction: Domain.Transaction) throws {
        // Resolved before anything is inserted or mutated, so the common refusal costs the
        // context nothing. `rolledBack` covers the rest: a row already applied earlier in a
        // batch, or an edit applied in place to a record that was there before.
        let account = try resolvedAccount(for: transaction.accountID)
        let rule = try transaction.recurringRuleID.flatMap { try ruleRecord(id: $0) }
        let target = try record(id: transaction.id) ?? {
            let fresh = TransactionRecord(id: transaction.id)
            modelContext.insert(fresh)
            return fresh
        }()
        target.apply(transaction)
        target.account = account
        target.recurringRule = rule
    }

    /// Runs a write, discarding every pending change if any part of it fails.
    ///
    /// A `ModelContext` keeps uncommitted inserts and edits, and a fetch sees them — so a
    /// write that throws half way through does not merely fail, it leaves the rest of the
    /// batch sitting in the context waiting for the *next* caller's `save()` to commit it.
    /// Every public write on this actor ends in one `save()`, so there is never unrelated
    /// pending work here to lose.
    ///
    /// - Parameter work: The write to run.
    /// - Throws: Whatever `work` throws, after the rollback.
    private func rolledBack(_ work: () throws -> Void) throws {
        do {
            try work()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// The account record a transaction names, insisting it exists.
    /// - Parameter accountID: The account's identifier, or `nil` for a parked entry.
    /// - Returns: The record, or `nil` when the transaction names no account.
    /// - Throws: ``Domain/TransactionRepositoryError/unknownAccount(_:)`` when the named
    ///   account is absent, or a persistence error if the fetch fails.
    private func resolvedAccount(for accountID: UUID?) throws -> AccountRecord? {
        guard let accountID else { return nil }
        guard let record = try accountRecord(id: accountID) else {
            throw TransactionRepositoryError.unknownAccount(accountID)
        }
        return record
    }

    /// Fetches the stored record behind a recurring rule identifier.
    /// - Parameter id: The rule's identifier.
    /// - Returns: The record, or `nil` if none matches.
    /// - Throws: A persistence error if the fetch fails.
    private func ruleRecord(id: UUID) throws -> RecurringRuleRecord? {
        var descriptor = FetchDescriptor<RecurringRuleRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Rebuilds one account's denormalised balance cache.
    /// - Parameter accountID: The account to refresh, if any.
    /// - Throws: A persistence error if the fetch fails.
    private func refreshCache(accountID: UUID?) throws {
        guard let accountID, let account = try accountRecord(id: accountID) else { return }
        account.cachedBalanceCents = BalanceEngine.recalculatedCacheCents(
            account: account.toDomain(),
            transactions: (account.transactions ?? [])
                .filter { !$0.isDeleted }
                .map { $0.toDomain() }
        )
    }

    /// Fetches every stored leg of a transfer.
    /// - Parameter groupID: The shared transfer group identifier.
    /// - Returns: The leg records.
    /// - Throws: A persistence error if the fetch fails.
    private func legRecords(groupID: UUID) throws -> [TransactionRecord] {
        let descriptor = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate { $0.transferGroupID == groupID }
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetches the stored record behind a transaction identifier.
    /// - Parameter id: The transaction's identifier.
    /// - Returns: The record, or `nil` if none matches.
    /// - Throws: A persistence error if the fetch fails.
    private func record(id: UUID) throws -> TransactionRecord? {
        var descriptor = FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Fetches the stored record behind an account identifier.
    /// - Parameter id: The account's identifier.
    /// - Returns: The record, or `nil` if none matches.
    /// - Throws: A persistence error if the fetch fails.
    private func accountRecord(id: UUID) throws -> AccountRecord? {
        var descriptor = FetchDescriptor<AccountRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
