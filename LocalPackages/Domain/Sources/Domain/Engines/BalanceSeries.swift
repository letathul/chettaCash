import Foundation

/// One day's closing balance in a daily balance series (§7.1).
public struct BalancePoint: Identifiable, Equatable, Sendable {
    /// The first instant of the day this point covers.
    public let dayStart: Date
    /// The account's balance at the end of that day, in cents.
    public let cents: Int

    /// The point's identity, for `ForEach`.
    public var id: Date { dayStart }

    /// Creates a point.
    /// - Parameters:
    ///   - dayStart: The first instant of the day.
    ///   - cents: The balance at the end of that day.
    public init(dayStart: Date, cents: Int) {
        self.dayStart = dayStart
        self.cents = cents
    }
}

/// A daily balance series and everything a sparkline needs to draw it (§7.1).
///
/// Unlike ``TrendSeries``, which charts a *flow* anchored at zero, this charts a
/// *stock*. A card sitting between −$800 and −$900 scaled against a zero-anchored
/// peak draws a flat line pinned to the bottom of the chart, and the $100 of movement
/// — the entire point of the sparkline — disappears. So the scale here is the band
/// between ``minCents`` and ``maxCents``, not a peak measured from zero.
///
/// ``normalized`` is derived once in `init` rather than in a view body: a SwiftUI
/// `body` must do no arithmetic over a collection it renders (§8.4).
public struct BalanceSeries: Identifiable, Equatable, Sendable {

    /// The identity the "All accounts" page uses, since it belongs to no one account.
    private static let aggregateID =
        UUID(uuidString: "00000000-0000-0000-0000-0000000000A1") ?? UUID()

    /// The account this series belongs to, or `nil` when it aggregates several.
    public let accountID: UUID?
    /// The daily closing balances, oldest first.
    ///
    /// Empty when the account did not yet exist anywhere in the window.
    public let points: [BalancePoint]
    /// The lowest balance in the window, in cents. Zero when there are no points.
    public let minCents: Int
    /// The highest balance in the window, in cents. Zero when there are no points.
    public let maxCents: Int
    /// Each point's position in the band, `0` at ``minCents`` and `1` at ``maxCents``.
    ///
    /// A flat series has no band to divide by, so every entry is `0.5` and the view
    /// draws a centred line. The division by zero is prevented here, not in the view.
    /// These are unit ratios, not money — money in this type stays `Int` cents.
    public let normalized: [Double]

    /// The band the series spans, in cents. Never negative.
    public var spanCents: Int { maxCents - minCents }
    /// Whether every point holds the same balance.
    public var isFlat: Bool { spanCents == 0 }
    /// The most recent day's balance, or zero when there are no points.
    public var currentCents: Int { points.last?.cents ?? 0 }
    /// The oldest day's balance, or zero when there are no points.
    public var firstCents: Int { points.first?.cents ?? 0 }

    /// The change across the whole window.
    ///
    /// - Note: This is last-versus-**first**, unlike ``TrendSeries/deltaCents``, which
    ///   is last-versus-previous. A sparkline answers "where am I versus a month ago",
    ///   not "versus yesterday".
    public var deltaCents: Int { currentCents - firstCents }

    /// The series' identity, for a carousel's `ForEach`.
    public var id: UUID { accountID ?? Self.aggregateID }

    /// Creates a series, deriving its scale from the points.
    /// - Parameters:
    ///   - accountID: The account the series describes, or `nil` when it aggregates.
    ///   - points: The daily closing balances, oldest first.
    public init(accountID: UUID?, points: [BalancePoint]) {
        self.accountID = accountID
        self.points = points
        let values = points.map(\.cents)
        let lowest = values.min() ?? 0
        let highest = values.max() ?? 0
        self.minCents = lowest
        self.maxCents = highest
        let span = highest - lowest
        self.normalized = span == 0
            ? values.map { _ in 0.5 }
            : values.map { Double($0 - lowest) / Double(span) }
    }
}
