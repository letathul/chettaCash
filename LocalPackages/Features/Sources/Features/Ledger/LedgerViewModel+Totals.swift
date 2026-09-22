import Foundation
import Domain

/// The lookups the Ledger's rows and pickers need (§7.4).
///
/// The totals themselves are stored on ``LedgerViewModel`` and rebuilt by
/// ``LedgerViewModel/refresh()``; what remains here are the by-identifier lookups, all
/// served from dictionaries built in the same pass.
///
/// Split from ``LedgerViewModel`` to keep each file within the 300-line limit.
extension LedgerViewModel {

    /// Categories offered for one context, excluding archived and system ones (§4.8).
    /// - Parameter context: Which picker the categories are for.
    /// - Returns: The selectable categories.
    public func selectableCategories(for context: CategoryContext) -> [Domain.Category] {
        categoriesByContext[context] ?? []
    }

    /// Looks up a category by identifier.
    /// - Parameter id: The category's identifier, if any.
    /// - Returns: The category, or `nil` when unset or unknown.
    public func category(id: UUID?) -> Domain.Category? {
        guard let id else { return nil }
        return categoriesByID[id]
    }

    /// Looks up an account by identifier.
    /// - Parameter id: The account's identifier, if any.
    /// - Returns: The account, or `nil` when unset or unknown.
    public func account(id: UUID?) -> Domain.Account? {
        guard let id else { return nil }
        return accountsByID[id]
    }

    /// Finds the other leg of a transfer, so the Edit sheet can show its destination.
    /// - Parameter transaction: One leg of the transfer.
    /// - Returns: The counterpart account's identifier, if the partner leg exists.
    public func counterpartAccountID(for transaction: Domain.Transaction) -> UUID? {
        guard let groupID = transaction.transferGroupID else { return nil }
        return allTransactions
            .first { $0.transferGroupID == groupID && $0.id != transaction.id }?
            .accountID
    }

    /// Whether a row's transaction may be edited.
    ///
    /// A transaction on a closed account still opens and still reads — history stays
    /// browsable — but the detail screen offers no Edit button for it (§4.7, §7.4).
    ///
    /// Only a *known* closed account withholds the button. An account that cannot be
    /// resolved — the model has not finished loading, or the row names an account this
    /// screen never fetched — is not evidence of closure, and reading it as such hid
    /// Edit on a perfectly editable transaction.
    ///
    /// - Parameter item: The row to test.
    /// - Returns: `true` unless an account the row touches is known to be closed.
    public func isEditable(_ item: LedgerItem) -> Bool {
        switch item {
        case .single(let transaction):
            return isOpen(accountID: transaction.accountID)
        case .transfer(let outLeg, let inLeg):
            return isOpen(accountID: outLeg.accountID) && isOpen(accountID: inLeg.accountID)
        }
    }

    /// Whether an account is anything other than known-closed.
    /// - Parameter accountID: The account to test.
    /// - Returns: `false` only when the account is loaded and closed.
    private func isOpen(accountID: UUID?) -> Bool {
        account(id: accountID)?.isClosed != true
    }
}
