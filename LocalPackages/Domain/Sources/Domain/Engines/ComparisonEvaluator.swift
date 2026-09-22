import Foundation

/// Which side of a comparison is being referred to.
public enum ComparisonSide: String, Sendable {
    /// The first item.
    case itemA
    /// The second item.
    case itemB
}

/// The outcome of comparing two packages (§7.5).
public enum ComparisonOutcome: Equatable, Sendable {
    /// One or both sides are missing or invalid, so there is nothing to report.
    case noResult
    /// Both sides work out to the same per-unit price.
    case tie(perUnitA: Double, perUnitB: Double)
    /// One side is cheaper per unit.
    case cheaper(side: ComparisonSide, perUnitA: Double, perUnitB: Double)

    /// The winning side, if there is one.
    public var winner: ComparisonSide? {
        guard case .cheaper(let side, _, _) = self else { return nil }
        return side
    }
}

/// Decides which of two packages is better value (§7.5).
public enum ComparisonEvaluator {

    /// How close two per-unit prices must be to count as the same.
    ///
    /// Below this the difference is smaller than the figures are displayed to, so
    /// claiming a winner would be noise.
    public static let tieThreshold = 0.0005

    /// Evaluates a saved comparison.
    /// - Parameter comparison: The comparison to evaluate.
    /// - Returns: The outcome, or ``ComparisonOutcome/noResult`` when either side is
    ///   incomplete or invalid.
    public static func evaluate(_ comparison: Comparison) -> ComparisonOutcome {
        let perUnitA = UnitPrice.normalizedPrice(
            priceCents: comparison.itemAPriceCents,
            quantity: comparison.itemAQuantity,
            unit: comparison.itemAUnit.flatMap(PackageUnit.init(rawValue:))
        )
        let perUnitB = UnitPrice.normalizedPrice(
            priceCents: comparison.itemBPriceCents,
            quantity: comparison.itemBQuantity,
            unit: comparison.itemBUnit.flatMap(PackageUnit.init(rawValue:))
        )
        guard let perUnitA, let perUnitB else { return .noResult }

        if abs(perUnitA - perUnitB) < tieThreshold {
            return .tie(perUnitA: perUnitA, perUnitB: perUnitB)
        }
        return .cheaper(
            side: perUnitA < perUnitB ? .itemA : .itemB,
            perUnitA: perUnitA,
            perUnitB: perUnitB
        )
    }

    /// Whether a comparison may be removed from the history strip.
    ///
    /// **A comparison can never be deleted if it is the last one remaining.** Guarded
    /// here rather than only in the UI, so no caller can get around it (§7.5).
    ///
    /// - Parameters:
    ///   - id: The comparison being removed.
    ///   - comparisons: Every saved comparison.
    /// - Returns: `true` when removal is allowed.
    public static func canRemove(id: UUID, from comparisons: [Comparison]) -> Bool {
        comparisons.count > 1 && comparisons.contains { $0.id == id }
    }
}
