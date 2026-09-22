import Foundation
import SwiftData
import Domain

/// SwiftData-backed ``RecurringRuleRepository``.
@ModelActor
public actor SwiftDataRecurringRuleRepository: RecurringRuleRepository {

    /// Fetches rules in start-date order.
    /// - Parameter activeOnly: Whether to return only rules still generating occurrences.
    /// - Returns: The matching rules.
    /// - Throws: A persistence error if the fetch fails.
    public func rules(activeOnly: Bool) async throws -> [Domain.RecurringRule] {
        var descriptor = FetchDescriptor<RecurringRuleRecord>(
            sortBy: [SortDescriptor(\.startDate)]
        )
        if activeOnly {
            descriptor.predicate = #Predicate { $0.isActive == true }
        }
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    /// Fetches a single rule.
    /// - Parameter id: The rule's identifier.
    /// - Returns: The rule, or `nil` if none matches.
    /// - Throws: A persistence error if the fetch fails.
    public func rule(id: UUID) async throws -> Domain.RecurringRule? {
        try record(id: id)?.toDomain()
    }

    /// Inserts or updates a rule, resolving its account.
    /// - Parameter rule: The rule to persist.
    /// - Throws: A persistence error if the write fails.
    public func save(_ rule: Domain.RecurringRule) async throws {
        let target = try record(id: rule.id) ?? {
            let fresh = RecurringRuleRecord(id: rule.id)
            modelContext.insert(fresh)
            return fresh
        }()
        target.apply(rule)
        target.account = try rule.accountID.flatMap { try accountRecord(id: $0) }
        try modelContext.save()
    }

    /// Deletes a rule, leaving any transactions it already generated in place.
    /// - Parameter id: The rule's identifier.
    /// - Throws: A persistence error if the delete fails.
    public func delete(id: UUID) async throws {
        guard let target = try record(id: id) else { return }
        modelContext.delete(target)
        try modelContext.save()
    }

    /// Fetches the stored record behind a rule identifier.
    /// - Parameter id: The rule's identifier.
    /// - Returns: The record, or `nil` if none matches.
    /// - Throws: A persistence error if the fetch fails.
    private func record(id: UUID) throws -> RecurringRuleRecord? {
        var descriptor = FetchDescriptor<RecurringRuleRecord>(predicate: #Predicate { $0.id == id })
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
