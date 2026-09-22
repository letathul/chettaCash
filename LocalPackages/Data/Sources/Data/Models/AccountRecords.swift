import Foundation
import SwiftData
import Domain

/// Persistent form of ``Domain/AccountGroup``.
@Model
public final class AccountGroupRecord {
    /// Stable identifier. Uniqueness is enforced in application code, because
    /// `@Attribute(.unique)` is unavailable under CloudKit.
    public var id: UUID = UUID()
    /// Display name shown as the group header.
    public var name: String = ""
    /// Manual ordering position.
    public var sortIndex: Int = 0

    /// Accounts belonging to this group.
    @Relationship(deleteRule: .nullify, inverse: \AccountRecord.group)
    public var accounts: [AccountRecord]? = []

    /// Creates an account group record.
    /// - Parameters:
    ///   - id: Stable identifier.
    ///   - name: Display name.
    ///   - sortIndex: Manual ordering position.
    public init(id: UUID = UUID(), name: String = "", sortIndex: Int = 0) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
    }
}

/// Persistent form of ``Domain/Account``.
///
/// `cachedBalanceCents` is a denormalised cache of the derived balance, never the
/// source of truth (§4.1). Accounts are closed, never deleted, so every delete rule
/// here nullifies except `statements`, which cascades (§4.7).
@Model
public final class AccountRecord {
    /// Stable identifier.
    public var id: UUID = UUID()
    /// Display name.
    public var name: String = ""
    /// Whether this is a spending account or a credit card.
    public var kind: AccountKind = AccountKind.account
    /// Balance held on `openingBalanceDate`, in cents.
    public var openingBalanceCents: Int = 0
    /// The date the opening balance applies from.
    public var openingBalanceDate: Date = Date.now
    /// Denormalised cache of the derived balance, in cents.
    public var cachedBalanceCents: Int = 0
    /// Manual ordering position within its group.
    public var sortIndex: Int = 0
    /// Whether the account has been closed.
    public var isClosed: Bool = false
    /// The date the account was closed.
    public var closedDate: Date?
    /// The owning group.
    public var group: AccountGroupRecord?

    /// Day of month the card statement closes.
    public var statementDayOfMonth: Int?
    /// Day of month the card payment is due.
    public var paymentDueDayOfMonth: Int?
    /// Whether to remind ahead of the due date.
    public var remindBeforeDueDate: Bool = true

    /// The last four digits of this account's card, if the user recorded them.
    ///
    /// Optional with no default, like `closedDate`, so adding it stays a lightweight
    /// migration: an existing store gains the column as `nil` without a versioned schema.
    public var last4: String?
    /// The payment network that card runs on.
    public var cardNetwork: CardNetwork?

    /// Transactions recorded against this account.
    @Relationship(deleteRule: .nullify, inverse: \TransactionRecord.account)
    public var transactions: [TransactionRecord]? = []
    /// Billing periods on this card.
    @Relationship(deleteRule: .cascade, inverse: \CardStatementRecord.account)
    public var statements: [CardStatementRecord]? = []

    /// Creates an account record with default values.
    /// - Parameter id: Stable identifier.
    public init(id: UUID = UUID()) {
        self.id = id
    }
}
