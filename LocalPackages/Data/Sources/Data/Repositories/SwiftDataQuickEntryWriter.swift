import Foundation
import SwiftData
import Domain

/// SwiftData-backed ``QuickEntryWriting``: one context, one commit (§15).
///
/// Every other repository here owns its own `ModelContext`, which is what lets each be an
/// independent actor — and what makes a four-repository write four commits. A Shortcut
/// cannot live with that. It can imply a created card, an invented category, the entry and a
/// merchant pin, and it runs in a process that ends the moment it returns, so a failure part
/// way through would leave an orphan card and an orphan category behind with nothing on
/// screen to explain them and nobody watching.
///
/// So this actor does the whole write against one context and saves once. It restates a
/// little of what the individual repositories do, deliberately: the alternative is sharing a
/// context between actors, which is the thing `@ModelActor` exists to prevent.
@ModelActor
public actor SwiftDataQuickEntryWriter: QuickEntryWriting {

    /// Writes everything one quick entry implies, in one commit.
    ///
    /// Order within the context still matters — the account record has to exist before the
    /// transaction's relationship is assigned — but it no longer matters *across* failures:
    /// nothing is durable until the single `save()` at the end, and a throw before it rolls
    /// the context back to where it started.
    ///
    /// - Parameter bundle: What to write.
    /// - Throws: ``Domain/TransactionRepositoryError/unknownAccount(_:)`` when the entry
    ///   names an account that neither exists nor is being created, or a persistence error
    ///   if the write fails.
    public func write(_ bundle: QuickEntryWrite) async throws {
        do {
            if let account = bundle.newAccount { try upsert(account) }
            if let category = bundle.newCategory { try upsert(category) }
            let account = try resolvedAccount(for: bundle.transaction.accountID)
            try upsert(bundle.transaction, on: account)
            if let pin = bundle.newPin { try upsert(pin) }
            refreshCache(account)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Inserts or updates an account, resolving its group.
    /// - Parameter account: The account to persist.
    /// - Throws: A persistence error if the fetch fails.
    private func upsert(_ account: Domain.Account) throws {
        let id = account.id
        let target = try first(FetchDescriptor<AccountRecord>(
            predicate: #Predicate { $0.id == id }
        )) ?? insert(AccountRecord(id: id))
        target.apply(account)
        if let groupID = account.groupID {
            target.group = try first(FetchDescriptor<AccountGroupRecord>(
                predicate: #Predicate { $0.id == groupID }
            ))
        } else {
            target.group = nil
        }
    }

    /// Inserts or updates a category.
    /// - Parameter category: The category to persist.
    /// - Throws: A persistence error if the fetch fails.
    private func upsert(_ category: Domain.Category) throws {
        let id = category.id
        let target = try first(FetchDescriptor<CategoryRecord>(
            predicate: #Predicate { $0.id == id }
        )) ?? insert(CategoryRecord(id: id))
        target.apply(category)
    }

    /// Inserts or updates the entry and points it at its account.
    /// - Parameters:
    ///   - transaction: The entry to persist.
    ///   - account: The account record it belongs to, or `nil` for a parked entry (§15.5).
    /// - Throws: A persistence error if the fetch fails.
    private func upsert(_ transaction: Domain.Transaction, on account: AccountRecord?) throws {
        let id = transaction.id
        let target = try first(FetchDescriptor<TransactionRecord>(
            predicate: #Predicate { $0.id == id }
        )) ?? insert(TransactionRecord(id: id))
        target.apply(transaction)
        target.account = account
    }

    /// Inserts or updates a pin, replacing any pin sharing its merchant key.
    ///
    /// Keyed on `merchantKey` rather than `id`, exactly as
    /// ``SwiftDataMerchantCategoryRuleRepository/save(_:)`` is: pinning `Whole Foods Mkt`
    /// after pinning `WHOLE FOODS MKT #10234` must replace that pin, not add a second one
    /// that never wins.
    ///
    /// - Parameter rule: The pin to persist.
    /// - Throws: A persistence error if the fetch fails.
    private func upsert(_ rule: Domain.MerchantCategoryRule) throws {
        let key = rule.merchantKey
        let id = rule.id
        let existing = try first(FetchDescriptor<MerchantCategoryRuleRecord>(
            predicate: #Predicate { $0.merchantKey == key }
        )) ?? first(FetchDescriptor<MerchantCategoryRuleRecord>(
            predicate: #Predicate { $0.id == id }
        ))
        let target = existing ?? insert(MerchantCategoryRuleRecord(id: id))
        target.apply(rule)
    }

    /// The account record an entry names, insisting it exists.
    ///
    /// The same refusal ``SwiftDataTransactionRepository`` makes, for the same reason: an
    /// entry filed against nothing still shows in the Ledger and still counts toward spend
    /// totals while no balance moves. A `nil` identifier is the other case and stays legal —
    /// that is a §15.5 parked entry, unassigned on purpose.
    ///
    /// - Parameter accountID: The entry's account, or `nil` for a parked entry.
    /// - Returns: The record, or `nil` when the entry names no account.
    /// - Throws: ``Domain/TransactionRepositoryError/unknownAccount(_:)`` when absent.
    private func resolvedAccount(for accountID: UUID?) throws -> AccountRecord? {
        guard let accountID else { return nil }
        guard let record = try first(FetchDescriptor<AccountRecord>(
            predicate: #Predicate { $0.id == accountID }
        )) else {
            throw TransactionRepositoryError.unknownAccount(accountID)
        }
        return record
    }

    /// Rebuilds an account's balance cache from its own history.
    /// - Parameter account: The account to rebuild, if the entry had one.
    private func refreshCache(_ account: AccountRecord?) {
        guard let account else { return }
        account.cachedBalanceCents = BalanceEngine.recalculatedCacheCents(
            account: account.toDomain(),
            transactions: (account.transactions ?? [])
                .filter { !$0.isDeleted }
                .map { $0.toDomain() }
        )
    }

    /// The first record matching a descriptor.
    /// - Parameter descriptor: The descriptor to fetch.
    /// - Returns: The record, or `nil` when none matches.
    /// - Throws: A persistence error if the fetch fails.
    private func first<Record: PersistentModel>(
        _ descriptor: FetchDescriptor<Record>
    ) throws -> Record? {
        var limited = descriptor
        limited.fetchLimit = 1
        return try modelContext.fetch(limited).first
    }

    /// Inserts a fresh record and hands it back.
    /// - Parameter record: The record to insert.
    /// - Returns: The same record, now in the context.
    private func insert<Record: PersistentModel>(_ record: Record) -> Record {
        modelContext.insert(record)
        return record
    }
}
