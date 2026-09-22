import Foundation
import Testing
@testable import Domain

/// Phase 8 acceptance criteria for the Trends charts (§7.1).
@Suite("Trends")
struct TrendsEngineTests {

    /// A fixed UTC calendar, so results never depend on the runner's locale.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// Builds a UTC date at midday.
    /// - Parameters:
    ///   - year: The year.
    ///   - month: The month.
    ///   - day: The day.
    /// - Returns: That instant.
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .now
    }

    /// Builds an expense.
    /// - Parameters:
    ///   - cents: The amount.
    ///   - accountID: The owning account.
    ///   - when: The date.
    /// - Returns: The transaction.
    private func spend(_ cents: Int, accountID: UUID, when: Date) -> Transaction {
        Transaction(amountCents: cents, type: .expense, accountID: accountID, date: when)
    }

    @Test("The series covers six months, oldest first, ending in the reference month")
    func seriesShape() {
        let series = TrendsEngine.monthlySpend(
            transactions: [], reference: date(2026, 9, 12), calendar: calendar
        )

        #expect(series.points.count == 6)
        #expect(series.points.map(\.monthStart) == series.points.map(\.monthStart).sorted())
        let last = calendar.dateComponents([.year, .month], from: series.points[5].monthStart)
        #expect(last.month == 9)
        let first = calendar.dateComponents([.year, .month], from: series.points[0].monthStart)
        #expect(first.month == 4)
    }

    @Test("Monthly spend counts that month's posted expenses only")
    func monthlySpendBuckets() {
        let account = UUID()
        let transactions = [
            spend(1_000, accountID: account, when: date(2026, 8, 3)),
            spend(2_000, accountID: account, when: date(2026, 8, 20)),
            spend(5_000, accountID: account, when: date(2026, 9, 2))
        ]

        let series = TrendsEngine.monthlySpend(
            transactions: transactions, reference: date(2026, 9, 12), calendar: calendar
        )

        #expect(series.points[4].cents == 3_000, "August")
        #expect(series.points[5].cents == 5_000, "September")
        #expect(series.currentCents == 5_000)
    }

    @Test("Transfers and adjustments never reach the Spend chart")
    func spendExcludesTransfersAndAdjustments() throws {
        let source = UUID()
        let card = UUID()
        let legs = try TransferFactory.makeLegs(
            amountCents: 50_000, date: date(2026, 9, 3),
            sourceAccountID: source, destinationAccountID: card
        )
        let correction = AdjustmentFactory.make(
            accountID: source, signedCents: -2_000, date: date(2026, 9, 4)
        )
        let transactions = [
            spend(1_500, accountID: source, when: date(2026, 9, 2)),
            legs.out, legs.in, correction
        ]

        let series = TrendsEngine.monthlySpend(
            transactions: transactions, reference: date(2026, 9, 12), calendar: calendar
        )

        #expect(series.currentCents == 1_500)
    }

    @Test("A future-dated expense does not appear until its month arrives")
    func unpostedIsExcluded() {
        let account = UUID()
        let transactions = [spend(9_000, accountID: account, when: date(2026, 9, 30))]

        let series = TrendsEngine.monthlySpend(
            transactions: transactions, reference: date(2026, 9, 12), calendar: calendar
        )

        #expect(series.currentCents == 0)
    }

    @Test("The delta compares the last two months")
    func deltaComparesMonths() {
        let account = UUID()
        let transactions = [
            spend(2_000, accountID: account, when: date(2026, 8, 3)),
            spend(5_000, accountID: account, when: date(2026, 9, 2))
        ]

        let series = TrendsEngine.monthlySpend(
            transactions: transactions, reference: date(2026, 9, 12), calendar: calendar
        )

        #expect(series.deltaCents == 3_000)
    }

    @Test("Net worth includes cards and tracks month by month")
    func netWorthSeries() {
        let chequing = Account(
            name: "Chequing", openingBalanceCents: 100_000,
            openingBalanceDate: date(2026, 4, 1)
        )
        let card = Account(
            name: "Visa", kind: .card, openingBalanceCents: -20_000,
            openingBalanceDate: date(2026, 4, 1)
        )
        let transactions = [spend(10_000, accountID: chequing.id, when: date(2026, 8, 15))]

        let series = TrendsEngine.monthlyNetWorth(
            accounts: [chequing, card], transactions: transactions,
            reference: date(2026, 9, 12), calendar: calendar
        )

        #expect(series.points[3].cents == 80_000, "July: cards included")
        #expect(series.points[4].cents == 70_000, "August: after the expense")
        #expect(series.deltaCents == 0, "September added nothing")
    }

    @Test("An account is not counted in months before it existed")
    func accountsOnlyCountOnceOpened() {
        let old = Account(
            name: "Old", openingBalanceCents: 50_000, openingBalanceDate: date(2026, 4, 1)
        )
        let recent = Account(
            name: "Recent", openingBalanceCents: 30_000, openingBalanceDate: date(2026, 8, 10)
        )

        let series = TrendsEngine.monthlyNetWorth(
            accounts: [old, recent], transactions: [],
            reference: date(2026, 9, 12), calendar: calendar
        )

        #expect(series.points[3].cents == 50_000, "July: only the older account existed")
        #expect(series.points[4].cents == 80_000, "August: both")
    }

    @Test("A closed account still counts for the months it held money")
    func closedAccountsKeepTheirHistory() {
        var closed = Account(
            name: "Old", openingBalanceCents: 50_000, openingBalanceDate: date(2026, 4, 1)
        )
        closed.isClosed = true
        closed.closedDate = date(2026, 9, 1)

        let series = TrendsEngine.monthlyNetWorth(
            accounts: [closed], transactions: [],
            reference: date(2026, 9, 12), calendar: calendar
        )

        #expect(series.points[3].cents == 50_000)
    }

    @Test("An empty history produces a flat series rather than no series")
    func emptyHistoryIsFlat() {
        let series = TrendsEngine.monthlyNetWorth(
            accounts: [], transactions: [], reference: date(2026, 9, 12), calendar: calendar
        )

        #expect(series.points.count == 6)
        #expect(series.points.allSatisfy { $0.cents == 0 })
        #expect(series.deltaCents == 0)
        #expect(series.peakCents == 0)
    }
}
