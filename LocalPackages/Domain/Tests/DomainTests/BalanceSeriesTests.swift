import Foundation
import Testing
@testable import Domain

/// The hero card's daily balance sparkline (§7.1).
@Suite("Daily balance series")
struct BalanceSeriesTests {

    /// A UTC calendar, so results never depend on the runner's locale.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// Builds a UTC date.
    /// - Parameters:
    ///   - year: The year.
    ///   - month: The month.
    ///   - day: The day.
    ///   - hour: The hour, defaulting to midday.
    /// - Returns: That instant.
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .now
    }

    /// Builds an account opened well before any test window.
    /// - Parameters:
    ///   - kind: Spending account or card.
    ///   - openingCents: The opening balance.
    ///   - opened: The opening-balance date.
    /// - Returns: The account.
    private func account(
        kind: AccountKind = .account,
        openingCents: Int = 0,
        opened: Date? = nil
    ) -> Account {
        Account(
            kind: kind,
            openingBalanceCents: openingCents,
            openingBalanceDate: opened ?? date(2026, 1, 1)
        )
    }

    /// Builds a transaction.
    /// - Parameters:
    ///   - type: The type.
    ///   - cents: The positive magnitude.
    ///   - account: The owning account.
    ///   - when: The date.
    /// - Returns: The transaction.
    private func entry(
        _ type: TransactionType, _ cents: Int, on account: Account, when: Date
    ) -> Transaction {
        Transaction(amountCents: cents, type: type, accountID: account.id, date: when)
    }

    @Test("The series covers thirty days, oldest first, ending on the reference day")
    func seriesShape() {
        let series = BalanceSeriesEngine.dailyBalances(
            account: account(), transactions: [], asOf: date(2026, 9, 22), calendar: calendar
        )

        #expect(series.points.count == 30)
        let sorted = series.points.map(\.dayStart) == series.points.map(\.dayStart).sorted()
        #expect(sorted)
        #expect(series.points.last?.dayStart == date(2026, 9, 22, hour: 0))
        #expect(series.points.first?.dayStart == date(2026, 8, 24, hour: 0))
    }

    @Test("An account with no transactions draws a flat line at its opening balance")
    func flatAtOpeningBalance() {
        let series = BalanceSeriesEngine.dailyBalances(
            account: account(openingCents: 50_000),
            transactions: [],
            asOf: date(2026, 9, 22),
            calendar: calendar
        )

        let allAtOpening = series.points.allSatisfy { $0.cents == 50_000 }
        #expect(allAtOpening)
        #expect(series.isFlat)
        #expect(series.deltaCents == 0)
    }

    @Test("Each point is the account's balance at the end of that day")
    func pointsAreEndOfDayBalances() {
        let chequing = account(openingCents: 100_000)
        let transactions = [
            entry(.expense, 2_500, on: chequing, when: date(2026, 9, 20)),
            entry(.income, 10_000, on: chequing, when: date(2026, 9, 21))
        ]

        let series = BalanceSeriesEngine.dailyBalances(
            account: chequing, transactions: transactions,
            asOf: date(2026, 9, 22), calendar: calendar
        )
        let byDay = Dictionary(
            series.points.map { ($0.dayStart, $0.cents) }, uniquingKeysWith: { first, _ in first }
        )

        #expect(byDay[date(2026, 9, 19, hour: 0)] == 100_000)
        #expect(byDay[date(2026, 9, 20, hour: 0)] == 97_500)
        #expect(byDay[date(2026, 9, 21, hour: 0)] == 107_500)
    }

    @Test("The last point equals the balance BalanceEngine derives for the same moment")
    func lastPointAgreesWithBalanceEngine() {
        let chequing = account(openingCents: 42_000)
        let asOf = date(2026, 9, 22)
        let transactions = [
            entry(.expense, 1_234, on: chequing, when: date(2026, 9, 3)),
            entry(.income, 90_000, on: chequing, when: date(2026, 9, 15)),
            entry(.transferOut, 5_000, on: chequing, when: date(2026, 9, 18))
        ]

        let series = BalanceSeriesEngine.dailyBalances(
            account: chequing, transactions: transactions, asOf: asOf, calendar: calendar
        )
        let derived = BalanceEngine.currentBalanceCents(
            account: chequing, transactions: transactions, asOf: asOf
        )

        #expect(series.currentCents == derived)
    }

    @Test("A transaction dated later today does not move today's point")
    func laterTodayStaysInert() {
        let chequing = account(openingCents: 10_000)
        let later = entry(.expense, 9_000, on: chequing, when: date(2026, 9, 22, hour: 23))

        let series = BalanceSeriesEngine.dailyBalances(
            account: chequing, transactions: [later],
            asOf: date(2026, 9, 22, hour: 14), calendar: calendar
        )

        #expect(series.currentCents == 10_000)
    }

    @Test("A transaction dated inside the window but in the future never appears")
    func futureDatedNeverAppears() {
        let chequing = account(openingCents: 10_000)
        let future = entry(.expense, 9_000, on: chequing, when: date(2026, 9, 30))

        let series = BalanceSeriesEngine.dailyBalances(
            account: chequing, transactions: [future],
            asOf: date(2026, 9, 22), calendar: calendar
        )

        let untouched = series.points.allSatisfy { $0.cents == 10_000 }
        #expect(untouched)
    }

    @Test("Another account's transactions never reach this account's series")
    func otherAccountsAreIgnored() {
        let chequing = account(openingCents: 10_000)
        let savings = account(openingCents: 0)
        let theirs = entry(.expense, 7_000, on: savings, when: date(2026, 9, 20))

        let series = BalanceSeriesEngine.dailyBalances(
            account: chequing, transactions: [theirs],
            asOf: date(2026, 9, 22), calendar: calendar
        )

        #expect(series.currentCents == 10_000)
    }

    @Test("Transfer legs and adjustments move the balance even though they never reach a spend total")
    func transfersAndAdjustmentsMoveTheBalance() {
        let chequing = account(openingCents: 100_000)
        let transactions = [
            entry(.transferOut, 20_000, on: chequing, when: date(2026, 9, 18)),
            Transaction(
                amountCents: 0, type: .adjustment, signedOverrideCents: -3_000,
                accountID: chequing.id, date: date(2026, 9, 19)
            )
        ]

        let series = BalanceSeriesEngine.dailyBalances(
            account: chequing, transactions: transactions,
            asOf: date(2026, 9, 22), calendar: calendar
        )
        let spend = TotalsEngine.spendTotalCents(
            transactions: transactions, asOf: date(2026, 9, 22)
        )

        #expect(series.currentCents == 77_000)
        #expect(spend == 0)
    }

    @Test("A card owing money draws a series that is negative at every point")
    func cardSeriesStaysNegative() {
        let visa = account(kind: .card, openingCents: -80_000)
        let charge = entry(.expense, 10_000, on: visa, when: date(2026, 9, 20))

        let series = BalanceSeriesEngine.dailyBalances(
            account: visa, transactions: [charge],
            asOf: date(2026, 9, 22), calendar: calendar
        )

        let allNegative = series.points.allSatisfy { $0.cents < 0 }
        #expect(allNegative)
        #expect(series.currentCents == -90_000)
        #expect(series.spanCents == 10_000)
    }

    @Test("A day that loses an hour to daylight saving still yields exactly one point")
    func daylightSavingYieldsOnePointPerDay() {
        var zoned = Calendar(identifier: .gregorian)
        zoned.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        let march = zoned.date(from: DateComponents(year: 2026, month: 3, day: 12, hour: 12)) ?? .now

        let series = BalanceSeriesEngine.dailyBalances(
            account: account(opened: date(2026, 1, 1)), transactions: [],
            days: 7, asOf: march, calendar: zoned
        )
        let distinctDays = Set(series.points.map(\.dayStart)).count

        #expect(series.points.count == 7)
        #expect(distinctDays == 7)
    }
}
