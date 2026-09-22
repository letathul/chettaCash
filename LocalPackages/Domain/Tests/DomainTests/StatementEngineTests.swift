import Foundation
import Testing
@testable import Domain

/// Phase 7 acceptance criteria for card statements (§4.6).
@Suite("Card statements")
struct StatementEngineTests {

    /// A fixed UTC calendar, so results never depend on the runner's locale.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// Builds the last instant of a UTC day, which is when a period closes.
    /// - Parameters:
    ///   - year: The year.
    ///   - month: The month.
    ///   - day: The day.
    /// - Returns: That day's final instant.
    private func endOfDay(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: 23, minute: 59, second: 59
        )) ?? .now
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

    /// Builds a card account.
    /// - Parameters:
    ///   - closingDay: Day of month the statement closes.
    ///   - dueDay: Day of month payment is due.
    ///   - opening: The opening balance in cents, negative when owed.
    ///   - openedOn: The opening balance date.
    /// - Returns: The card.
    private func card(
        closingDay: Int = 5,
        dueDay: Int = 25,
        opening: Int = 0,
        openedOn: Date? = nil
    ) -> Account {
        Account(
            name: "TD Visa",
            kind: .card,
            openingBalanceCents: opening,
            openingBalanceDate: openedOn ?? date(2026, 1, 1),
            statementDayOfMonth: closingDay,
            paymentDueDayOfMonth: dueDay
        )
    }

    /// Builds a charge on a card.
    /// - Parameters:
    ///   - cents: The amount.
    ///   - card: The card.
    ///   - when: The date.
    /// - Returns: The transaction.
    private func charge(_ cents: Int, on card: Account, when: Date) -> Transaction {
        Transaction(amountCents: cents, type: .expense, accountID: card.id, date: when)
    }

    /// Builds a payment onto a card.
    /// - Parameters:
    ///   - cents: The amount.
    ///   - card: The card.
    ///   - when: The date.
    /// - Returns: The transaction.
    private func payment(_ cents: Int, to card: Account, when: Date) -> Transaction {
        Transaction(
            amountCents: cents, type: .transferIn, accountID: card.id,
            date: when, transferGroupID: UUID()
        )
    }

    // MARK: - Period generation

    @Test("Periods close on the statement day and fall due afterwards")
    func periodBoundaries() {
        let visa = card(closingDay: 5, dueDay: 25)

        let periods = StatementEngine.periods(
            for: visa, upTo: date(2026, 3, 10), calendar: calendar
        )

        #expect(periods.count == 3)
        #expect(periods[0].closingDate == endOfDay(2026, 1, 5))
        #expect(periods[0].dueDate == endOfDay(2026, 1, 25))
        #expect(periods[1].closingDate == endOfDay(2026, 2, 5))
        #expect(periods[2].closingDate == endOfDay(2026, 3, 5))
    }

    @Test("A due day earlier than the closing day falls into the next month")
    func dueDateRollsIntoNextMonth() {
        let visa = card(closingDay: 25, dueDay: 15)

        let periods = StatementEngine.periods(
            for: visa, upTo: date(2026, 2, 1), calendar: calendar
        )

        #expect(periods[0].closingDate == endOfDay(2026, 1, 25))
        #expect(periods[0].dueDate == endOfDay(2026, 2, 15))
    }

    @Test("A period starts the instant after the previous one closed")
    func periodsAreContiguous() {
        let visa = card(closingDay: 5)

        let periods = StatementEngine.periods(
            for: visa, upTo: date(2026, 3, 10), calendar: calendar
        )

        #expect(periods[1].periodStart > periods[0].closingDate)
        #expect(periods[1].periodStart < periods[1].closingDate)
    }

    @Test("A spending account has no statements")
    func onlyCardsHaveStatements() {
        let chequing = Account(name: "Chequing", kind: .account, statementDayOfMonth: 5)
        #expect(StatementEngine.periods(for: chequing, upTo: date(2026, 3, 1)).isEmpty)
    }

    // MARK: - Computed balance

    @Test("The statement balance is what was owed at closing, not what is owed now")
    func balanceIsFrozenAtClosing() {
        let visa = card(closingDay: 5)
        let transactions = [
            charge(10_000, on: visa, when: date(2026, 1, 3)),
            charge(4_000, on: visa, when: date(2026, 1, 20))
        ]

        let atClosing = StatementEngine.computedBalanceCents(
            account: visa, transactions: transactions, closingDate: date(2026, 1, 5)
        )
        let now = StatementEngine.owedCents(
            account: visa, transactions: transactions, asOf: date(2026, 1, 31)
        )

        #expect(atClosing == 10_000, "the later charge belongs to the next period")
        #expect(now == 14_000, "the current balance includes it")
    }

    @Test("A card in credit owes nothing rather than a negative figure")
    func creditBalanceOwesNothing() {
        let visa = card(opening: 5_000)
        #expect(StatementEngine.owedCents(
            account: visa, transactions: [], asOf: date(2026, 2, 1)
        ) == 0)
    }

    @Test("A user override supersedes the computed figure")
    func overrideWins() {
        var statement = CardStatement(computedBalanceCents: 10_000)
        #expect(statement.effectiveBalanceCents == 10_000)

        statement.overrideBalanceCents = 10_450
        #expect(statement.effectiveBalanceCents == 10_450)
    }

    // MARK: - Payment allocation

    @Test("A partial payment leaves the remainder outstanding")
    func partialPaymentLeavesRemainder() {
        let visa = card()
        let statement = CardStatement(
            accountID: visa.id, closingDate: date(2026, 1, 5),
            dueDate: date(2026, 1, 25), computedBalanceCents: 10_000, isPeriodClosed: true
        )
        let paid = payment(4_000, to: visa, when: date(2026, 1, 10))

        let plan = StatementAllocator.allocate(
            paymentTransactions: [paid], statements: [statement]
        )

        #expect(plan.payments.count == 1)
        #expect(plan.payments.first?.amountCents == 4_000)
        #expect(plan.overflowCentsByTransaction.isEmpty)
        #expect(StatementEngine.paidCents(of: statement, payments: plan.payments) == 4_000)
        #expect(StatementEngine.outstandingCents(
            of: statement, payments: plan.payments
        ) == 6_000, "$60.00 of $100.00 remains due")
    }

    @Test("Overflow beyond the statement is not allocated")
    func overflowIsNotAllocated() {
        let visa = card()
        let statement = CardStatement(
            accountID: visa.id, closingDate: date(2026, 1, 5),
            dueDate: date(2026, 1, 25), computedBalanceCents: 10_000, isPeriodClosed: true
        )
        let paid = payment(15_000, to: visa, when: date(2026, 1, 10))

        let plan = StatementAllocator.allocate(
            paymentTransactions: [paid], statements: [statement]
        )

        #expect(plan.payments.count == 1)
        #expect(plan.payments.first?.amountCents == 10_000)
        #expect(plan.overflowCentsByTransaction[paid.id] == 5_000)
        #expect(StatementEngine.outstandingCents(of: statement, payments: plan.payments) == 0)
    }

    @Test("Payments settle the oldest open statement first")
    func oldestStatementFirst() throws {
        let visa = card()
        let january = CardStatement(
            accountID: visa.id, closingDate: date(2026, 1, 5),
            dueDate: date(2026, 1, 25), computedBalanceCents: 6_000, isPeriodClosed: true
        )
        let february = CardStatement(
            accountID: visa.id, closingDate: date(2026, 2, 5),
            dueDate: date(2026, 2, 25), computedBalanceCents: 9_000, isPeriodClosed: true
        )
        let paid = payment(10_000, to: visa, when: date(2026, 2, 10))

        let plan = StatementAllocator.allocate(
            paymentTransactions: [paid],
            statements: [february, january]
        )

        #expect(plan.payments.count == 2)
        let toJanuary = try #require(plan.payments.first { $0.statementID == january.id })
        let toFebruary = try #require(plan.payments.first { $0.statementID == february.id })
        #expect(toJanuary.amountCents == 6_000, "January is settled in full first")
        #expect(toFebruary.amountCents == 4_000)
    }

    @Test("A payment cannot settle a statement that had not closed when it was made")
    func paymentCannotPrepayFutureStatement() {
        let visa = card()
        let february = CardStatement(
            accountID: visa.id, closingDate: date(2026, 2, 5),
            dueDate: date(2026, 2, 25), computedBalanceCents: 9_000, isPeriodClosed: true
        )
        let paid = payment(9_000, to: visa, when: date(2026, 1, 20))

        let plan = StatementAllocator.allocate(
            paymentTransactions: [paid], statements: [february]
        )

        #expect(plan.payments.isEmpty)
        #expect(plan.overflowCentsByTransaction[paid.id] == 9_000)
    }

    @Test("Re-running allocation does not double-allocate a recorded payment")
    func allocationIsIdempotent() {
        let visa = card()
        let statement = CardStatement(
            accountID: visa.id, closingDate: date(2026, 1, 5),
            dueDate: date(2026, 1, 25), computedBalanceCents: 10_000, isPeriodClosed: true
        )
        let paid = payment(4_000, to: visa, when: date(2026, 1, 10))
        let first = StatementAllocator.allocate(
            paymentTransactions: [paid], statements: [statement]
        )

        let second = StatementAllocator.allocate(
            paymentTransactions: [paid], statements: [statement],
            existingPayments: first.payments
        )

        #expect(second.payments.isEmpty)
    }

    @Test("Only transfers in are treated as card payments")
    func onlyTransfersInAllocate() {
        let visa = card()
        let statement = CardStatement(
            accountID: visa.id, closingDate: date(2026, 1, 5),
            dueDate: date(2026, 1, 25), computedBalanceCents: 10_000, isPeriodClosed: true
        )
        let spend = charge(3_000, on: visa, when: date(2026, 1, 10))

        let plan = StatementAllocator.allocate(
            paymentTransactions: [spend], statements: [statement]
        )

        #expect(plan.payments.isEmpty)
    }
}
