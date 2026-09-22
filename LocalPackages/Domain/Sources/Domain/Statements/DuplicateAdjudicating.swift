import Foundation

/// What a reader concluded about two entries that may be one purchase.
public enum DuplicateJudgement: String, Sendable, Equatable, CaseIterable {
    /// The two describe the same real purchase.
    case sameTransaction
    /// The two are genuinely different purchases that happen to match on day and amount.
    case differentTransactions
    /// Not enough to tell either way.
    case unsure
}

/// One reader's opinion about one conflict.
public struct DuplicateVerdict: Identifiable, Hashable, Sendable {
    /// The conflict this answers, sharing its identifier.
    public let id: UUID
    /// What was concluded.
    public var judgement: DuplicateJudgement
    /// One sentence explaining it, shown under the comparison.
    public var rationale: String
    /// Which reader produced it, so a test can assert the fallback really ran.
    public var source: ReceiptScanSource

    /// Whether this verdict should pre-tick the incoming row for removal.
    ///
    /// Only an outright `sameTransaction` does. An `unsure` verdict leaves both rows
    /// untouched, because a pre-ticked guess is one careless tap away from deleting a real
    /// purchase.
    public var suggestsRemovingIncoming: Bool { judgement == .sameTransaction }

    /// Creates a verdict.
    /// - Parameters:
    ///   - id: The conflict this answers.
    ///   - judgement: What was concluded.
    ///   - rationale: One sentence explaining it.
    ///   - source: Which reader produced it.
    public init(
        id: UUID,
        judgement: DuplicateJudgement,
        rationale: String,
        source: ReceiptScanSource
    ) {
        self.id = id
        self.judgement = judgement
        self.rationale = rationale
        self.source = source
    }
}

/// What an adjudicator needs to know beyond the pair itself.
public struct DuplicateAdjudicationContext: Sendable {
    /// The moment the import is happening.
    public var now: Date
    /// The card's display name, so an explanation can name it.
    public var accountName: String
    /// The calendar deciding which day a date falls on.
    public var calendar: Calendar

    /// Creates a context.
    /// - Parameters:
    ///   - now: The moment the import is happening.
    ///   - accountName: The card's display name.
    ///   - calendar: The calendar deciding day boundaries.
    public init(now: Date = .now, accountName: String = "", calendar: Calendar = .current) {
        self.now = now
        self.accountName = accountName
        self.calendar = calendar
    }
}

/// Judges whether two descriptions of one day's charge are the same purchase (§9.7).
///
/// Declared in Domain, like ``ReceiptExtracting``, so the framework-backed implementation
/// lives in Features and a test can substitute a fake without a simulator.
///
/// **An adjudicator never decides anything on its own.** Its verdict pre-selects the
/// wizard's default and writes the line the user reads; the user always taps. A model
/// silently discarding a financial row is not recoverable, which is the same rule
/// ``AccountMatcher`` follows when it refuses to guess an account.
public protocol DuplicateAdjudicating: Sendable {
    /// Judges each conflict.
    ///
    /// Never throws: a reader that cannot help returns fewer verdicts than it was given,
    /// or none at all, and the caller falls back to another.
    ///
    /// - Parameters:
    ///   - conflicts: The pairs to judge.
    ///   - context: What the reader needs beyond the pairs.
    /// - Returns: The verdicts, which may not cover every conflict.
    func adjudicate(
        _ conflicts: [DuplicateConflict],
        context: DuplicateAdjudicationContext
    ) async -> [DuplicateVerdict]
}
