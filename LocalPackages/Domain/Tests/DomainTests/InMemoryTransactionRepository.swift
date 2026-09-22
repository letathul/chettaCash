import Foundation
@testable import Domain

/// An in-memory ``TransactionRepository`` used to verify the transfer invariant
/// from §4.3 without involving SwiftData.
actor InMemoryTransactionRepository: TransactionRepository {
    /// Stored transactions, keyed by identifier.
    private var storage: [UUID: Transaction] = [:]

    /// Fetches transactions, newest first.
    /// - Parameters:
    ///   - accountID: Restricts results to one account, or `nil` for all.
    ///   - range: Restricts results to a date range, or `nil` for all history.
    /// - Returns: The matching transactions.
    func transactions(accountID: UUID?, in range: ClosedRange<Date>?) async throws -> [Transaction] {
        storage.values
            .filter { accountID == nil || $0.accountID == accountID }
            .filter { range?.contains($0.date) ?? true }
            .sorted { $0.date > $1.date }
    }

    /// Fetches both legs of a transfer.
    /// - Parameter groupID: The shared transfer group identifier.
    /// - Returns: The transfer's legs.
    func transferLegs(groupID: UUID) async throws -> [Transaction] {
        storage.values.filter { $0.transferGroupID == groupID }
    }

    /// Inserts or updates a transaction.
    /// - Parameter transaction: The transaction to store.
    func save(_ transaction: Transaction) async throws {
        storage[transaction.id] = transaction
    }

    /// Stores both legs of a transfer.
    /// - Parameters:
    ///   - outLeg: The outflow leg.
    ///   - inLeg: The inflow leg.
    func saveTransfer(outLeg: Transaction, inLeg: Transaction) async throws {
        storage[outLeg.id] = outLeg
        storage[inLeg.id] = inLeg
    }

    /// Deletes a transaction, or both legs when it belongs to a transfer.
    /// - Parameter id: The transaction's identifier.
    func delete(id: UUID) async throws {
        guard let transaction = storage[id] else { return }
        if let groupID = transaction.transferGroupID {
            try await deleteTransfer(groupID: groupID)
        } else {
            storage[id] = nil
        }
    }

    /// Deletes both legs of a transfer.
    /// - Parameter groupID: The shared transfer group identifier.
    func deleteTransfer(groupID: UUID) async throws {
        for (id, transaction) in storage where transaction.transferGroupID == groupID {
            storage[id] = nil
        }
    }
}
