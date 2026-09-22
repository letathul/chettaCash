import Foundation
import SwiftData
import Domain

/// SwiftData-backed ``ProductRepository``.
///
/// Every write resolves the product's purchase and refuses the row if that purchase
/// does not exist: an orphan product is not representable in the Domain model (§7.8).
@ModelActor
public actor SwiftDataProductRepository: ProductRepository {

    /// Fetches every product, newest purchase first.
    /// - Returns: Every product.
    /// - Throws: A persistence error if the fetch fails.
    public func products() async throws -> [Domain.Product] {
        let descriptor = FetchDescriptor<ProductRecord>()
        let records = try modelContext.fetch(descriptor)
        let dated: [(date: Date, record: ProductRecord)] = records.compactMap { record in
            guard let date = record.transaction?.date else { return nil }
            return (date, record)
        }
        let ordered = dated.sorted { left, right in
            if left.date == right.date { return left.record.sortIndex < right.record.sortIndex }
            return left.date > right.date
        }
        return ordered.compactMap { $0.record.toDomain() }
    }

    /// Fetches the products belonging to one purchase, in their display order.
    /// - Parameter transactionID: The purchase's identifier.
    /// - Returns: That purchase's products, ordered by `sortIndex`.
    /// - Throws: A persistence error if the fetch fails.
    public func products(transactionID: UUID) async throws -> [Domain.Product] {
        let descriptor = FetchDescriptor<ProductRecord>(
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        return try modelContext.fetch(descriptor)
            .filter { $0.transaction?.id == transactionID }
            .compactMap { $0.toDomain() }
    }

    /// Fetches a single product.
    /// - Parameter id: The product's identifier.
    /// - Returns: The product, or `nil` if none matches.
    /// - Throws: A persistence error if the fetch fails.
    public func product(id: UUID) async throws -> Domain.Product? {
        try record(id: id)?.toDomain()
    }

    /// Inserts or updates a product, resolving its relationships.
    /// - Parameter product: The product to persist.
    /// - Throws: ``Domain/ProductRepositoryError/unknownTransaction(_:)`` when the
    ///   purchase does not exist, or a persistence error if the write fails.
    public func save(_ product: Domain.Product) async throws {
        guard let purchase = try transactionRecord(id: product.transactionID) else {
            throw ProductRepositoryError.unknownTransaction(product.transactionID)
        }
        let target = try record(id: product.id) ?? {
            let fresh = ProductRecord(id: product.id)
            modelContext.insert(fresh)
            return fresh
        }()
        target.apply(product)
        target.transaction = purchase
        target.recurringRule = try product.recurringRuleID.flatMap { try ruleRecord(id: $0) }
        try modelContext.save()
    }

    /// Deletes a product, leaving its purchase in place.
    /// - Parameter id: The product's identifier.
    /// - Throws: A persistence error if the delete fails.
    public func delete(id: UUID) async throws {
        guard let target = try record(id: id) else { return }
        modelContext.delete(target)
        try modelContext.save()
    }

    /// Fetches the stored record behind a product identifier.
    /// - Parameter id: The product's identifier.
    /// - Returns: The record, or `nil` if none matches.
    /// - Throws: A persistence error if the fetch fails.
    private func record(id: UUID) throws -> ProductRecord? {
        var descriptor = FetchDescriptor<ProductRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Fetches the stored record behind a transaction identifier.
    /// - Parameter id: The transaction's identifier.
    /// - Returns: The record, or `nil` if none matches.
    /// - Throws: A persistence error if the fetch fails.
    private func transactionRecord(id: UUID) throws -> TransactionRecord? {
        var descriptor = FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
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
}
