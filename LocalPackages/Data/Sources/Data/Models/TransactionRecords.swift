import Foundation
import SwiftData
import Domain

/// Persistent form of ``Domain/Transaction``.
///
/// A row dated in the future exists here but is inert until its date arrives (§4.2).
@Model
public final class TransactionRecord {
    /// Stable identifier.
    public var id: UUID = UUID()
    /// Positive magnitude in cents. The sign comes from `type`.
    public var amountCents: Int = 0
    /// The kind of entry, which determines its sign.
    public var type: TransactionType = TransactionType.expense
    /// Signed amount for adjustments, which may be negative.
    public var signedOverrideCents: Int?
    /// The assigned category. Always `nil` for both transfer legs.
    public var categoryID: UUID?
    /// The account this entry is recorded against.
    public var account: AccountRecord?
    /// When the transaction occurred.
    public var date: Date = Date.now
    /// Merchant or payer name.
    public var merchant: String = ""
    /// Optional place of purchase.
    public var location: String?
    /// Optional free-text note.
    public var memo: String?
    /// Arbitrary user labels.
    public var tags: [String] = []

    /// Links the two legs of a transfer.
    public var transferGroupID: UUID?
    /// The rule that generated this occurrence.
    public var recurringRule: RecurringRuleRecord?
    /// Whether this occurrence diverges from its rule.
    public var isSeriesOverride: Bool = false

    /// Identifier of the stored receipt image.
    public var receiptFileID: String?
    /// Original receipt file name.
    public var receiptFileName: String?
    /// Checksum used to verify a receipt after transfer.
    public var receiptChecksum: String?
    /// Receipt upload progress.
    public var receiptUploadState: ReceiptUploadState = ReceiptUploadState.none

    /// The import fingerprint, so a statement row already recorded can be found (§4.2).
    ///
    /// A denormalised copy of ``Domain/Transaction/transactionHash``, which is computed —
    /// this column exists only so the store can be queried by it, exactly as
    /// `AccountRecord.cachedBalanceCents` caches a derived balance. Empty on rows written
    /// before statement import existed, which needs no migration because the import
    /// recomputes every key it compares.
    ///
    /// Deliberately **not** `@Attribute(.unique)`: a unique constraint is forbidden here
    /// (see ``ModelContainerFactory``), and uniqueness is enforced by
    /// ``StatementImportPlanner`` instead.
    public var transactionHash: String = ""

    /// The products this purchase contained (§7.8).
    ///
    /// Cascade: deleting the purchase deletes the things it bought, because a product
    /// with no transaction is not representable. The inverse is declared so the
    /// relationship satisfies CloudKit and so SwiftData keeps both sides in step.
    @Relationship(deleteRule: .cascade, inverse: \ProductRecord.transaction)
    public var products: [ProductRecord]? = []

    /// Creates a transaction record with default values.
    /// - Parameter id: Stable identifier.
    public init(id: UUID = UUID()) {
        self.id = id
    }
}

/// Persistent form of ``Domain/RecurringRule``.
@Model
public final class RecurringRuleRecord {
    /// Stable identifier.
    public var id: UUID = UUID()
    /// Display name for the series.
    public var name: String = ""
    /// Magnitude of each occurrence, in cents.
    public var amountCents: Int = 0
    /// The type each occurrence takes.
    public var type: TransactionType = TransactionType.expense
    /// Category applied to each occurrence.
    public var categoryID: UUID?
    /// Account each occurrence is recorded against.
    public var account: AccountRecord?
    /// How often the rule fires.
    public var frequency: RecurringFrequency = RecurringFrequency.monthly
    /// Date of the first occurrence.
    public var startDate: Date = Date.now
    /// Optional end date.
    public var endDate: Date?
    /// Optional cap on total occurrences.
    public var occurrenceLimit: Int?
    /// How many occurrences exist so far.
    public var occurrencesGenerated: Int = 0
    /// Whether the rule still generates occurrences.
    public var isActive: Bool = true
    /// The product this rule bills for.
    public var product: ProductRecord?

    /// Creates a recurring rule record with default values.
    /// - Parameter id: Stable identifier.
    public init(id: UUID = UUID()) {
        self.id = id
    }
}
