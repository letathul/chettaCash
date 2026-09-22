import Foundation
import SwiftData
import Domain

/// SwiftData-backed ``AccountRepository``.
///
/// `@ModelActor` gives this a private `ModelContext` isolated to its own actor, which
/// is what lets it satisfy the protocol's `Sendable` requirement under strict
/// concurrency without pinning everything to the main actor.
@ModelActor
public actor SwiftDataAccountRepository: AccountRepository {

    /// Fetches accounts in sort order.
    /// - Parameter includeClosed: Whether closed accounts are returned.
    /// - Returns: The matching accounts.
    /// - Throws: A persistence error if the fetch fails.
    public func accounts(includeClosed: Bool) async throws -> [Domain.Account] {
        var descriptor = FetchDescriptor<AccountRecord>(
            sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.name)]
        )
        if !includeClosed {
            descriptor.predicate = #Predicate { $0.isClosed == false }
        }
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    /// Fetches a single account.
    /// - Parameter id: The account's identifier.
    /// - Returns: The account, or `nil` if none matches.
    /// - Throws: A persistence error if the fetch fails.
    public func account(id: UUID) async throws -> Domain.Account? {
        try record(id: id)?.toDomain()
    }

    /// Inserts or updates an account, resolving its group and refreshing its cache.
    /// - Parameter account: The account to persist.
    /// - Throws: A persistence error if the write fails.
    public func save(_ account: Domain.Account) async throws {
        let target = try record(id: account.id) ?? {
            let fresh = AccountRecord(id: account.id)
            modelContext.insert(fresh)
            return fresh
        }()
        target.apply(account)
        target.group = try account.groupID.flatMap { try groupRecord(id: $0) }
        target.cachedBalanceCents = BalanceEngine.recalculatedCacheCents(
            account: target.toDomain(),
            transactions: (target.transactions ?? []).filter { !$0.isDeleted }.map { $0.toDomain() }
        )
        try modelContext.save()
    }

    /// Fetches all account groups in sort order.
    /// - Returns: The groups.
    /// - Throws: A persistence error if the fetch fails.
    public func groups() async throws -> [Domain.AccountGroup] {
        let descriptor = FetchDescriptor<AccountGroupRecord>(
            sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    /// Inserts or updates an account group.
    /// - Parameter group: The group to persist.
    /// - Throws: A persistence error if the write fails.
    public func save(_ group: Domain.AccountGroup) async throws {
        let target = try groupRecord(id: group.id) ?? {
            let fresh = AccountGroupRecord(id: group.id)
            modelContext.insert(fresh)
            return fresh
        }()
        target.apply(group)
        try modelContext.save()
    }

    /// Rebuilds every account's balance cache from its full transaction history (§4.1).
    /// - Throws: A persistence error if the rebuild fails.
    public func recalculateAllBalances() async throws {
        let records = try modelContext.fetch(FetchDescriptor<AccountRecord>())
        for record in records {
            record.cachedBalanceCents = BalanceEngine.recalculatedCacheCents(
                account: record.toDomain(),
                transactions: (record.transactions ?? []).filter { !$0.isDeleted }.map { $0.toDomain() }
            )
        }
        try modelContext.save()
    }

    /// Fetches the stored record behind an account identifier.
    /// - Parameter id: The account's identifier.
    /// - Returns: The record, or `nil` if none matches.
    /// - Throws: A persistence error if the fetch fails.
    private func record(id: UUID) throws -> AccountRecord? {
        var descriptor = FetchDescriptor<AccountRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Fetches the stored record behind a group identifier.
    /// - Parameter id: The group's identifier.
    /// - Returns: The record, or `nil` if none matches.
    /// - Throws: A persistence error if the fetch fails.
    private func groupRecord(id: UUID) throws -> AccountGroupRecord? {
        var descriptor = FetchDescriptor<AccountGroupRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
