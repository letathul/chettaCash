import Foundation
import SwiftData
import Domain

/// Persistent form of ``Domain/Category``.
///
/// Categories are archived, never deleted, so historical rows keep their label (§4.8).
@Model
public final class CategoryRecord {
    /// Stable identifier.
    public var id: UUID = UUID()
    /// Display text.
    public var label: String = ""
    /// Which picker this category appears in.
    public var context: CategoryContext = CategoryContext.expense
    /// Whether the app seeded this category.
    public var isBuiltIn: Bool = false
    /// Whether the category is hidden from pickers.
    public var isArchived: Bool = false
    /// Manual ordering position within its context.
    public var sortIndex: Int = 0

    /// Creates a category record.
    /// - Parameters:
    ///   - id: Stable identifier.
    ///   - label: Display text.
    ///   - context: Which picker this category appears in.
    ///   - isBuiltIn: Whether the app seeded this category.
    ///   - isArchived: Whether the category is hidden from pickers.
    ///   - sortIndex: Manual ordering position.
    public init(
        id: UUID = UUID(),
        label: String = "",
        context: CategoryContext = CategoryContext.expense,
        isBuiltIn: Bool = false,
        isArchived: Bool = false,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.label = label
        self.context = context
        self.isBuiltIn = isBuiltIn
        self.isArchived = isArchived
        self.sortIndex = sortIndex
    }
}

/// Persistent form of ``Domain/CardStatement``.
@Model
public final class CardStatementRecord {
    /// Stable identifier.
    public var id: UUID = UUID()
    /// The card this statement belongs to.
    public var account: AccountRecord?
    /// First day of the billing period.
    public var periodStart: Date = Date.now
    /// The day the period closed.
    public var closingDate: Date = Date.now
    /// The day payment is due.
    public var dueDate: Date = Date.now
    /// Balance computed from the period's transactions, in cents.
    public var computedBalanceCents: Int = 0
    /// User-entered figure superseding the computed one.
    public var overrideBalanceCents: Int?
    /// Whether the period has closed.
    public var isPeriodClosed: Bool = false
    /// Whether the interest-and-fees prompt has been resolved.
    public var interestPromptResolved: Bool = false

    /// Payments allocated against this statement.
    @Relationship(deleteRule: .cascade, inverse: \StatementPaymentRecord.statement)
    public var payments: [StatementPaymentRecord]? = []

    /// Creates a card statement record with default values.
    /// - Parameter id: Stable identifier.
    public init(id: UUID = UUID()) {
        self.id = id
    }
}

/// Persistent form of ``Domain/StatementPayment``.
@Model
public final class StatementPaymentRecord {
    /// Stable identifier.
    public var id: UUID = UUID()
    /// The statement being paid.
    public var statement: CardStatementRecord?
    /// The paying `transferIn` transaction.
    public var transaction: TransactionRecord?
    /// Amount allocated to this statement, in cents.
    public var amountCents: Int = 0

    /// Creates a statement payment record with default values.
    /// - Parameter id: Stable identifier.
    public init(id: UUID = UUID()) {
        self.id = id
    }
}

/// Persistent form of ``Domain/Product``.
///
/// Carries no price, account or date: those live on ``transaction``, which is the one
/// place a purchase's money is recorded (§7.8).
@Model
public final class ProductRecord {
    /// Stable identifier.
    public var id: UUID = UUID()
    /// Product name.
    public var name: String = ""
    /// The purchase this product was part of.
    ///
    /// Optional only because SwiftData and CloudKit require it to be; the repository
    /// refuses to write a product without one.
    public var transaction: TransactionRecord?
    /// The assigned product category.
    public var categoryID: UUID?
    /// Arbitrary user labels.
    public var tags: [String] = []
    /// Free-text note.
    public var notes: String?
    /// Ordering position within its transaction.
    public var sortIndex: Int = 0

    /// Whether the product is on a free trial.
    public var hasTrial: Bool = false
    /// When the free trial ends.
    public var trialEndsDate: Date?
    /// Lead time for the trial reminder.
    public var trialReminderLeadTime: ReminderLeadTime = ReminderLeadTime.useDefault

    /// Whether the product carries a warranty or expiry date.
    public var hasWarranty: Bool = false
    /// When the warranty expires.
    public var warrantyExpiresDate: Date?
    /// Lead time for the warranty reminder.
    public var warrantyReminderLeadTime: ReminderLeadTime = ReminderLeadTime.useDefault

    /// The recurring rule that bills for this product.
    @Relationship(deleteRule: .nullify, inverse: \RecurringRuleRecord.product)
    public var recurringRule: RecurringRuleRecord?

    /// Creates a product record with default values.
    /// - Parameter id: Stable identifier.
    public init(id: UUID = UUID()) {
        self.id = id
    }
}

/// Persistent form of ``Domain/Comparison``.
@Model
public final class ComparisonRecord {
    /// Stable identifier.
    public var id: UUID = UUID()
    /// Display label for the history chip.
    public var label: String = ""
    /// The dimension both items are measured in.
    public var unitCategory: UnitCategory?
    /// Item A's price in cents.
    public var itemAPriceCents: Int?
    /// Item A's quantity.
    public var itemAQuantity: Double?
    /// Item A's unit raw value.
    public var itemAUnit: String?
    /// Item B's price in cents.
    public var itemBPriceCents: Int?
    /// Item B's quantity.
    public var itemBQuantity: Double?
    /// Item B's unit raw value.
    public var itemBUnit: String?
    /// Manual ordering position in the history strip.
    public var sortIndex: Int = 0

    /// Creates a comparison record with default values.
    /// - Parameter id: Stable identifier.
    public init(id: UUID = UUID()) {
        self.id = id
    }
}

/// Persistent form of ``Domain/MerchantCategoryRule``.
///
/// `merchantKey` carries no `@Attribute(.unique)` — that attribute is unavailable
/// under CloudKit, which the whole schema is shaped for. Uniqueness is enforced by
/// ``SwiftDataMerchantCategoryRuleRepository``, which upserts on the key.
@Model
public final class MerchantCategoryRuleRecord {
    /// Stable identifier.
    public var id: UUID = UUID()
    /// The normalised merchant key this pin matches on.
    public var merchantKey: String = ""
    /// The merchant name as the user typed it.
    public var displayName: String = ""
    /// The category this merchant always files under.
    ///
    /// A loose identifier rather than a relationship, matching how every other record
    /// refers to a category.
    public var categoryID: UUID?
    /// When the pin was last written.
    public var updatedAt: Date = Date.distantPast

    /// Creates a pin record with default values.
    /// - Parameter id: Stable identifier.
    public init(id: UUID = UUID()) {
        self.id = id
    }
}
