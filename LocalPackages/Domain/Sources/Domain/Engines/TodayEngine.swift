import Foundation

/// A card statement approaching or past its due date (§7.2).
public struct DueStatementItem: Identifiable, Sendable {
    /// The statement due.
    public let statement: CardStatement
    /// The card's name.
    public let accountName: String
    /// How much has been paid toward it.
    public let paidCents: Int
    /// How much is still due.
    public let outstandingCents: Int
    /// Whole days until the due date. Negative when overdue.
    public let daysRemaining: Int

    /// The item's identity.
    public var id: UUID { statement.id }
    /// Whether the due date has passed.
    public var isOverdue: Bool { daysRemaining < 0 }

    /// Creates an item.
    /// - Parameters:
    ///   - statement: The statement due.
    ///   - accountName: The card's name.
    ///   - paidCents: How much has been paid.
    ///   - outstandingCents: How much is still due.
    ///   - daysRemaining: Days until due, negative when overdue.
    public init(
        statement: CardStatement,
        accountName: String,
        paidCents: Int,
        outstandingCents: Int,
        daysRemaining: Int
    ) {
        self.statement = statement
        self.accountName = accountName
        self.paidCents = paidCents
        self.outstandingCents = outstandingCents
        self.daysRemaining = daysRemaining
    }
}

/// A card statement whose due date passed while it was still owed (§7.2, §4.6).
///
/// Statement balances are cumulative, so an unpaid month is never lost — it rolls into
/// the next statement. But that next statement has its own later due date, which would
/// otherwise leave a missed payment completely unannounced.
public struct MissedPaymentItem: Identifiable, Sendable {
    /// The statement that went unpaid.
    public let statement: CardStatement
    /// The card's name.
    public let accountName: String
    /// How much of it is still owed.
    public let outstandingCents: Int
    /// Whole days since the due date passed.
    public let daysOverdue: Int

    /// The item's identity.
    public var id: UUID { statement.id }

    /// Creates an item.
    /// - Parameters:
    ///   - statement: The statement that went unpaid.
    ///   - accountName: The card's name.
    ///   - outstandingCents: How much is still owed.
    ///   - daysOverdue: Whole days since the due date passed.
    public init(
        statement: CardStatement,
        accountName: String,
        outstandingCents: Int,
        daysOverdue: Int
    ) {
        self.statement = statement
        self.accountName = accountName
        self.outstandingCents = outstandingCents
        self.daysOverdue = daysOverdue
    }
}

/// The next occurrence of an active recurring rule (§7.2).
public struct UpcomingChargeItem: Identifiable, Sendable {
    /// The rule that will charge.
    public let rule: RecurringRule
    /// The account it charges.
    public let accountName: String
    /// When it next charges.
    public let date: Date

    /// The item's identity.
    public var id: UUID { rule.id }

    /// Creates an item.
    /// - Parameters:
    ///   - rule: The rule that will charge.
    ///   - accountName: The account it charges.
    ///   - date: When it next charges.
    public init(rule: RecurringRule, accountName: String, date: Date) {
        self.rule = rule
        self.accountName = accountName
        self.date = date
    }
}

/// A trial or warranty approaching expiry (§7.2).
public struct EndingSoonItem: Identifiable, Sendable {
    /// Which kind of date is ending.
    public enum Kind: String, Sendable {
        /// A free trial is ending.
        case trial
        /// A warranty or expiry date is approaching.
        case warranty
    }

    /// The product.
    public let item: Product
    /// Which date is ending.
    public let kind: Kind
    /// When it ends.
    public let date: Date
    /// Whole days until it ends. Negative when already past.
    public let daysRemaining: Int

    /// The item's identity, distinct per kind so one product can appear twice.
    public var id: String { "\(item.id)-\(kind.rawValue)" }

    /// Creates an item.
    /// - Parameters:
    ///   - item: The product.
    ///   - kind: Which date is ending.
    ///   - date: When it ends.
    ///   - daysRemaining: Days until it ends.
    public init(item: Product, kind: Kind, date: Date, daysRemaining: Int) {
        self.item = item
        self.kind = kind
        self.date = date
        self.daysRemaining = daysRemaining
    }
}

/// A transaction written with no account, waiting to be told where it belongs (§15.5).
///
/// A Shortcut that could not work out which account an entry belonged to wrote it anyway
/// rather than losing it. Until it is assigned it counts toward spend totals and moves no
/// balance, so Spend and Available Cash disagree by exactly this much — which is why it
/// appears here rather than waiting to be noticed in the Ledger.
public struct UnassignedEntryItem: Identifiable, Sendable {
    /// The entry waiting for an account.
    public let transaction: Transaction

    /// The item's identity.
    public var id: UUID { transaction.id }
    /// What the entry says about itself, for a row that has no account to name.
    public var merchant: String { transaction.merchant }
    /// The amount, in cents.
    public var amountCents: Int { transaction.amountCents }
    /// When it happened.
    public var date: Date { transaction.date }

    /// Creates an item.
    /// - Parameter transaction: The entry waiting for an account.
    public init(transaction: Transaction) {
        self.transaction = transaction
    }
}

/// Everything the Today card and sheet report (§7.2).
///
/// The Dashboard answers "where do I stand"; this answers "what needs me". Every
/// section is omitted entirely when empty rather than showing an empty state, and a
/// day with nothing in any of them is a quiet day.
public struct TodayDigest: Sendable {
    /// Total spent today, in cents.
    public let spentTodayCents: Int
    /// How many transactions posted today.
    public let postedTodayCount: Int
    /// Card statements inside their reminder window, or overdue.
    public let dueSoon: [DueStatementItem]
    /// Statements whose due date passed while still owed.
    public let missedPayments: [MissedPaymentItem]
    /// The next occurrence of each active rule within the next 30 days.
    public let upcomingCharges: [UpcomingChargeItem]
    /// Trials and warranties approaching expiry.
    public let endingSoon: [EndingSoonItem]
    /// Entries written with no account, newest first (§15.5).
    public let unassignedEntries: [UnassignedEntryItem]

    /// Whether nothing at all needs the user's attention.
    ///
    /// On a quiet day the card still shows balances plus an explicit "Nothing due"
    /// line. It never hides itself and never shows empty chips.
    public var isQuietDay: Bool {
        spentTodayCents == 0 && dueSoon.isEmpty && upcomingCharges.isEmpty
            && endingSoon.isEmpty && missedPayments.isEmpty && unassignedEntries.isEmpty
    }

    /// Creates a digest.
    /// - Parameters:
    ///   - spentTodayCents: Total spent today.
    ///   - postedTodayCount: How many transactions posted today.
    ///   - dueSoon: Statements due or overdue.
    ///   - missedPayments: Statements whose due date passed while still owed.
    ///   - upcomingCharges: Next occurrence per active rule.
    ///   - endingSoon: Trials and warranties approaching expiry.
    ///   - unassignedEntries: Entries written with no account.
    public init(
        spentTodayCents: Int = 0,
        postedTodayCount: Int = 0,
        dueSoon: [DueStatementItem] = [],
        missedPayments: [MissedPaymentItem] = [],
        upcomingCharges: [UpcomingChargeItem] = [],
        endingSoon: [EndingSoonItem] = [],
        unassignedEntries: [UnassignedEntryItem] = []
    ) {
        self.spentTodayCents = spentTodayCents
        self.postedTodayCount = postedTodayCount
        self.dueSoon = dueSoon
        self.missedPayments = missedPayments
        self.upcomingCharges = upcomingCharges
        self.endingSoon = endingSoon
        self.unassignedEntries = unassignedEntries
    }
}
