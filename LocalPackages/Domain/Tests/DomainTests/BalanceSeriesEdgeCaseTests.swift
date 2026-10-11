import Foundation
import Testing
@testable import Domain

/// The boundaries a sparkline has to survive without lying or trapping (§7.1).
@Suite("Daily balance series edges")
struct BalanceSeriesEdgeCaseTests {

    private typealias Given = SeriesFixtures

    @Test("An account opened mid-window starts the series on its opening day rather than back-filling zeroes")
    func openedMidWindow() {
        let opened = Given.date(2026, 9, 15)
        let account = Given.account(openingCents: 30_000, opened: opened)

        let series = BalanceSeriesEngine.dailyBalances(
            account: account, transactions: [],
            asOf: Given.date(2026, 9, 22), calendar: Given.utc
        )

        #expect(series.points.count == 8)
        #expect(series.points.first?.dayStart == Given.date(2026, 9, 15, hour: 0))
        #expect(series.firstCents == 30_000)
    }

    @Test("An account whose opening date has not arrived yields no points at all")
    func openingDateNotYetArrived() {
        let account = Given.account(openingCents: 30_000, opened: Given.date(2026, 12, 1))

        let series = BalanceSeriesEngine.dailyBalances(
            account: account, transactions: [],
            asOf: Given.date(2026, 9, 22), calendar: Given.utc
        )

        #expect(series.points.isEmpty)
        #expect(series.currentCents == 0)
        #expect(series.deltaCents == 0)
        #expect(series.normalized.isEmpty)
    }

    @Test("A flat series reports a zero span and hands the view a mid-band value for every point")
    func flatSeriesIsSafeToDivideBy() {
        let series = BalanceSeriesEngine.dailyBalances(
            account: Given.account(openingCents: 12_345), transactions: [],
            asOf: Given.date(2026, 9, 22), calendar: Given.utc
        )

        #expect(series.isFlat)
        #expect(series.spanCents == 0)
        let allCentred = series.normalized.allSatisfy { $0 == 0.5 }
        #expect(allCentred)
    }

    @Test("A single-point series reports no change and a single mid-band value")
    func singlePointSeries() {
        let series = BalanceSeriesEngine.dailyBalances(
            account: Given.account(openingCents: 900), transactions: [],
            days: 1, asOf: Given.date(2026, 9, 22), calendar: Given.utc
        )

        #expect(series.points.count == 1)
        #expect(series.deltaCents == 0)
        #expect(series.normalized == [0.5])
    }

    @Test("Asking for zero days returns an empty series rather than trapping")
    func zeroDays() {
        let series = BalanceSeriesEngine.dailyBalances(
            account: Given.account(openingCents: 900), transactions: [],
            days: 0, asOf: Given.date(2026, 9, 22), calendar: Given.utc
        )

        #expect(series.points.isEmpty)
        #expect(series.minCents == 0)
        #expect(series.maxCents == 0)
    }

    @Test("The minimum and maximum bound every point in the series")
    func minimumAndMaximumBoundEveryPoint() {
        let account = Given.account(openingCents: 50_000)
        let transactions = [
            Given.entry(.expense, 30_000, on: account, when: Given.date(2026, 9, 10)),
            Given.entry(.income, 70_000, on: account, when: Given.date(2026, 9, 18))
        ]

        let series = BalanceSeriesEngine.dailyBalances(
            account: account, transactions: transactions,
            asOf: Given.date(2026, 9, 22), calendar: Given.utc
        )
        let withinBand = series.points.allSatisfy {
            $0.cents >= series.minCents && $0.cents <= series.maxCents
        }

        #expect(withinBand)
        #expect(series.minCents == 20_000)
        #expect(series.maxCents == 90_000)
    }

    @Test("The normalised values run from zero at the low point to one at the high point")
    func normalisationSpansTheBand() {
        let account = Given.account(openingCents: 50_000)
        let transactions = [
            Given.entry(.expense, 30_000, on: account, when: Given.date(2026, 9, 10)),
            Given.entry(.income, 70_000, on: account, when: Given.date(2026, 9, 18))
        ]

        let series = BalanceSeriesEngine.dailyBalances(
            account: account, transactions: transactions,
            asOf: Given.date(2026, 9, 22), calendar: Given.utc
        )

        #expect(series.normalized.min() == 0)
        #expect(series.normalized.max() == 1)
        let inUnitRange = series.normalized.allSatisfy { $0 >= 0 && $0 <= 1 }
        #expect(inUnitRange)
    }

    @Test("The window delta measures the last point against the first, not against the point before it")
    func deltaIsMeasuredAcrossTheWholeWindow() {
        let account = Given.account(openingCents: 10_000)
        let transactions = [
            Given.entry(.income, 5_000, on: account, when: Given.date(2026, 9, 10)),
            Given.entry(.income, 1_000, on: account, when: Given.date(2026, 9, 22, hour: 1))
        ]

        let series = BalanceSeriesEngine.dailyBalances(
            account: account, transactions: transactions,
            asOf: Given.date(2026, 9, 22, hour: 12), calendar: Given.utc
        )

        #expect(series.firstCents == 10_000)
        #expect(series.currentCents == 16_000)
        #expect(series.deltaCents == 6_000)
    }

    @Test("One call returns one series per account, in the order the accounts were given")
    func oneSeriesPerAccountInOrder() {
        let first = Given.account(openingCents: 1_000)
        let second = Given.account(kind: .card, openingCents: -2_000)

        let series = BalanceSeriesEngine.dailyBalances(
            accounts: [first, second], transactions: [],
            asOf: Given.date(2026, 9, 22), calendar: Given.utc
        )

        #expect(series.count == 2)
        #expect(series.map(\.accountID) == [first.id, second.id])
        #expect(series[0].currentCents == 1_000)
        #expect(series[1].currentCents == -2_000)
    }
}
