import Foundation
import Testing
@testable import Domain

/// Phase 8 acceptance criteria for the Today card and sheet (§7.2).
@Suite("Today digest")
struct TodayBuilderTests {

    /// A fixed UTC calendar, so results never depend on the runner's locale.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// The moment every test evaluates against.
    ///
    /// Evening, so a transaction dated midday today has already posted.
    private var now: Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 12, hour: 18
        )) ?? .now
    }

    /// A date offset from ``now`` by whole days.
    /// - Parameter days: Days to offset.
    /// - Returns: The offset date, at midday.
    private func day(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))?
            .addingTimeInterval(12 * 3_600) ?? now
    }

    /// A spending account.
    private var chequing: Account {
        Account(name: "Chequing", openingBalanceCents: 100_000,
                openingBalanceDate: day(-200))
    }

    /// Builds a digest.
    /// - Parameter input: The inputs to build from.
    /// - Returns: The digest.
    private func digest(_ input: TodayInput) -> TodayDigest {
        TodayBuilder.digest(from: input, now: now, calendar: calendar)
    }

    // MARK: - Quiet day

    @Test("A day with nothing at all is a quiet day")
    func quietDay() {
        let result = digest(TodayInput(accounts: [chequing]))

        #expect(result.isQuietDay)
        #expect(result.spentTodayCents == 0)
        #expect(result.postedTodayCount == 0)
        #expect(result.dueSoon.isEmpty)
        #expect(result.upcomingCharges.isEmpty)
        #expect(result.endingSoon.isEmpty)
    }

    @Test("Spending today ends the quiet day")
    func spendingEndsQuietDay() {
        let account = chequing
        let result = digest(TodayInput(
            accounts: [account],
            transactions: [Transaction(
                amountCents: 2_450, type: .expense, accountID: account.id, date: day(0)
            )]
        ))

        #expect(result.isQuietDay == false)
        #expect(result.spentTodayCents == 2_450)
        #expect(result.postedTodayCount == 1)
    }

    @Test("Yesterday's spending does not count toward today")
    func yesterdayIsNotToday() {
        let account = chequing
        let result = digest(TodayInput(
            accounts: [account],
            transactions: [Transaction(
                amountCents: 2_450, type: .expense, accountID: account.id, date: day(-1)
            )]
        ))

        #expect(result.spentTodayCents == 0)
        #expect(result.isQuietDay)
    }

    @Test("A transfer today is not spending")
    func transferIsNotSpending() throws {
        let account = chequing
        let legs = try TransferFactory.makeLegs(
            amountCents: 20_000, date: day(0),
            sourceAccountID: account.id, destinationAccountID: UUID()
        )

        let result = digest(TodayInput(accounts: [account], transactions: [legs.out, legs.in]))

        #expect(result.spentTodayCents == 0)
    }

    // MARK: - Due soon (§7.2, §10)

    /// A card with a closed, unpaid statement due in a given number of days.
    /// - Parameters:
    ///   - dueInDays: When the statement falls due.
    ///   - balance: The statement balance.
    /// - Returns: The card and its statement.
    private func cardWithStatement(
        dueInDays: Int,
        balance: Int = 10_000
    ) -> (card: Account, statement: CardStatement) {
        let card = Account(
            name: "TD Visa", kind: .card, openingBalanceCents: -balance,
            openingBalanceDate: day(-200), statementDayOfMonth: 5, paymentDueDayOfMonth: 25
        )
        let statement = CardStatement(
            accountID: card.id,
            closingDate: day(-7),
            dueDate: day(dueInDays),
            computedBalanceCents: balance,
            isPeriodClosed: true
        )
        return (card, statement)
    }

    @Test("A statement inside its three-day reminder window is due soon")
    func statementInsideWindow() throws {
        let fixture = cardWithStatement(dueInDays: 2)

        let result = digest(TodayInput(
            accounts: [fixture.card], statements: [fixture.statement]
        ))

        let due = try #require(result.dueSoon.first)
        #expect(due.accountName == "TD Visa")
        #expect(due.outstandingCents == 10_000)
        #expect(due.daysRemaining == 2)
        #expect(due.isOverdue == false)
    }

    @Test("A statement beyond the reminder window is not yet due soon")
    func statementOutsideWindow() {
        let fixture = cardWithStatement(dueInDays: 10)

        let result = digest(TodayInput(
            accounts: [fixture.card], statements: [fixture.statement]
        ))

        #expect(result.dueSoon.isEmpty)
    }

    @Test("An overdue statement stays listed")
    func overdueStatementIsListed() throws {
        let fixture = cardWithStatement(dueInDays: -4)

        let result = digest(TodayInput(
            accounts: [fixture.card], statements: [fixture.statement]
        ))

        let due = try #require(result.dueSoon.first)
        #expect(due.isOverdue)
        #expect(due.daysRemaining == -4)
    }

    @Test("A settled statement drops off the list")
    func settledStatementIsNotDue() {
        let fixture = cardWithStatement(dueInDays: 2)
        let payment = Transaction(
            amountCents: 10_000, type: .transferIn, accountID: fixture.card.id,
            date: day(-1), transferGroupID: UUID()
        )

        let result = digest(TodayInput(
            accounts: [fixture.card], transactions: [payment], statements: [fixture.statement]
        ))

        #expect(result.dueSoon.isEmpty)
    }

    @Test("A partially paid statement carries its partial-payment figures")
    func partialPaymentFigures() throws {
        let fixture = cardWithStatement(dueInDays: 2)
        let payment = Transaction(
            amountCents: 4_000, type: .transferIn, accountID: fixture.card.id,
            date: day(-1), transferGroupID: UUID()
        )

        let result = digest(TodayInput(
            accounts: [fixture.card], transactions: [payment], statements: [fixture.statement]
        ))

        let due = try #require(result.dueSoon.first)
        #expect(due.paidCents == 4_000)
        #expect(due.outstandingCents == 6_000)
    }

    @Test("Only the newest closed statement per card is listed as due")
    func supersededStatementsAreNotListed() throws {
        let card = Account(
            name: "TD Visa", kind: .card, openingBalanceCents: -124_075,
            openingBalanceDate: day(-200), statementDayOfMonth: 5, paymentDueDayOfMonth: 25
        )
        let older = CardStatement(
            accountID: card.id, closingDate: day(-38), dueDate: day(-18),
            computedBalanceCents: 124_075, isPeriodClosed: true
        )
        let newer = CardStatement(
            accountID: card.id, closingDate: day(-7), dueDate: day(2),
            computedBalanceCents: 124_075, isPeriodClosed: true
        )

        let result = digest(TodayInput(accounts: [card], statements: [older, newer]))

        #expect(result.dueSoon.count == 1, "the older statement is superseded, not separately due")
        #expect(try #require(result.dueSoon.first).statement.id == newer.id)
    }

    @Test("A card with reminders switched off is not listed")
    func remindersOffIsNotListed() {
        var fixture = cardWithStatement(dueInDays: 2)
        fixture.card.remindBeforeDueDate = false

        let result = digest(TodayInput(
            accounts: [fixture.card], statements: [fixture.statement]
        ))

        #expect(result.dueSoon.isEmpty)
    }
}
