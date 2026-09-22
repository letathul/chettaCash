import Foundation

/// Judges duplicate pairs by comparing their names, with no model involved (§9.7).
///
/// The counterpart to the on-device reader, and what actually makes the feature safe: it
/// runs everywhere — Simulator, older device, model declined — and it is deterministic, so
/// the riskiest decision in the import is covered by tests that need no simulator.
///
/// **It never answers ``DuplicateJudgement/differentTransactions``.** Two entries that
/// already agree on card, day and amount are not shown to be different purchases by their
/// names failing to look alike — plenty of real duplicates share no words at all
/// (`AMZN Mktp US*2K4TQ` against `Headphones`). Absence of evidence is reported as
/// ``DuplicateJudgement/unsure``, which asks the user rather than nudging them.
public struct HeuristicDuplicateAdjudicator: DuplicateAdjudicating {

    /// How much of two names must be shared before they are called the same shop.
    ///
    /// A half. Lower starts matching `Blue Bottle` to `Blue Apron`.
    public static let overlapThreshold = 0.5

    /// Creates the adjudicator.
    public init() {}

    /// Judges each conflict by name similarity.
    /// - Parameters:
    ///   - conflicts: The pairs to judge.
    ///   - context: What the reader needs beyond the pairs. Unused here.
    /// - Returns: One verdict per conflict.
    public func adjudicate(
        _ conflicts: [DuplicateConflict],
        context: DuplicateAdjudicationContext
    ) async -> [DuplicateVerdict] {
        conflicts.map { Self.verdict(for: $0) }
    }

    /// The verdict for one conflict.
    /// - Parameter conflict: The pair to judge.
    /// - Returns: The verdict.
    static func verdict(for conflict: DuplicateConflict) -> DuplicateVerdict {
        let existing = conflict.existing.merchant
        let incoming = conflict.incoming.merchant
        let overlap = MerchantSimilarity.overlap(existing, incoming)

        if overlap >= overlapThreshold || MerchantSimilarity.sharesLeadingToken(existing, incoming) {
            return DuplicateVerdict(
                id: conflict.id,
                judgement: .sameTransaction,
                rationale: "“\(existing)” and “\(incoming)” look like the same shop.",
                source: .textHeuristics
            )
        }
        return DuplicateVerdict(
            id: conflict.id,
            judgement: .unsure,
            rationale: conflict.reason.explanation,
            source: .textHeuristics
        )
    }
}
