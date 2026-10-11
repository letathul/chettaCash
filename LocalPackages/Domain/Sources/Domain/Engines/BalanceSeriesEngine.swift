import Foundation

/// Builds the Dashboard hero card's daily balance sparklines (§7.1).
///
/// One pass over the transactions and one sort, rather than the
/// O(days × accounts × transactions) that calling
/// ``BalanceEngine/currentBalanceCents(account:transactions:asOf:)`` once per day per
/// account would cost — the same rescanning this codebase already avoids by storing
/// the Dashboard's derived figures rather than computing them per body evaluation.
///
/// - Important: Transfer legs and adjustments **are** included here. They move a
///   *balance*, even though ``TotalsEngine`` correctly excludes them from every
///   *total*. This is the one place in the codebase where that exclusion does not
///   apply.
public enum BalanceSeriesEngine {

    /// How many days the hero sparkline covers.
    ///
    /// A hero card is roughly 120–160pt wide, so 90 points would fall under 2pt per
    /// day and read as noise. Thirty days is one pay cycle, and matches the "this
    /// month" frame the rest of the Dashboard already uses.
    public static let dayCount = 30

    /// A dated change to a running balance.
    private struct BalanceEvent {
        /// When the change takes effect.
        let date: Date
        /// The signed change in cents.
        let cents: Int
    }

    /// The daily balance series for one account.
    ///
    /// The series begins on the account's opening day when that falls inside the
    /// window: leading days are omitted rather than back-filled, since zeroes would
    /// imply a $0 balance and the opening figure would imply the account already
    /// existed. Both would be untrue.
    ///
    /// - Parameters:
    ///   - account: The account to chart.
    ///   - transactions: Every transaction; other accounts' entries are ignored.
    ///   - days: How many days the window covers.
    ///   - asOf: The moment the window ends at.
    ///   - calendar: The calendar deciding day boundaries.
    /// - Returns: The series, oldest day first, empty when the account did not exist
    ///   at any point in the window.
    public static func dailyBalances(
        account: Account,
        transactions: [Transaction],
        days: Int = dayCount,
        asOf: Date = .now,
        calendar: Calendar = .current
    ) -> BalanceSeries {
        let starts = dayStarts(days: days, asOf: asOf, calendar: calendar)
        let ends = starts.map { cutoff(for: $0, asOf: asOf, calendar: calendar) }
        guard let first = ends.firstIndex(where: { $0 >= account.openingBalanceDate }) else {
            return BalanceSeries(accountID: account.id, points: [])
        }
        let events = transactions
            .filter { $0.accountID == account.id && BalanceEngine.isPosted($0, asOf: asOf) }
            .map { BalanceEvent(date: $0.date, cents: BalanceEngine.signedAmountCents(for: $0)) }
            .sorted { $0.date < $1.date }
        return BalanceSeries(
            accountID: account.id,
            points: accumulate(
                events: events,
                dayStarts: starts[first...],
                cutoffs: ends[first...],
                startingCents: account.openingBalanceCents
            )
        )
    }

    /// One daily balance series per account, in the order the accounts were given.
    ///
    /// - Parameters:
    ///   - accounts: The accounts to chart. Closed accounts are not filtered out —
    ///     the caller decides which accounts the carousel shows.
    ///   - transactions: Every transaction.
    ///   - days: How many days the window covers.
    ///   - asOf: The moment the window ends at.
    ///   - calendar: The calendar deciding day boundaries.
    /// - Returns: One series per account.
    public static func dailyBalances(
        accounts: [Account],
        transactions: [Transaction],
        days: Int = dayCount,
        asOf: Date = .now,
        calendar: Calendar = .current
    ) -> [BalanceSeries] {
        accounts.map {
            dailyBalances(
                account: $0, transactions: transactions,
                days: days, asOf: asOf, calendar: calendar
            )
        }
    }

    /// The daily net worth of a set of accounts, for the carousel's "All accounts" page.
    ///
    /// Agrees with ``TrendsEngine/netWorthCents(accounts:transactions:asOf:)`` at every
    /// point: an account contributes nothing before its `openingBalanceDate`, and
    /// neither does a transaction of its that predates it. Without that second clamp
    /// the two figures would disagree on the same screen.
    ///
    /// - Parameters:
    ///   - accounts: The accounts to total.
    ///   - transactions: Every transaction.
    ///   - days: How many days the window covers.
    ///   - asOf: The moment the window ends at.
    ///   - calendar: The calendar deciding day boundaries.
    /// - Returns: The aggregate series, oldest day first.
    public static func dailyNetWorth(
        accounts: [Account],
        transactions: [Transaction],
        days: Int = dayCount,
        asOf: Date = .now,
        calendar: Calendar = .current
    ) -> BalanceSeries {
        let starts = dayStarts(days: days, asOf: asOf, calendar: calendar)
        let ends = starts.map { cutoff(for: $0, asOf: asOf, calendar: calendar) }
        let openedByID = Dictionary(
            accounts.map { ($0.id, $0.openingBalanceDate) }, uniquingKeysWith: { first, _ in first }
        )
        var events = accounts.map {
            BalanceEvent(date: $0.openingBalanceDate, cents: $0.openingBalanceCents)
        }
        for transaction in transactions {
            guard let accountID = transaction.accountID,
                  let opened = openedByID[accountID],
                  BalanceEngine.isPosted(transaction, asOf: asOf) else { continue }
            events.append(
                BalanceEvent(
                    date: max(transaction.date, opened),
                    cents: BalanceEngine.signedAmountCents(for: transaction)
                )
            )
        }
        events.sort { $0.date < $1.date }
        return BalanceSeries(
            accountID: nil,
            points: accumulate(
                events: events, dayStarts: starts[...], cutoffs: ends[...], startingCents: 0
            )
        )
    }

    /// Walks ascending events alongside ascending day cutoffs, emitting one point per day.
    ///
    /// Both sequences ascend, so the event pointer advances a total of *k* times across
    /// every day rather than *k* times per day.
    ///
    /// - Parameters:
    ///   - events: The changes, sorted ascending by date.
    ///   - dayStarts: The first instant of each day, oldest first.
    ///   - cutoffs: The moment each day's balance is read at, aligned with `dayStarts`.
    ///   - startingCents: The balance before the first event.
    /// - Returns: One point per day.
    private static func accumulate(
        events: [BalanceEvent],
        dayStarts: ArraySlice<Date>,
        cutoffs: ArraySlice<Date>,
        startingCents: Int
    ) -> [BalancePoint] {
        var running = startingCents
        var index = events.startIndex
        var points: [BalancePoint] = []
        points.reserveCapacity(dayStarts.count)
        for (dayStart, cutoff) in zip(dayStarts, cutoffs) {
            while index < events.endIndex, events[index].date <= cutoff {
                running += events[index].cents
                index += 1
            }
            points.append(BalancePoint(dayStart: dayStart, cents: running))
        }
        return points
    }

    /// The first instant of each day in the trailing window, oldest first.
    ///
    /// Built by calendar day arithmetic rather than by subtracting 86,400 seconds, so
    /// a day that gains or loses an hour to daylight saving still yields one point.
    ///
    /// - Parameters:
    ///   - days: How many days to cover. Zero or fewer yields no days.
    ///   - asOf: The moment the window ends at.
    ///   - calendar: The calendar deciding day boundaries.
    /// - Returns: The day starts.
    private static func dayStarts(days: Int, asOf: Date, calendar: Calendar) -> [Date] {
        guard days > 0 else { return [] }
        let todayStart = calendar.startOfDay(for: asOf)
        return (0..<days).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: todayStart)
        }
    }

    /// The moment one day's balance is read at.
    ///
    /// Clamped to `asOf` so a transaction dated 23:00 today does not move today's
    /// point when the series is built at 14:00 — the same guard ``TrendsEngine``
    /// applies against entries that have not posted yet (§4.2).
    ///
    /// - Parameters:
    ///   - dayStart: The first instant of the day.
    ///   - asOf: The moment the window ends at.
    ///   - calendar: The calendar deciding day boundaries.
    /// - Returns: The end of that day, or `asOf` when that is earlier.
    private static func cutoff(for dayStart: Date, asOf: Date, calendar: Calendar) -> Date {
        min(TodayBuilder.dayRange(containing: dayStart, calendar: calendar).upperBound, asOf)
    }
}
