import Foundation

/// What kind of line a statement row is.
///
/// The distinction is not cosmetic: a charge and a refund become transactions, and a
/// payment must not — see ``SkipReason/cardPayment``.
public enum StatementRowKind: String, Sendable, Equatable, CaseIterable {
    /// Money spent on the card.
    case charge
    /// Money returned to the card by a merchant.
    case refund
    /// A payment made against the card's balance from another account.
    case payment
}

/// One line of a credit-card statement, before it becomes anything.
public struct StatementRow: Identifiable, Hashable, Sendable {
    /// Stable identifier for this row within the import.
    public let id: UUID
    /// The date the statement printed, which is the *posting* date.
    public var date: Date
    /// The descriptor exactly as the statement printed it, never rewritten.
    ///
    /// Kept verbatim alongside ``cleanedMerchant`` so the wizard can show the user the
    /// text they would recognise from their own statement.
    public var rawDescriptor: String
    /// Positive magnitude in cents. The direction comes from ``kind``, never from here.
    public var amountCents: Int
    /// Whether the line is a charge, a refund or a payment.
    public var kind: StatementRowKind
    /// A readable shop name, when a reader could produce one.
    public var cleanedMerchant: String?

    /// The name to file the transaction under: the tidied one when there is one.
    public var merchant: String { cleanedMerchant ?? rawDescriptor }

    /// Creates a statement row.
    /// - Parameters:
    ///   - id: Stable identifier. Defaults to a fresh UUID.
    ///   - date: The date the statement printed.
    ///   - rawDescriptor: The descriptor as printed.
    ///   - amountCents: Positive magnitude in cents.
    ///   - kind: Charge, refund or payment.
    ///   - cleanedMerchant: A readable shop name, if one was produced.
    public init(
        id: UUID = UUID(),
        date: Date,
        rawDescriptor: String,
        amountCents: Int,
        kind: StatementRowKind = .charge,
        cleanedMerchant: String? = nil
    ) {
        self.id = id
        self.date = date
        self.rawDescriptor = rawDescriptor
        self.amountCents = amountCents
        self.kind = kind
        self.cleanedMerchant = cleanedMerchant
    }
}

/// A whole statement, as read off a file.
public struct StatementDocument: Equatable, Sendable {
    /// The card's digits and network, so ``AccountMatcher`` can take it directly.
    public var tender: ReceiptTender
    /// The first day of the statement's period, when it could be read.
    public var periodStart: Date?
    /// The day the statement closed, when it could be read.
    public var closingDate: Date?
    /// Every transaction line found.
    public var rows: [StatementRow]
    /// Which reader produced this.
    ///
    /// Reuses ``ReceiptScanSource`` rather than declaring a second identical enum: the
    /// meaning is already "which reader produced this", not anything receipt-specific.
    public var source: ReceiptScanSource
    /// Lines that looked like transactions but could not be read. See ``UnreadLine``.
    public var unread: [UnreadLine]
    /// How many lines the source actually held, before any of them were parsed.
    ///
    /// Counted at the source rather than derived from ``rows``, because the difference
    /// between the two is the whole point: a summary that reports the post-parse count can
    /// never say that anything went missing.
    public var sourceLineCount: Int

    /// Whether nothing usable was found.
    public var isEmpty: Bool { rows.isEmpty }

    /// Creates a document.
    /// - Parameters:
    ///   - tender: The card's digits and network.
    ///   - periodStart: The first day of the period.
    ///   - closingDate: The day the statement closed.
    ///   - rows: The transaction lines.
    ///   - source: Which reader produced it.
    ///   - unread: Lines that looked like transactions but could not be read.
    ///   - sourceLineCount: How many lines the source held. Defaults to the row count.
    public init(
        tender: ReceiptTender = ReceiptTender(),
        periodStart: Date? = nil,
        closingDate: Date? = nil,
        rows: [StatementRow] = [],
        source: ReceiptScanSource = .textHeuristics,
        unread: [UnreadLine] = [],
        sourceLineCount: Int? = nil
    ) {
        self.tender = tender
        self.periodStart = periodStart
        self.closingDate = closingDate
        self.rows = rows
        self.source = source
        self.unread = unread
        self.sourceLineCount = sourceLineCount ?? (rows.count + unread.count)
    }
}

/// Why a statement row produced no transaction.
public enum SkipReason: String, Sendable, Equatable, CaseIterable {
    /// The ledger already records this purchase.
    ///
    /// Not a byte-identical match: the same card, amount and merchant within the import's
    /// day tolerance, because the statement's date and the user's rarely agree exactly.
    case exactDuplicate
    /// The row is a payment against the card, which cannot be imported. See
    /// ``SkipReason/cardPaymentExplanation``.
    case cardPayment
    /// No amount could be read, so importing it would invent a figure.
    case unreadableAmount

    /// What to tell the user about this kind of skip, or `nil` when it needs no comment.
    public var explanation: String? {
        switch self {
        case .exactDuplicate: return nil
        case .cardPayment:
            return SkipReason.cardPaymentExplanation
        case .unreadableAmount:
            return "Some lines had no readable amount and were left out."
        }
    }

    /// Why a card payment is never imported.
    ///
    /// A payment on the statement is the far side of a transfer the user records from the
    /// account they paid *from*. Importing it as income would inflate income totals, which
    /// §4.3 forbids for the transfer legs it mirrors; importing it as a transfer leg would
    /// create a half-transfer, which ``TransactionRepository`` forbids outright.
    public static let cardPaymentExplanation =
        "Card payments were left out — record those as a transfer from the account you paid from."
}

/// A statement row that produced no transaction, and why.
public struct SkippedRow: Identifiable, Hashable, Sendable {
    /// The row's identity.
    public var id: UUID { row.id }
    /// The row that was skipped.
    public var row: StatementRow
    /// Why it was skipped.
    public var reason: SkipReason

    /// Creates a skipped row.
    /// - Parameters:
    ///   - row: The row that was skipped.
    ///   - reason: Why it was skipped.
    public init(row: StatementRow, reason: SkipReason) {
        self.row = row
        self.reason = reason
    }
}

/// Why two entries look like the same purchase.
public enum DuplicateReason: String, Sendable, Equatable, CaseIterable {
    /// Same card, same day, same amount — only the wording differs.
    case sameDaySameAmount
    /// Same card and amount a day apart, which is the usual posting lag.
    case adjacentDaySameAmount
    /// Same card and amount several days apart, which a weekend or a holiday produces.
    case nearbyDaySameAmount

    /// The one line shown under the comparison.
    public var explanation: String {
        switch self {
        case .sameDaySameAmount:
            return "Same card, same day, same amount — only the wording differs."
        case .adjacentDaySameAmount:
            return "Same card and amount, a day apart — statements post a day late."
        case .nearbyDaySameAmount:
            return "Same card and amount, a few days apart — a weekend purchase posts on the Monday."
        }
    }
}

/// One entry the ledger already holds that may be the same purchase as an incoming row.
public struct DuplicateConflict: Identifiable, Hashable, Sendable {
    /// Stable identifier for this conflict.
    public let id: UUID
    /// The transaction the import would write.
    public var incoming: Transaction
    /// The statement row it came from, kept so the wizard can show the raw descriptor.
    public var row: StatementRow
    /// The entry already in the ledger.
    public var existing: Transaction
    /// Why the two were paired.
    public var reason: DuplicateReason

    /// Creates a conflict.
    /// - Parameters:
    ///   - id: Stable identifier. Defaults to a fresh UUID.
    ///   - incoming: The transaction the import would write.
    ///   - row: The statement row it came from.
    ///   - existing: The entry already in the ledger.
    ///   - reason: Why the two were paired.
    public init(
        id: UUID = UUID(),
        incoming: Transaction,
        row: StatementRow,
        existing: Transaction,
        reason: DuplicateReason
    ) {
        self.id = id
        self.incoming = incoming
        self.row = row
        self.existing = existing
        self.reason = reason
    }
}

/// What importing a statement would write, decided before anything is written.
public struct ImportPlan: Sendable, Equatable {
    /// Transactions with no conflict, ready to save.
    public var additions: [Transaction]
    /// Pairs that need the user to decide.
    public var conflicts: [DuplicateConflict]
    /// Rows that produced nothing, and why.
    public var skipped: [SkippedRow]
    /// Lines the reader could not turn into rows at all. See ``UnreadLine``.
    public var unread: [UnreadLine]
    /// How many lines the statement held, counted at the source.
    public var rowsProcessed: Int

    /// Whether the import would change nothing and ask nothing.
    public var isNoOp: Bool { additions.isEmpty && conflicts.isEmpty }

    /// Creates a plan.
    /// - Parameters:
    ///   - additions: Transactions ready to save.
    ///   - conflicts: Pairs needing a decision.
    ///   - skipped: Rows that produced nothing.
    ///   - unread: Lines the reader could not turn into rows.
    ///   - rowsProcessed: How many lines the statement held.
    public init(
        additions: [Transaction] = [],
        conflicts: [DuplicateConflict] = [],
        skipped: [SkippedRow] = [],
        unread: [UnreadLine] = [],
        rowsProcessed: Int = 0
    ) {
        self.additions = additions
        self.conflicts = conflicts
        self.skipped = skipped
        self.unread = unread
        self.rowsProcessed = rowsProcessed
    }
}
