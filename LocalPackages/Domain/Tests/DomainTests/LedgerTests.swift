import Foundation
import Testing
@testable import Domain

/// Phase 5 acceptance criteria for the Ledger's filters and rows (§7.4, §4.3).
@Suite("Ledger filtering and assembly")
struct LedgerTests {

    /// A fixed calendar so month boundaries never depend on the runner's locale.
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
    /// - Returns: Noon on that day, which keeps it clear of boundary instants.
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .now
    }

    // MARK: - Period boundaries

    @Test("This month covers the whole calendar month and nothing either side")
    func thisMonthBoundaries() throws {
        let reference = date(2026, 9, 12)
        let range = try #require(
            LedgerPeriod.thisMonth.dateRange(containing: reference, calendar: calendar)
        )

        #expect(range.contains(date(2026, 9, 1)))
        #expect(range.contains(date(2026, 9, 30)))
        #expect(!range.contains(date(2026, 8, 31)))
        #expect(!range.contains(date(2026, 10, 1)))
    }

    @Test("Last month uses real calendar months, including across a year boundary")
    func lastMonthBoundaries() throws {
        let january = try #require(
            LedgerPeriod.lastMonth.dateRange(containing: date(2027, 1, 15), calendar: calendar)
        )
        #expect(january.contains(date(2026, 12, 25)))
        #expect(!january.contains(date(2027, 1, 1)))

        let february = try #require(
            LedgerPeriod.lastMonth.dateRange(containing: date(2026, 3, 15), calendar: calendar)
        )
        #expect(february.contains(date(2026, 2, 28)))
        #expect(!february.contains(date(2026, 3, 1)))
    }

    @Test("All time has no boundaries")
    func allTimeIsUnbounded() {
        #expect(LedgerPeriod.allTime.dateRange(containing: date(2026, 9, 12)) == nil)
    }

    // MARK: - Combined filtering

    /// Builds a transaction for filter tests.
    /// - Parameters:
    ///   - type: The transaction type.
    ///   - cents: The magnitude.
    ///   - accountID: The owning account.
    ///   - categoryID: The assigned category.
    ///   - when: The date.
    /// - Returns: The transaction.
    private func transaction(
        _ type: TransactionType = .expense,
        cents: Int = 1_000,
        accountID: UUID,
        categoryID: UUID? = nil,
        when: Date
    ) -> Transaction {
        Transaction(
            amountCents: cents,
            type: type,
            categoryID: categoryID,
            accountID: accountID,
            date: when
        )
    }

    @Test("Period, account and category combine with AND")
    func filtersCombineWithAnd() {
        let chequing = UUID()
        let visa = UUID()
        let groceries = UUID()
        let transport = UUID()
        let reference = date(2026, 9, 12)
        let all = [
            transaction(accountID: chequing, categoryID: groceries, when: date(2026, 9, 3)),
            transaction(accountID: chequing, categoryID: transport, when: date(2026, 9, 4)),
            transaction(accountID: visa, categoryID: groceries, when: date(2026, 9, 5)),
            transaction(accountID: chequing, categoryID: groceries, when: date(2026, 8, 20))
        ]

        let filter = LedgerFilter(period: .thisMonth, accountID: chequing, categoryID: groceries)
        let matched = filter.apply(to: all, reference: reference, calendar: calendar)

        #expect(matched.count == 1)
        #expect(matched.first?.date == date(2026, 9, 3))
    }

    @Test("A filter combination matching nothing returns empty rather than falling back")
    func emptyCombinationIsEmpty() {
        let chequing = UUID()
        let all = [transaction(accountID: chequing, when: date(2026, 9, 3))]

        let filter = LedgerFilter(period: .thisMonth, accountID: UUID(), categoryID: nil)
        let matched = filter.apply(to: all, reference: date(2026, 9, 12), calendar: calendar)

        #expect(matched.isEmpty)
    }

    // MARK: - Transfer rows (§4.3)

    /// Builds a transfer pair between two accounts.
    /// - Parameters:
    ///   - source: The source account.
    ///   - destination: The destination account.
    ///   - when: The date both legs carry.
    /// - Returns: The two legs.
    private func transferLegs(
        source: UUID,
        destination: UUID,
        when: Date
    ) throws -> (out: Transaction, in: Transaction) {
        try TransferFactory.makeLegs(
            amountCents: 5_000,
            date: when,
            sourceAccountID: source,
            destinationAccountID: destination
        )
    }

    @Test("With no account filter a transfer collapses into one row")
    func transferCollapsesWithoutAccountFilter() throws {
        let chequing = UUID()
        let visa = UUID()
        let legs = try transferLegs(source: chequing, destination: visa, when: date(2026, 9, 5))

        let items = LedgerAssembler.items(from: [legs.out, legs.in], collapseTransfers: true)

        #expect(items.count == 1)
        guard case .transfer(let outLeg, let inLeg) = items[0] else {
            Issue.record("Expected a collapsed transfer row")
            return
        }
        #expect(outLeg.accountID == chequing)
        #expect(inLeg.accountID == visa)
    }

    @Test("With an account filter only that account's leg is shown")
    func transferShowsOneLegWhenFiltered() throws {
        let chequing = UUID()
        let visa = UUID()
        let legs = try transferLegs(source: chequing, destination: visa, when: date(2026, 9, 5))
        let filter = LedgerFilter(period: .allTime, accountID: visa)

        let matched = filter.apply(to: [legs.out, legs.in], calendar: calendar)
        let items = LedgerAssembler.items(
            from: matched, collapseTransfers: filter.isAccountFiltered == false
        )

        #expect(items.count == 1)
        guard case .single(let leg) = items[0] else {
            Issue.record("Expected a single leg row")
            return
        }
        #expect(leg.accountID == visa)
        #expect(leg.type == .transferIn)
    }

    @Test("A transfer whose partner is filtered out still renders as a row")
    func orphanedLegStillRenders() throws {
        let legs = try transferLegs(source: UUID(), destination: UUID(), when: date(2026, 9, 5))

        let items = LedgerAssembler.items(from: [legs.out], collapseTransfers: true)

        #expect(items.count == 1)
        guard case .single = items[0] else {
            Issue.record("Expected the surviving leg to render alone")
            return
        }
    }

    // MARK: - Upcoming and grouping (§7.4)

    @Test("Unposted rows split into Upcoming, soonest first, above posted history")
    func upcomingSplit() {
        let account = UUID()
        let now = date(2026, 9, 12)
        let items = LedgerAssembler.items(
            from: [
                transaction(accountID: account, when: date(2026, 9, 20)),
                transaction(accountID: account, when: date(2026, 9, 15)),
                transaction(accountID: account, when: date(2026, 9, 10)),
                transaction(accountID: account, when: date(2026, 9, 11))
            ],
            collapseTransfers: true
        )

        let split = LedgerAssembler.split(items, asOf: now)

        #expect(split.upcoming.map(\.date) == [date(2026, 9, 15), date(2026, 9, 20)])
        #expect(split.posted.map(\.date) == [date(2026, 9, 11), date(2026, 9, 10)])
    }

    @Test("Posted rows group by calendar day, newest day first")
    func groupsByDay() {
        let account = UUID()
        let items = LedgerAssembler.items(
            from: [
                transaction(accountID: account, when: date(2026, 9, 10)),
                transaction(accountID: account, when: date(2026, 9, 10)),
                transaction(accountID: account, when: date(2026, 9, 9))
            ],
            collapseTransfers: true
        )

        let days = LedgerAssembler.groupedByDay(items, calendar: calendar)

        #expect(days.count == 2)
        #expect(days[0].items.count == 2)
        #expect(days[1].items.count == 1)
        #expect(days[0].day > days[1].day)
    }

    // MARK: - Summary banner (§4.3, §7.4)

    @Test("Transfers and adjustments are visible as rows but absent from the banner")
    func bannerExcludesTransfersAndAdjustments() throws {
        let chequing = UUID()
        let visa = UUID()
        let now = date(2026, 9, 12)
        let purchase = transaction(cents: 6_000, accountID: visa, when: date(2026, 9, 5))
        let payment = try transferLegs(source: chequing, destination: visa, when: date(2026, 9, 6))
        let correction = AdjustmentFactory.make(
            accountID: chequing, signedCents: -2_000, date: date(2026, 9, 7)
        )
        let all = [purchase, payment.out, payment.in, correction]

        let items = LedgerAssembler.items(from: all, collapseTransfers: true)
        let spend = TotalsEngine.spendTotalCents(transactions: all, asOf: now)
        let income = TotalsEngine.incomeTotalCents(transactions: all, asOf: now)
        let count = LedgerAssembler.bannerCount(of: all, asOf: now)

        #expect(items.count == 3, "purchase, collapsed transfer and adjustment all render")
        #expect(spend == 6_000)
        #expect(income == 0)
        #expect(count == 1)
    }

    @Test("Unposted transactions are excluded from the banner totals")
    func bannerExcludesUpcoming() {
        let account = UUID()
        let now = date(2026, 9, 12)
        let all = [
            transaction(cents: 1_000, accountID: account, when: date(2026, 9, 10)),
            transaction(cents: 9_000, accountID: account, when: date(2026, 9, 20))
        ]

        #expect(TotalsEngine.spendTotalCents(transactions: all, asOf: now) == 1_000)
        #expect(LedgerAssembler.bannerCount(of: all, asOf: now) == 1)
    }
}
