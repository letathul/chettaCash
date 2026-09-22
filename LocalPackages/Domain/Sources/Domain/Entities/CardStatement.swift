import Foundation

/// One billing period on a credit card (§4.6).
///
/// A card carries two figures and both must be shown: the current balance, which
/// includes charges made after the period closed, and the statement balance, which
/// is what is actually due on the due date.
public struct CardStatement: Identifiable, Hashable, Sendable {
    /// Stable identifier, preserved across backup export and import.
    public let id: UUID
    /// The card this statement belongs to.
    public var accountID: UUID?
    /// First day of the billing period.
    public var periodStart: Date
    /// The day the period closed.
    public var closingDate: Date
    /// The day payment is due.
    public var dueDate: Date
    /// Balance computed from transactions in the period, in cents.
    public var computedBalanceCents: Int
    /// User-entered figure that supersedes ``computedBalanceCents`` when the real
    /// statement differs.
    public var overrideBalanceCents: Int?
    /// Whether the period has closed.
    public var isPeriodClosed: Bool
    /// Whether the interest-and-fees prompt has been answered or dismissed.
    ///
    /// Once `true` the prompt never appears again for this statement.
    public var interestPromptResolved: Bool

    /// The figure actually owed for this period, preferring the user's override.
    public var effectiveBalanceCents: Int {
        overrideBalanceCents ?? computedBalanceCents
    }

    /// Creates a card statement.
    /// - Parameters:
    ///   - id: Stable identifier. Defaults to a fresh UUID.
    ///   - accountID: The card this statement belongs to.
    ///   - periodStart: First day of the billing period.
    ///   - closingDate: The day the period closed.
    ///   - dueDate: The day payment is due.
    ///   - computedBalanceCents: Balance computed from the period's transactions.
    ///   - overrideBalanceCents: User-entered figure superseding the computed one.
    ///   - isPeriodClosed: Whether the period has closed.
    ///   - interestPromptResolved: Whether the interest prompt has been resolved.
    public init(
        id: UUID = UUID(),
        accountID: UUID? = nil,
        periodStart: Date = .now,
        closingDate: Date = .now,
        dueDate: Date = .now,
        computedBalanceCents: Int = 0,
        overrideBalanceCents: Int? = nil,
        isPeriodClosed: Bool = false,
        interestPromptResolved: Bool = false
    ) {
        self.id = id
        self.accountID = accountID
        self.periodStart = periodStart
        self.closingDate = closingDate
        self.dueDate = dueDate
        self.computedBalanceCents = computedBalanceCents
        self.overrideBalanceCents = overrideBalanceCents
        self.isPeriodClosed = isPeriodClosed
        self.interestPromptResolved = interestPromptResolved
    }
}

/// An allocation of one card payment against one statement (§4.6).
///
/// Payments allocate to the oldest open statement first. Overflow beyond a
/// statement's balance reduces the current balance without being allocated.
public struct StatementPayment: Identifiable, Hashable, Sendable {
    /// Stable identifier.
    public let id: UUID
    /// The statement this payment is allocated against.
    public var statementID: UUID?
    /// The `transferIn` transaction that paid the card.
    public var transactionID: UUID?
    /// How much of that payment is allocated to this statement, in cents.
    public var amountCents: Int

    /// Creates a statement payment allocation.
    /// - Parameters:
    ///   - id: Stable identifier. Defaults to a fresh UUID.
    ///   - statementID: The statement being paid.
    ///   - transactionID: The paying transaction.
    ///   - amountCents: Amount allocated to this statement, in cents.
    public init(
        id: UUID = UUID(),
        statementID: UUID? = nil,
        transactionID: UUID? = nil,
        amountCents: Int = 0
    ) {
        self.id = id
        self.statementID = statementID
        self.transactionID = transactionID
        self.amountCents = amountCents
    }
}
