import Foundation

/// One month's value in a trend series.
public struct TrendPoint: Identifiable, Equatable, Sendable {
    /// The first instant of the month this point covers.
    public let monthStart: Date
    /// The value in cents.
    public let cents: Int

    /// The point's identity, for `ForEach`.
    public var id: Date { monthStart }

    /// Creates a point.
    /// - Parameters:
    ///   - monthStart: The first instant of the month.
    ///   - cents: The value in cents.
    public init(monthStart: Date, cents: Int) {
        self.monthStart = monthStart
        self.cents = cents
    }
}

/// A trend series and its month-over-month change.
public struct TrendSeries: Equatable, Sendable {
    /// The monthly values, oldest first.
    public let points: [TrendPoint]

    /// The most recent month's value.
    public var currentCents: Int { points.last?.cents ?? 0 }

    /// The change against the prior month.
    public var deltaCents: Int {
        guard points.count >= 2 else { return 0 }
        return points[points.count - 1].cents - points[points.count - 2].cents
    }

    /// The largest value in the series, used to scale bars.
    public var peakCents: Int { points.map(\.cents).map(abs).max() ?? 0 }

    /// Creates a series.
    /// - Parameter points: The monthly values, oldest first.
    public init(points: [TrendPoint]) {
        self.points = points
    }
}

/// Builds the Dashboard's six-month trend charts from real history (§7.1).
///
/// Nothing here is hardcoded or sampled: monthly spend is the sum of that month's
/// posted expenses excluding transfers and adjustments, and monthly net worth is the
/// balance of every account that existed at that month's end.
public enum TrendsEngine {

    /// How many months the Dashboard charts cover.
    public static let monthCount = 6

    /// Monthly spend over the trailing months.
    ///
    /// - Parameters:
    ///   - transactions: Every transaction.
    ///   - months: How many months to cover.
    ///   - reference: The month the series ends in.
    ///   - calendar: The calendar deciding month boundaries.
    /// - Returns: The series, oldest month first.
    public static func monthlySpend(
        transactions: [Transaction],
        months: Int = monthCount,
        reference: Date = .now,
        calendar: Calendar = .current
    ) -> TrendSeries {
        let points = monthStarts(months: months, reference: reference, calendar: calendar)
            .map { start -> TrendPoint in
                guard let range = monthRange(containing: start, calendar: calendar) else {
                    return TrendPoint(monthStart: start, cents: 0)
                }
                // Clamp to the reference moment: evaluating the current month as of
                // its end would count transactions dated later this month, which are
                // still unposted and must stay inert (§4.2).
                return TrendPoint(
                    monthStart: start,
                    cents: TotalsEngine.spendTotalCents(
                        transactions: transactions,
                        in: range,
                        asOf: min(range.upperBound, reference)
                    )
                )
            }
        return TrendSeries(points: points)
    }

    /// Monthly net worth at each month's end.
    ///
    /// An account is counted only from its opening-balance date onward, so months
    /// before it existed are not inflated by its opening figure. Closed accounts are
    /// included: their derived balance is zero after closing anyway, and excluding
    /// them would erase the money they held beforehand.
    ///
    /// - Parameters:
    ///   - accounts: Every account, closed ones included.
    ///   - transactions: Every transaction.
    ///   - months: How many months to cover.
    ///   - reference: The month the series ends in.
    ///   - calendar: The calendar deciding month boundaries.
    /// - Returns: The series, oldest month first.
    public static func monthlyNetWorth(
        accounts: [Account],
        transactions: [Transaction],
        months: Int = monthCount,
        reference: Date = .now,
        calendar: Calendar = .current
    ) -> TrendSeries {
        let points = monthStarts(months: months, reference: reference, calendar: calendar)
            .map { start -> TrendPoint in
                guard let range = monthRange(containing: start, calendar: calendar) else {
                    return TrendPoint(monthStart: start, cents: 0)
                }
                let asOf = min(range.upperBound, reference)
                return TrendPoint(
                    monthStart: start,
                    cents: netWorthCents(
                        accounts: accounts, transactions: transactions, asOf: asOf
                    )
                )
            }
        return TrendSeries(points: points)
    }

    /// Net worth at a past moment, counting only accounts that existed by then.
    /// - Parameters:
    ///   - accounts: Every account, closed ones included.
    ///   - transactions: Every transaction.
    ///   - asOf: The moment to evaluate at.
    /// - Returns: Net worth in cents.
    public static func netWorthCents(
        accounts: [Account],
        transactions: [Transaction],
        asOf: Date
    ) -> Int {
        accounts
            .filter { $0.openingBalanceDate <= asOf }
            .reduce(0) { running, account in
                running + BalanceEngine.currentBalanceCents(
                    account: account, transactions: transactions, asOf: asOf
                )
            }
    }

    /// The first instant of each month in the trailing window, oldest first.
    /// - Parameters:
    ///   - months: How many months to cover.
    ///   - reference: The month the window ends in.
    ///   - calendar: The calendar deciding month boundaries.
    /// - Returns: The month starts.
    private static func monthStarts(
        months: Int,
        reference: Date,
        calendar: Calendar
    ) -> [Date] {
        guard months > 0, let current = monthRange(containing: reference, calendar: calendar) else {
            return []
        }
        return (0..<months).reversed().compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: current.lowerBound)
        }
    }

    /// The half-open range covering one calendar month.
    /// - Parameters:
    ///   - date: Any date inside the month.
    ///   - calendar: The calendar deciding month boundaries.
    /// - Returns: From the month's first instant to its last.
    private static func monthRange(
        containing date: Date,
        calendar: Calendar
    ) -> ClosedRange<Date>? {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return nil }
        let lastInstant = interval.end.addingTimeInterval(-0.001)
        guard interval.start <= lastInstant else { return nil }
        return interval.start...lastInstant
    }
}
