import Foundation
import Domain

/// The lookups the product cards and forms need (§7.3, §7.8).
///
/// The filtered and ordered lists themselves are stored on ``ProductsViewModel`` and
/// rebuilt by ``ProductsViewModel/refresh()``; what remains here are the
/// by-identifier lookups, all served from dictionaries built in the same pass.
///
/// Split from ``ProductsViewModel`` to keep each file within the 300-line limit.
extension ProductsViewModel {

    /// Whether no product exists at all, which is the first-run empty state.
    public var isEmpty: Bool { products.isEmpty }

    /// Looks up an account by identifier.
    /// - Parameter id: The account's identifier, if any.
    /// - Returns: The account, or `nil` when unset or unknown.
    public func account(id: UUID?) -> Domain.Account? {
        guard let id else { return nil }
        return accountsByID[id]
    }

    /// Looks up a category by identifier.
    /// - Parameter id: The category's identifier, if any.
    /// - Returns: The category, or `nil` when unset or unknown.
    public func category(id: UUID?) -> Domain.Category? {
        guard let id else { return nil }
        return categoriesByID[id]
    }

    /// Looks up a purchase by identifier.
    /// - Parameter id: The transaction's identifier.
    /// - Returns: The transaction, or `nil` when unknown.
    public func purchase(id: UUID) -> Domain.Transaction? {
        transactionsByID[id]
    }

    /// The products attached to one purchase, in display order (§7.8).
    /// - Parameter transactionID: The purchase's identifier.
    /// - Returns: Its products.
    public func products(for transactionID: UUID) -> [Domain.Product] {
        productsByTransactionID[transactionID] ?? []
    }

    /// The rule billing for a product, if it has one.
    /// - Parameter product: The product to inspect.
    /// - Returns: The rule, or `nil` when the product does not bill.
    public func rule(for product: Domain.Product) -> Domain.RecurringRule? {
        rulesByProductID[product.id]
    }
}
