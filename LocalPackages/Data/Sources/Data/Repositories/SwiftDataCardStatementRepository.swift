import Foundation
import SwiftData
import Domain

/// SwiftData-backed ``CardStatementRepository``.
@ModelActor
public actor SwiftDataCardStatementRepository: CardStatementRepository {

    /// Fetches a card's statements, oldest first.
    /// - Parameter accountID: The card to list, or `nil` for every card.
    /// - Returns: The matching statements.
    /// - Throws: A persistence error if the fetch fails.
    public func statements(accountID: UUID?) async throws -> [Domain.CardStatement] {
        let descriptor = FetchDescriptor<CardStatementRecord>(
            sortBy: [SortDescriptor(\.closingDate)]
        )
        return try modelContext.fetch(descriptor)
            .filter { accountID == nil || $0.account?.id == accountID }
            .map { $0.toDomain() }
    }

    /// Fetches payment allocations.
    /// - Parameter accountID: The card to list, or `nil` for every card.
    /// - Returns: The matching allocations.
    /// - Throws: A persistence error if the fetch fails.
    public func payments(accountID: UUID?) async throws -> [Domain.StatementPayment] {
        try modelContext.fetch(FetchDescriptor<StatementPaymentRecord>())
            .filter { accountID == nil || $0.statement?.account?.id == accountID }
            .map { $0.toDomain() }
    }

    /// Inserts or updates a statement, resolving its card.
    /// - Parameter statement: The statement to persist.
    /// - Throws: A persistence error if the write fails.
    public func save(_ statement: Domain.CardStatement) async throws {
        let target = try record(id: statement.id) ?? {
            let fresh = CardStatementRecord(id: statement.id)
            modelContext.insert(fresh)
            return fresh
        }()
        target.apply(statement)
        target.account = try statement.accountID.flatMap { try accountRecord(id: $0) }
        try modelContext.save()
    }

    /// Inserts a payment allocation, resolving its statement and transaction.
    /// - Parameter payment: The allocation to persist.
    /// - Throws: A persistence error if the write fails.
    public func save(_ payment: Domain.StatementPayment) async throws {
        let target = try paymentRecord(id: payment.id) ?? {
            let fresh = StatementPaymentRecord(id: payment.id)
            modelContext.insert(fresh)
            return fresh
        }()
        target.amountCents = payment.amountCents
        target.statement = try payment.statementID.flatMap { try record(id: $0) }
        target.transaction = try payment.transactionID.flatMap { try transactionRecord(id: $0) }
        try modelContext.save()
    }

    /// Fetches the stored record behind a statement identifier.
    /// - Parameter id: The statement's identifier.
    /// - Returns: The record, or `nil` if none matches.
    /// - Throws: A persistence error if the fetch fails.
    private func record(id: UUID) throws -> CardStatementRecord? {
        var descriptor = FetchDescriptor<CardStatementRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Fetches the stored record behind a payment identifier.
    /// - Parameter id: The payment's identifier.
    /// - Returns: The record, or `nil` if none matches.
    /// - Throws: A persistence error if the fetch fails.
    private func paymentRecord(id: UUID) throws -> StatementPaymentRecord? {
        var descriptor = FetchDescriptor<StatementPaymentRecord>(
            predicate: #Predicate { $0.id == id }
        )
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

    /// Fetches the stored record behind a transaction identifier.
    /// - Parameter id: The transaction's identifier.
    /// - Returns: The record, or `nil` if none matches.
    /// - Throws: A persistence error if the fetch fails.
    private func transactionRecord(id: UUID) throws -> TransactionRecord? {
        var descriptor = FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
