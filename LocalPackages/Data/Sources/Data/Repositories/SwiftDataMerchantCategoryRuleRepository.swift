import Foundation
import SwiftData
import Domain

/// SwiftData-backed ``MerchantCategoryRuleRepository``.
@ModelActor
public actor SwiftDataMerchantCategoryRuleRepository: MerchantCategoryRuleRepository {

    /// Fetches every pin, most recently updated first.
    /// - Returns: The pins.
    /// - Throws: A persistence error if the fetch fails.
    public func rules() async throws -> [Domain.MerchantCategoryRule] {
        let descriptor = FetchDescriptor<MerchantCategoryRuleRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).compactMap { $0.toDomain() }
    }

    /// Fetches the pin for one normalised merchant key.
    /// - Parameter merchantKey: The key, from ``Domain/MerchantCategoryIndex/key(for:)``.
    /// - Returns: The pin, or `nil` when the merchant has none.
    /// - Throws: A persistence error if the fetch fails.
    public func rule(merchantKey: String) async throws -> Domain.MerchantCategoryRule? {
        try record(merchantKey: merchantKey)?.toDomain()
    }

    /// Inserts or updates a pin, replacing any pin sharing its `merchantKey`.
    ///
    /// Matching on the key rather than the identifier is what makes a pin an upsert:
    /// pinning `Whole Foods Mkt` after pinning `WHOLE FOODS MKT #10234` must replace
    /// that pin, not add a second one that never wins.
    ///
    /// - Parameter rule: The pin to persist.
    /// - Throws: A persistence error if the write fails.
    public func save(_ rule: Domain.MerchantCategoryRule) async throws {
        let existing = try record(merchantKey: rule.merchantKey) ?? record(id: rule.id)
        let target = existing ?? {
            let fresh = MerchantCategoryRuleRecord(id: rule.id)
            modelContext.insert(fresh)
            return fresh
        }()
        target.apply(rule)
        try modelContext.save()
    }

    /// Deletes a pin, leaving every transaction it ever categorised alone.
    /// - Parameter id: The pin's identifier.
    /// - Throws: A persistence error if the delete fails.
    public func delete(id: UUID) async throws {
        guard let target = try record(id: id) else { return }
        modelContext.delete(target)
        try modelContext.save()
    }

    /// Fetches the stored record behind a pin identifier.
    /// - Parameter id: The pin's identifier.
    /// - Returns: The record, or `nil` if none matches.
    /// - Throws: A persistence error if the fetch fails.
    private func record(id: UUID) throws -> MerchantCategoryRuleRecord? {
        var descriptor = FetchDescriptor<MerchantCategoryRuleRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Fetches the stored record for a merchant key.
    /// - Parameter merchantKey: The normalised key.
    /// - Returns: The record, or `nil` if none matches.
    /// - Throws: A persistence error if the fetch fails.
    private func record(merchantKey: String) throws -> MerchantCategoryRuleRecord? {
        guard !merchantKey.isEmpty else { return nil }
        var descriptor = FetchDescriptor<MerchantCategoryRuleRecord>(
            predicate: #Predicate { $0.merchantKey == merchantKey }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
