import Foundation
import Domain

/// Turning the transaction form into the records it implies (§4.3, §4.5, §7.8).
///
/// Split from ``TransactionFormState`` to keep each file within the 300-line limit.
extension TransactionFormState {
    /// Builds the transaction for expense and income modes.
    /// - Returns: The transaction to persist, or `nil` when invalid or in transfer mode.
    public func commitSingle() -> Domain.Transaction? {
        guard isValid, mode != .transfer, let cents = amountCents else { return nil }
        var transaction = preserved ?? Domain.Transaction(id: pendingID)
        transaction.amountCents = cents
        transaction.type = mode == .income ? .income : .expense
        transaction.signedOverrideCents = nil
        transaction.categoryID = categoryID
        transaction.accountID = accountID
        transaction.date = date
        transaction.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.location = emptyToNil(location)
        transaction.memo = emptyToNil(memo)
        transaction.tags = tags
        transaction.receiptFileID = receiptFileID
        transaction.receiptFileName = receiptFileName
        transaction.receiptChecksum = receiptChecksum
        transaction.receiptUploadState = receiptUploadState
        transaction.transferGroupID = nil
        return transaction
    }

    /// Builds a transaction from the current values without validating (§7.8).
    ///
    /// For the Add Product form's read-only purchase header, which has to describe a
    /// transaction that has not been written yet. The identifier is the one the save
    /// will use, so products collected against it end up pointing at the right row.
    ///
    /// - Returns: The transaction as it currently stands.
    public func commitPreview() -> Domain.Transaction {
        var transaction = preserved ?? Domain.Transaction(id: pendingID)
        transaction.amountCents = amountCents ?? 0
        transaction.type = mode == .income ? .income : .expense
        transaction.accountID = accountID
        transaction.date = date
        transaction.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.receiptFileID = receiptFileID
        return transaction
    }

    /// Builds both legs for transfer mode (§4.3).
    /// - Returns: The outflow and inflow legs.
    /// - Throws: ``TransferError`` when the accounts match or the amount is not positive.
    public func commitTransfer() throws -> (out: Domain.Transaction, in: Domain.Transaction)? {
        guard isValid, mode == .transfer,
              let cents = amountCents,
              let source = accountID,
              let destination = destinationAccountID else { return nil }
        return try TransferFactory.makeLegs(
            amountCents: cents,
            date: date,
            sourceAccountID: source,
            destinationAccountID: destination,
            merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines),
            memo: emptyToNil(memo)
        )
    }

    /// Builds the recurring rule this transaction seeds, if the toggle is on (§4.5).
    ///
    /// The rule is persisted here; the engine that lazily generates its occurrences
    /// arrives in Phase 6.
    ///
    /// - Returns: The rule to persist, or `nil` when the toggle is off.
    public func commitRecurringRule() -> Domain.RecurringRule? {
        // A repeating charge of nothing is not a series worth generating.
        guard isRecurring, mode != .transfer, isValid,
              let cents = amountCents, cents > 0 else { return nil }
        return Domain.RecurringRule(
            name: merchant.trimmingCharacters(in: .whitespacesAndNewlines),
            amountCents: cents,
            type: mode == .income ? .income : .expense,
            categoryID: categoryID,
            accountID: accountID,
            frequency: frequency,
            startDate: date,
            endDate: endCondition == .onDate ? endDate : nil,
            occurrenceLimit: occurrenceLimit
        )
    }
}
