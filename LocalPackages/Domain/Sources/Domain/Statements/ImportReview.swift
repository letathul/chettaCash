import Foundation

/// Why a reviewable row is in the state it is (§9.7).
///
/// The order matters to the screen that renders it: a row needing attention is asked about
/// first, and an approved row is the quiet default.
public enum ImportReviewStatus: Sendable, Equatable {
    /// Nothing is wrong with the row; it is ready to write.
    case ready
    /// The reader could not turn a line into a row. See ``UnreadProblem``.
    case needsAttention(UnreadProblem)
    /// The ledger may already record this purchase.
    case duplicate(existingID: UUID, reason: DuplicateReason)
    /// The row cannot be imported at all. See ``SkipReason``.
    case excluded(SkipReason)

    /// Whether this status starts the row ticked for import.
    ///
    /// **Only a clean row.** A duplicate pre-ticked is one careless tap from a double entry,
    /// and a card payment pre-ticked is a rule violation (§4.3) — both are the user's call,
    /// so both start untouched. Same reasoning as ``ConflictDraft`` before it.
    public var isTickedByDefault: Bool {
        if case .ready = self { return true }
        return false
    }

    /// Where the row sorts, lowest first: the rows needing a person come first.
    public var priority: Int {
        switch self {
        case .needsAttention: return 0
        case .duplicate: return 1
        case .excluded: return 2
        case .ready: return 3
        }
    }
}

/// One line of a statement, as something the user can read, change and approve (§9.7).
///
/// **Every source line becomes one of these.** Rows the planner would have written, rows it
/// would have skipped, rows it flagged as duplicates, and lines no reader could parse all
/// arrive here together — which is the point. The old flow committed the first group before
/// showing anything and reported the rest as counts, so a statement that read badly was
/// indistinguishable from a statement with little on it.
public struct ImportReviewRow: Identifiable, Sendable, Equatable {
    /// Stable identifier for this row within the review.
    public let id: UUID
    /// The statement's own wording, kept verbatim so the user can check it against their bank.
    public var sourceText: String
    /// The date the row will be filed under, or `nil` when none could be read.
    public var date: Date?
    /// The name the transaction will carry.
    public var merchant: String
    /// Positive magnitude in cents. The direction is carried by ``isIncome``, never by this.
    public var amountCents: Int
    /// Whether the row is money coming in rather than money spent.
    public var isIncome: Bool
    /// The category the row will be filed under, when one could be decided.
    public var categoryID: UUID?
    /// Why the row is in the state it is.
    public var status: ImportReviewStatus
    /// Whether the user has ticked the row for import.
    public var isTicked: Bool

    /// Whether the row holds enough to become a transaction.
    ///
    /// A row with no date or no amount cannot be written, so it cannot be ticked either —
    /// refused outright rather than quietly filled in with today's date and a zero, which is
    /// how a statement line becomes a ledger entry nobody meant to make.
    public var canBeTicked: Bool { date != nil && amountCents > 0 && !merchant.isEmpty }

    /// Creates a reviewable row.
    /// - Parameters:
    ///   - id: Stable identifier. Defaults to a fresh UUID.
    ///   - sourceText: The statement's own wording.
    ///   - date: The date the row will be filed under.
    ///   - merchant: The name the transaction will carry.
    ///   - amountCents: Positive magnitude in cents.
    ///   - isIncome: Whether the row is money coming in.
    ///   - categoryID: The category the row will be filed under.
    ///   - status: Why the row is in the state it is.
    ///   - isTicked: Whether the row is ticked. Defaults to what the status implies.
    public init(
        id: UUID = UUID(),
        sourceText: String,
        date: Date? = nil,
        merchant: String = "",
        amountCents: Int = 0,
        isIncome: Bool = false,
        categoryID: UUID? = nil,
        status: ImportReviewStatus = .ready,
        isTicked: Bool? = nil
    ) {
        self.id = id
        self.sourceText = sourceText
        self.date = date
        self.merchant = merchant
        self.amountCents = amountCents
        self.isIncome = isIncome
        self.categoryID = categoryID
        self.status = status
        let wanted = isTicked ?? status.isTickedByDefault
        self.isTicked = wanted && date != nil && amountCents > 0 && !merchant.isEmpty
    }
}

/// How a review's rows divide up, for the chips above the list.
public struct ImportReviewSummary: Sendable, Equatable {
    /// How many lines the statement held, counted at the source.
    public var sourceLines: Int
    /// How many rows are ticked and will be written.
    public var ticked: Int
    /// How many rows look like something the ledger already holds.
    public var duplicates: Int
    /// How many lines no reader could turn into a row.
    public var needsAttention: Int
    /// How many rows cannot be imported at all, card payments chiefly.
    public var excluded: Int

    /// Whether approving now would write nothing.
    public var isEmpty: Bool { ticked == 0 }

    /// Creates a summary.
    /// - Parameters:
    ///   - sourceLines: How many lines the statement held.
    ///   - ticked: How many rows will be written.
    ///   - duplicates: How many look like existing entries.
    ///   - needsAttention: How many lines could not be read.
    ///   - excluded: How many cannot be imported at all.
    public init(
        sourceLines: Int = 0,
        ticked: Int = 0,
        duplicates: Int = 0,
        needsAttention: Int = 0,
        excluded: Int = 0
    ) {
        self.sourceLines = sourceLines
        self.ticked = ticked
        self.duplicates = duplicates
        self.needsAttention = needsAttention
        self.excluded = excluded
    }
}

/// Reading a summary back to the user.
extension ImportReviewSummary {

    /// The one line above the list, in the shape ``ImportOutcome/summary`` established.
    ///
    /// Zero clauses are omitted rather than printed as "0 duplicates", so a clean statement
    /// reads as one short sentence instead of a row of noughts.
    public var headline: String {
        guard sourceLines > 0 else { return "Nothing to review." }
        var parts = ["\(sourceLines) \(sourceLines == 1 ? "line" : "lines")"]
        if ticked > 0 { parts.append("\(ticked) to add") }
        if duplicates > 0 { parts.append("\(duplicates) possible duplicates") }
        if needsAttention > 0 { parts.append("\(needsAttention) need a look") }
        if excluded > 0 { parts.append("\(excluded) left out") }
        return parts.joined(separator: " · ")
    }
}
