import Foundation
import Domain

/// Conversion between ``TransactionRecord`` and ``Domain/Transaction``.
extension TransactionRecord {
    /// Converts this record into its Domain value type.
    /// - Returns: The equivalent ``Domain/Transaction``, with relationships
    ///   flattened to identifiers.
    func toDomain() -> Domain.Transaction {
        Domain.Transaction(
            id: id,
            amountCents: amountCents,
            type: type,
            signedOverrideCents: signedOverrideCents,
            categoryID: categoryID,
            accountID: account?.id,
            date: date,
            merchant: merchant,
            location: location,
            memo: memo,
            tags: tags,
            transferGroupID: transferGroupID,
            recurringRuleID: recurringRule?.id,
            isSeriesOverride: isSeriesOverride,
            receiptFileID: receiptFileID,
            receiptFileName: receiptFileName,
            receiptChecksum: receiptChecksum,
            receiptUploadState: receiptUploadState
        )
    }

    /// Overwrites this record's scalar fields from a Domain value.
    ///
    /// The `account` and `recurringRule` relationships are resolved by the
    /// repository, which owns the `ModelContext` needed to look them up.
    ///
    /// - Parameter transaction: The values to apply.
    func apply(_ transaction: Domain.Transaction) {
        amountCents = transaction.amountCents
        type = transaction.type
        signedOverrideCents = transaction.signedOverrideCents
        categoryID = transaction.categoryID
        date = transaction.date
        merchant = transaction.merchant
        location = transaction.location
        memo = transaction.memo
        tags = transaction.tags
        transferGroupID = transaction.transferGroupID
        isSeriesOverride = transaction.isSeriesOverride
        receiptFileID = transaction.receiptFileID
        receiptFileName = transaction.receiptFileName
        receiptChecksum = transaction.receiptChecksum
        receiptUploadState = transaction.receiptUploadState
        // Derived, never supplied: the Domain value computes it, so the stored copy can
        // never drift away from the merchant, amount and date it describes.
        transactionHash = transaction.transactionHash
    }
}

/// Conversion between ``RecurringRuleRecord`` and ``Domain/RecurringRule``.
extension RecurringRuleRecord {
    /// Converts this record into its Domain value type.
    /// - Returns: The equivalent ``Domain/RecurringRule``.
    func toDomain() -> Domain.RecurringRule {
        Domain.RecurringRule(
            id: id,
            name: name,
            amountCents: amountCents,
            type: type,
            categoryID: categoryID,
            accountID: account?.id,
            frequency: frequency,
            startDate: startDate,
            endDate: endDate,
            occurrenceLimit: occurrenceLimit,
            occurrencesGenerated: occurrencesGenerated,
            isActive: isActive,
            productID: product?.id
        )
    }

    /// Overwrites this record's scalar fields from a Domain value.
    ///
    /// The `account` and `product` relationships are resolved by the repository.
    ///
    /// - Parameter rule: The values to apply.
    func apply(_ rule: Domain.RecurringRule) {
        name = rule.name
        amountCents = rule.amountCents
        type = rule.type
        categoryID = rule.categoryID
        frequency = rule.frequency
        startDate = rule.startDate
        endDate = rule.endDate
        occurrenceLimit = rule.occurrenceLimit
        occurrencesGenerated = rule.occurrencesGenerated
        isActive = rule.isActive
    }
}
