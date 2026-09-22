import Foundation
import Observation
import Domain

/// The editable state behind Add and Edit Product (§7.7).
///
/// Add and Edit share this so they validate identically (§7.11).
///
/// The form holds only what belongs to the **product**: name, category, tags, notes and
/// the dates that drive reminders. Price, account and purchase date are read off the
/// ``purchase`` and shown as a read-only header — a product has no money of its own, and
/// a second editable copy of the purchase's figures would be a second source of truth.
@MainActor
@Observable
public final class ProductFormState {
    /// The product being edited, or `nil` when adding.
    public let existingID: UUID?
    /// The purchase this product belongs to. Never editable from here.
    public let purchase: Domain.Transaction
    /// Whether this form is editing rather than adding.
    public var isEditing: Bool { existingID != nil }

    /// The product's name.
    public var name = ""
    /// The assigned product category.
    public var categoryID: UUID?
    /// Free-text note. A product takes notes; the receipt belongs to the purchase.
    public var notes = ""
    /// Arbitrary user labels.
    public var tags: [String] = []
    /// Ordering position within its purchase.
    public var sortIndex = 0

    /// Whether the product is on a free trial.
    public var hasTrial = false
    /// When the free trial ends.
    public var trialEndsDate: Date = .now.addingTimeInterval(14 * 86_400)
    /// Lead time for the trial reminder.
    public var trialReminderLeadTime: ReminderLeadTime = .useDefault

    /// Whether the product carries a warranty or expiry date.
    public var hasWarranty = false
    /// When the warranty expires.
    public var warrantyExpiresDate: Date = .now.addingTimeInterval(365 * 86_400)
    /// Lead time for the warranty reminder.
    public var warrantyReminderLeadTime: ReminderLeadTime = .useDefault

    /// Whether the product bills on a schedule.
    public var isRecurring = false
    /// How often it bills.
    public var frequency: RecurringFrequency = .monthly

    /// Whether Save has been attempted, which is what reveals validation (§7.11).
    public private(set) var hasAttemptedSave = false

    /// Fields preserved from the product being edited but not shown in the form.
    private let preserved: Domain.Product?

    /// Creates empty state for adding a product to a purchase.
    ///
    /// The name is seeded from the merchant, which is right far more often than a blank
    /// field for the common case of one purchase, one thing.
    ///
    /// - Parameters:
    ///   - purchase: The transaction the product was part of.
    ///   - sortIndex: Where it sits among that purchase's products.
    public init(purchase: Domain.Transaction, sortIndex: Int = 0) {
        self.existingID = nil
        self.purchase = purchase
        self.preserved = nil
        self.name = purchase.merchant
        self.sortIndex = sortIndex
        self.trialEndsDate = purchase.date.addingTimeInterval(14 * 86_400)
        self.warrantyExpiresDate = purchase.date.addingTimeInterval(365 * 86_400)
    }

    /// Creates state pre-filled from an existing product.
    /// - Parameters:
    ///   - product: The product being edited.
    ///   - purchase: The transaction it belongs to.
    public init(editing product: Domain.Product, purchase: Domain.Transaction) {
        self.existingID = product.id
        self.purchase = purchase
        self.preserved = product
        self.name = product.name
        self.categoryID = product.categoryID
        self.notes = product.notes ?? ""
        self.tags = product.tags
        self.sortIndex = product.sortIndex
        self.hasTrial = product.hasTrial
        self.trialEndsDate = product.trialEndsDate
            ?? purchase.date.addingTimeInterval(14 * 86_400)
        self.trialReminderLeadTime = product.trialReminderLeadTime
        self.hasWarranty = product.hasWarranty
        self.warrantyExpiresDate = product.warrantyExpiresDate
            ?? purchase.date.addingTimeInterval(365 * 86_400)
        self.warrantyReminderLeadTime = product.warrantyReminderLeadTime
        self.isRecurring = product.recurringRuleID != nil
    }

    // MARK: - Validation (§7.11)

    /// The trimmed product name.
    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The name field's error, or `nil` when valid.
    public var nameError: String? {
        guard hasAttemptedSave, trimmedName.isEmpty else { return nil }
        return "Product name is required."
    }

    /// Whether every required field is filled.
    ///
    /// A name, and nothing else. Price used to be required here; it now lives on the
    /// purchase, which has already been validated by the time this form opens.
    public var isValid: Bool { !trimmedName.isEmpty }

    /// Records a Save attempt and builds the product when the form is valid.
    /// - Returns: The product to persist, or `nil` when the form is invalid.
    public func commit() -> Domain.Product? {
        hasAttemptedSave = true
        guard isValid else { return nil }

        var product = preserved ?? Domain.Product(transactionID: purchase.id)
        product.transactionID = purchase.id
        product.name = trimmedName
        product.categoryID = categoryID
        product.notes = trimmed(notes)
        product.tags = tags
        product.sortIndex = sortIndex
        product.hasTrial = hasTrial
        product.trialEndsDate = hasTrial ? trialEndsDate : nil
        product.trialReminderLeadTime = trialReminderLeadTime
        product.hasWarranty = hasWarranty
        product.warrantyExpiresDate = hasWarranty ? warrantyExpiresDate : nil
        product.warrantyReminderLeadTime = warrantyReminderLeadTime
        return product
    }

    /// Trims a free-text field, treating whitespace-only as absent.
    /// - Parameter text: The typed text.
    /// - Returns: The trimmed text, or `nil` when nothing is left.
    private func trimmed(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
