import Foundation
import Testing
@testable import Domain

/// The carousel's "All accounts" page, which must agree with every other net-worth
/// figure on the same screen (§7.1).
@Suite("Daily net worth series")
struct BalanceSeriesAggregateTests {

    private typealias Given = SeriesFixtures

    @Test("The aggregate series matches the net worth TrendsEngine derives for the same moment")
    func aggregateAgreesWithTrendsEngine() {
        let asOf = Given.date(2026, 9, 22)
        let chequing = Given.account(openingCents: 120_000)
        let visa = Given.account(kind: .card, openingCents: -40_000)
        let transactions = [
            Given.entry(.expense, 6_250, on: chequing, when: Given.date(2026, 9, 12)),
            Given.entry(.expense, 5_410, on: visa, when: Given.date(2026, 9, 18)),
            Given.entry(.income, 210_000, on: chequing, when: Given.date(2026, 9, 20))
        ]

        let series = BalanceSeriesEngine.dailyNetWorth(
            accounts: [chequing, visa], transactions: transactions,
            asOf: asOf, calendar: Given.utc
        )
        let derived = TrendsEngine.netWorthCents(
            accounts: [chequing, visa], transactions: transactions, asOf: asOf
        )

        #expect(series.currentCents == derived)
        #expect(series.accountID == nil)
    }

    @Test("An account that opens mid-window lifts the aggregate only from its opening day")
    func mid_windowOpeningEntersAsAStep() {
        let chequing = Given.account(openingCents: 10_000)
        let savings = Given.account(openingCents: 500_000, opened: Given.date(2026, 9, 15))

        let series = BalanceSeriesEngine.dailyNetWorth(
            accounts: [chequing, savings], transactions: [],
            asOf: Given.date(2026, 9, 22), calendar: Given.utc
        )
        let byDay = Dictionary(
            series.points.map { ($0.dayStart, $0.cents) }, uniquingKeysWith: { first, _ in first }
        )

        #expect(byDay[Given.date(2026, 9, 14, hour: 0)] == 10_000)
        #expect(byDay[Given.date(2026, 9, 15, hour: 0)] == 510_000)
    }

    @Test("A transaction dated before its account opened does not lift the aggregate before the opening day")
    func preOpeningTransactionIsClampedToTheOpeningDay() {
        let opened = Given.date(2026, 9, 15)
        let savings = Given.account(openingCents: 0, opened: opened)
        let stray = Given.entry(.income, 90_000, on: savings, when: Given.date(2026, 9, 5))

        let series = BalanceSeriesEngine.dailyNetWorth(
            accounts: [savings], transactions: [stray],
            asOf: Given.date(2026, 9, 22), calendar: Given.utc
        )
        let byDay = Dictionary(
            series.points.map { ($0.dayStart, $0.cents) }, uniquingKeysWith: { first, _ in first }
        )

        #expect(byDay[Given.date(2026, 9, 10, hour: 0)] == 0)
        #expect(byDay[Given.date(2026, 9, 15, hour: 0)] == 90_000)
        let derived = TrendsEngine.netWorthCents(
            accounts: [savings], transactions: [stray], asOf: Given.date(2026, 9, 10)
        )
        #expect(byDay[Given.date(2026, 9, 10, hour: 0)] == derived)
    }

    @Test("A card's debt pulls the aggregate down on the day it is charged")
    func cardDebtPullsTheAggregateDown() {
        let chequing = Given.account(openingCents: 100_000)
        let visa = Given.account(kind: .card, openingCents: 0)
        let charge = Given.entry(.expense, 25_000, on: visa, when: Given.date(2026, 9, 19))

        let series = BalanceSeriesEngine.dailyNetWorth(
            accounts: [chequing, visa], transactions: [charge],
            asOf: Given.date(2026, 9, 22), calendar: Given.utc
        )
        let byDay = Dictionary(
            series.points.map { ($0.dayStart, $0.cents) }, uniquingKeysWith: { first, _ in first }
        )

        #expect(byDay[Given.date(2026, 9, 18, hour: 0)] == 100_000)
        #expect(byDay[Given.date(2026, 9, 19, hour: 0)] == 75_000)
    }

    @Test("An aggregate over no accounts is a flat line at zero")
    func emptyAccountSet() {
        let series = BalanceSeriesEngine.dailyNetWorth(
            accounts: [], transactions: [],
            asOf: Given.date(2026, 9, 22), calendar: Given.utc
        )

        #expect(series.points.count == 30)
        #expect(series.isFlat)
        #expect(series.currentCents == 0)
    }
}
