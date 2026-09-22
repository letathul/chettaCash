import Foundation

/// A single ledger entry against one account.
///
/// A transaction dated in the future exists in the database but is inert: it does
/// not affect balances, spend totals or charts until its date arrives (§4.2).
/// Use ``BalanceEngine/isPosted(_:asOf:)`` rather than comparing dates inline.
///
/// A transaction is the unit of purchase: it owns the money and the receipt, and the
/// ``Product`` rows pointing at it are the things that purchase contained (§7.8).
///
/// - Note: SwiftUI declares its own `Transaction` type. In any file that imports
///   SwiftUI, refer to this type as `Domain.Transaction`.
public struct Transaction: Identifiable, Hashable, Sendable {
    /// Stable identifier, preserved across backup export and import.
    public let id: UUID
    /// Magnitude of the transaction in cents, always positive.
    ///
    /// The sign comes from ``type``, never from this value. See
    /// ``BalanceEngine/signedAmountCents(for:)``.
    public var amountCents: Int
    /// What kind of entry this is, which determines its sign.
    public var type: TransactionType
    /// Signed amount for ``TransactionType/adjustment`` entries, which may be negative.
    public var signedOverrideCents: Int?
    /// The assigned category. Always `nil` for both transfer legs (§4.3).
    public var categoryID: UUID?
    /// The account this entry is recorded against.
    public var accountID: UUID?
    /// When the transaction occurred. Compared against the clock to decide posting.
    public var date: Date
    /// Merchant or payer name.
    public var merchant: String
    /// Optional place of purchase.
    public var location: String?
    /// Optional free-text note.
    public var memo: String?
    /// Arbitrary user labels. Unlimited, unlike categories (§4.8).
    public var tags: [String]

    /// Links the two legs of a transfer. Both legs share one value (§4.3).
    public var transferGroupID: UUID?
    /// The recurring rule that generated this occurrence, if any.
    public var recurringRuleID: UUID?
    /// Whether this occurrence has been edited away from its rule's values.
    public var isSeriesOverride: Bool

    /// Identifier of the stored receipt image in the receipt store.
    public var receiptFileID: String?
    /// Original file name of the stored receipt image.
    public var receiptFileName: String?
    /// Checksum used to verify a receipt after transfer.
    public var receiptChecksum: String?
    /// Progress of the receipt image toward cloud storage.
    public var receiptUploadState: ReceiptUploadState

    /// Creates a transaction.
    /// - Parameters:
    ///   - id: Stable identifier. Defaults to a fresh UUID.
    ///   - amountCents: Positive magnitude in cents.
    ///   - type: The kind of entry, which determines the sign.
    ///   - signedOverrideCents: Signed amount, for adjustments only.
    ///   - categoryID: Assigned category, or `nil` for transfer legs.
    ///   - accountID: The account this entry belongs to.
    ///   - date: When the transaction occurred.
    ///   - merchant: Merchant or payer name.
    ///   - location: Optional place of purchase.
    ///   - memo: Optional free-text note.
    ///   - tags: Arbitrary user labels.
    ///   - transferGroupID: Shared identifier linking two transfer legs.
    ///   - recurringRuleID: The rule that generated this occurrence.
    ///   - isSeriesOverride: Whether this occurrence diverges from its rule.
    ///   - receiptFileID: Identifier of the stored receipt image.
    ///   - receiptFileName: Original receipt file name.
    ///   - receiptChecksum: Checksum for verifying the receipt.
    ///   - receiptUploadState: Receipt upload progress.
    public init(
        id: UUID = UUID(),
        amountCents: Int = 0,
        type: TransactionType = .expense,
        signedOverrideCents: Int? = nil,
        categoryID: UUID? = nil,
        accountID: UUID? = nil,
        date: Date = .now,
        merchant: String = "",
        location: String? = nil,
        memo: String? = nil,
        tags: [String] = [],
        transferGroupID: UUID? = nil,
        recurringRuleID: UUID? = nil,
        isSeriesOverride: Bool = false,
        receiptFileID: String? = nil,
        receiptFileName: String? = nil,
        receiptChecksum: String? = nil,
        receiptUploadState: ReceiptUploadState = .none
    ) {
        self.id = id
        self.amountCents = amountCents
        self.type = type
        self.signedOverrideCents = signedOverrideCents
        self.categoryID = categoryID
        self.accountID = accountID
        self.date = date
        self.merchant = merchant
        self.location = location
        self.memo = memo
        self.tags = tags
        self.transferGroupID = transferGroupID
        self.recurringRuleID = recurringRuleID
        self.isSeriesOverride = isSeriesOverride
        self.receiptFileID = receiptFileID
        self.receiptFileName = receiptFileName
        self.receiptChecksum = receiptChecksum
        self.receiptUploadState = receiptUploadState
    }
}
