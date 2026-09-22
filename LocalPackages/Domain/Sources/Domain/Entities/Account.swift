import Foundation

/// A named grouping of accounts, such as "Everyday" or "Savings".
public struct AccountGroup: Identifiable, Hashable, Sendable {
    /// Stable identifier, preserved across backup export and import.
    public let id: UUID
    /// Display name shown as the group header in Settings.
    public var name: String
    /// Manual ordering position within the accounts list.
    public var sortIndex: Int

    /// Creates an account group.
    /// - Parameters:
    ///   - id: Stable identifier. Defaults to a fresh UUID.
    ///   - name: Display name.
    ///   - sortIndex: Manual ordering position.
    public init(id: UUID = UUID(), name: String = "", sortIndex: Int = 0) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
    }
}

/// A cash account or credit card that transactions are recorded against.
///
/// The current balance is never stored as the source of truth. It is derived by
/// ``BalanceEngine/currentBalanceCents(account:transactions:asOf:)`` from the
/// opening balance plus every posted transaction (§4.1). ``cachedBalanceCents``
/// is a denormalised cache of that computation, not an authority.
public struct Account: Identifiable, Hashable, Sendable {
    /// Stable identifier, preserved across backup export and import.
    public let id: UUID
    /// Display name, such as "TD Chequing".
    public var name: String
    /// Whether this is a spending account or a credit card.
    public var kind: AccountKind
    /// The balance this account held on ``openingBalanceDate``, in cents.
    ///
    /// For cards this is stored negative when money is owed. See
    /// ``BalanceEngine/normalizedOpeningBalanceCents(_:kind:)``.
    public var openingBalanceCents: Int
    /// The date ``openingBalanceCents`` applies from.
    public var openingBalanceDate: Date
    /// Denormalised cache of the derived current balance, in cents.
    public var cachedBalanceCents: Int
    /// Manual ordering position within its group.
    public var sortIndex: Int
    /// Whether the account has been closed (§4.7). Closed accounts are never deleted.
    public var isClosed: Bool
    /// The date the account was closed, if it is closed.
    public var closedDate: Date?
    /// The group this account belongs to.
    public var groupID: UUID?

    /// Day of month the card statement closes, for card accounts.
    public var statementDayOfMonth: Int?
    /// Day of month the card payment is due, for card accounts.
    public var paymentDueDayOfMonth: Int?
    /// Whether to schedule a payment reminder ahead of the due date.
    public var remindBeforeDueDate: Bool

    /// The last four digits of the card used on this account, if the user recorded them.
    ///
    /// Offered on every kind, not just ``AccountKind/card``: a chequing account has a
    /// debit card, and receipts print those the same way. Used only to match a scanned
    /// receipt back to its account (§9.7) — never to identify the card to anyone else,
    /// which is why four digits is all that is stored.
    public var last4: String?
    /// The payment network that card runs on.
    public var cardNetwork: CardNetwork?

    /// Creates an account.
    /// - Parameters:
    ///   - id: Stable identifier. Defaults to a fresh UUID.
    ///   - name: Display name.
    ///   - kind: Spending account or credit card.
    ///   - openingBalanceCents: Balance held on `openingBalanceDate`, in cents.
    ///   - openingBalanceDate: The date the opening balance applies from.
    ///   - cachedBalanceCents: Denormalised current-balance cache.
    ///   - sortIndex: Manual ordering position.
    ///   - isClosed: Whether the account is closed.
    ///   - closedDate: The date the account was closed.
    ///   - groupID: The owning group.
    ///   - statementDayOfMonth: Card statement closing day.
    ///   - paymentDueDayOfMonth: Card payment due day.
    ///   - remindBeforeDueDate: Whether to remind ahead of the due date.
    ///   - last4: The last four digits of this account's card.
    ///   - cardNetwork: The network that card runs on.
    public init(
        id: UUID = UUID(),
        name: String = "",
        kind: AccountKind = .account,
        openingBalanceCents: Int = 0,
        openingBalanceDate: Date = .now,
        cachedBalanceCents: Int = 0,
        sortIndex: Int = 0,
        isClosed: Bool = false,
        closedDate: Date? = nil,
        groupID: UUID? = nil,
        statementDayOfMonth: Int? = nil,
        paymentDueDayOfMonth: Int? = nil,
        remindBeforeDueDate: Bool = true,
        last4: String? = nil,
        cardNetwork: CardNetwork? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.openingBalanceCents = openingBalanceCents
        self.openingBalanceDate = openingBalanceDate
        self.cachedBalanceCents = cachedBalanceCents
        self.sortIndex = sortIndex
        self.isClosed = isClosed
        self.closedDate = closedDate
        self.groupID = groupID
        self.statementDayOfMonth = statementDayOfMonth
        self.paymentDueDayOfMonth = paymentDueDayOfMonth
        self.remindBeforeDueDate = remindBeforeDueDate
        self.last4 = last4
        self.cardNetwork = cardNetwork
    }
}
