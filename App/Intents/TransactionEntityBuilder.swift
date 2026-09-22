import Foundation
import UIKit
import Domain

/// Turns stored entries into ``TransactionEntity`` values.
///
/// Its own type because naming an entry's account and category needs two more fetches, and
/// doing them once for a batch rather than once per row is the difference between a Shortcut
/// that returns and one that times out.
@MainActor
struct TransactionEntityBuilder {
    /// The app's dependency graph.
    let dependencies: AppDependencies

    /// Builds entities for stored entries.
    /// - Parameter transactions: The entries to describe.
    /// - Returns: The entities, in the order given.
    /// - Throws: A persistence error if a fetch fails.
    func entities(for transactions: [Domain.Transaction]) async throws -> [TransactionEntity] {
        let accounts = try await dependencies.accounts.accounts(includeClosed: true)
        let accountNames = Dictionary(
            uniqueKeysWithValues: accounts.map { ($0.id, $0.name) }
        )
        let categories = try await dependencies.categories.allCategories()
        let categoryLabels = Dictionary(
            uniqueKeysWithValues: categories.map { ($0.id, $0.label) }
        )
        let code = dependencies.settings.currencyCode

        return transactions.map { transaction in
            TransactionEntity(
                transaction: transaction,
                accountName: transaction.accountID.flatMap { accountNames[$0] } ?? "",
                categoryLabel: transaction.categoryID.flatMap { categoryLabels[$0] } ?? "",
                currencyCode: code
            )
        }
    }
}
