import Foundation

/// Which correction the user meant when they tapped "Correct balance" (§4.4).
///
/// Both paths must exist, reached from that single action asking which they mean.
public enum BalanceCorrection: String, CaseIterable, Identifiable, Sendable {
    /// Record a dated adjustment. For small drift and unlogged charges.
    ///
    /// Affects balances and Net Worth, and is excluded from spend and income totals —
    /// a correction is not spending.
    case adjustment
    /// Change the starting figure, recomputing that account's entire history.
    case openingBalance

    /// The case's identity, for `ForEach`.
    public var id: String { rawValue }
}
