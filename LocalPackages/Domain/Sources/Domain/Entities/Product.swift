import Foundation

/// A thing a purchase contained: a gadget under warranty, a free trial, a subscription (§7.3).
///
/// A product never exists on its own. It is always part of a ``Transaction``, which is
/// what records the money and owns the receipt — one receipt, many products. Something
/// acquired for nothing is still a purchase: a transaction of zero cents.
///
/// Deliberately carries **no price**. With several products on one purchase there is no
/// per-product share to record, and a second copy of the money would be a second source
/// of truth. Ask the transaction.
public struct Product: Identifiable, Hashable, Sendable {
    /// Stable identifier, preserved across backup export and import.
    public let id: UUID
    /// The purchase this product was part of.
    ///
    /// Required: a product with no transaction is not representable. The purchase
    /// supplies the price, the account, the date and the receipt.
    public var transactionID: UUID
    /// Product name.
    public var name: String
    /// The assigned product category.
    public var categoryID: UUID?
    /// Arbitrary user labels, and the main thing the product list filters on.
    public var tags: [String]
    /// Free-text note.
    ///
    /// A product takes notes, never a receipt — the image belongs to the purchase.
    public var notes: String?
    /// Ordering position within its transaction.
    public var sortIndex: Int

    /// Whether the product is on a free trial.
    public var hasTrial: Bool
    /// When the free trial ends.
    public var trialEndsDate: Date?
    /// Lead time for the trial-ending reminder.
    public var trialReminderLeadTime: ReminderLeadTime

    /// Whether the product carries a warranty or expiry date.
    public var hasWarranty: Bool
    /// When the warranty or expiry falls due.
    public var warrantyExpiresDate: Date?
    /// Lead time for the warranty-expiring reminder.
    public var warrantyReminderLeadTime: ReminderLeadTime

    /// The recurring rule that bills for this product, if it is a subscription.
    public var recurringRuleID: UUID?

    /// Creates a product.
    /// - Parameters:
    ///   - id: Stable identifier. Defaults to a fresh UUID.
    ///   - transactionID: The purchase this product was part of.
    ///   - name: Product name.
    ///   - categoryID: The assigned product category.
    ///   - tags: Arbitrary user labels.
    ///   - notes: Free-text note.
    ///   - sortIndex: Ordering position within its transaction.
    ///   - hasTrial: Whether the product is on a free trial.
    ///   - trialEndsDate: When the free trial ends.
    ///   - trialReminderLeadTime: Lead time for the trial reminder.
    ///   - hasWarranty: Whether the product carries a warranty.
    ///   - warrantyExpiresDate: When the warranty expires.
    ///   - warrantyReminderLeadTime: Lead time for the warranty reminder.
    ///   - recurringRuleID: The rule that bills for this product.
    public init(
        id: UUID = UUID(),
        transactionID: UUID,
        name: String = "",
        categoryID: UUID? = nil,
        tags: [String] = [],
        notes: String? = nil,
        sortIndex: Int = 0,
        hasTrial: Bool = false,
        trialEndsDate: Date? = nil,
        trialReminderLeadTime: ReminderLeadTime = .useDefault,
        hasWarranty: Bool = false,
        warrantyExpiresDate: Date? = nil,
        warrantyReminderLeadTime: ReminderLeadTime = .useDefault,
        recurringRuleID: UUID? = nil
    ) {
        self.id = id
        self.transactionID = transactionID
        self.name = name
        self.categoryID = categoryID
        self.tags = tags
        self.notes = notes
        self.sortIndex = sortIndex
        self.hasTrial = hasTrial
        self.trialEndsDate = trialEndsDate
        self.trialReminderLeadTime = trialReminderLeadTime
        self.hasWarranty = hasWarranty
        self.warrantyExpiresDate = warrantyExpiresDate
        self.warrantyReminderLeadTime = warrantyReminderLeadTime
        self.recurringRuleID = recurringRuleID
    }
}
