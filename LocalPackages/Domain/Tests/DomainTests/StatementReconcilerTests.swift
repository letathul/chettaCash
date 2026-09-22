import Foundation
import Testing
@testable import Domain

/// Phase 7 acceptance criteria for reconciling a card end to end (§4.6).
@Suite("Statement reconciliation")
struct StatementReconcilerTests {

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

    /// A card closing on the 5th and due on the 25th.
    private var visa: Account {
        Account(
            name: "TD Visa",
            kind: .card,
            openingBalanceDate: date(2026, 1, 1),
            statementDayOfMonth: 5,
            paymentDueDayOfMonth: 25
        )
    }

    /// Runs a reconcile pass.
    /// - Parameters:
    ///   - card: The card to reconcile.
    ///   - transactions: Its transactions.
    ///   - statements: Statements already stored.
    ///   - payments: Allocations already stored.
    ///   - now: The moment deciding which periods have closed.
    /// - Returns: The outcome.
    private func reconcile(
        _ card: Account,
        transactions: [Transaction],
        statements: [CardStatement] = [],
        payments: [StatementPayment] = [],
        now: Date
    ) -> StatementReconcileOutcome {
        StatementReconciler.reconcile(
            account: card, transactions: transactions,
            existingStatements: statements, existingPayments: payments,
            now: now, calendar: calendar
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

    @Test("A charge made on the closing day belongs to the statement it closed")
    func closingDayChargeIsIncluded() throws {
        let card = visa
        let outcome = reconcile(
            card,
            transactions: [charge(7_500, on: card, when: date(2026, 1, 5))],
            now: date(2026, 1, 20)
        )

        let january = try #require(outcome.statements.first)
        #expect(january.computedBalanceCents == 7_500)
        #expect(january.isPeriodClosed)
    }

    @Test("A closed statement's balance is frozen against later charges")
    func closedStatementIsFrozen() throws {
        let card = visa
        let first = reconcile(
            card,
            transactions: [charge(7_500, on: card, when: date(2026, 1, 3))],
            now: date(2026, 1, 20)
        )
        let stored = try #require(first.statements.first)

        let second = reconcile(
            card,
            transactions: [
                charge(7_500, on: card, when: date(2026, 1, 3)),
                charge(3_000, on: card, when: date(2026, 1, 25))
            ],
            statements: [stored],
            now: date(2026, 1, 30)
        )

        let january = second.statements.first { $0.id == stored.id } ?? stored
        #expect(january.computedBalanceCents == 7_500, "later charges belong to February")
    }

    @Test("Both figures are available: statement balance and current balance")
    func bothFiguresAvailable() throws {
        let card = visa
        let transactions = [
            charge(10_000, on: card, when: date(2026, 1, 3)),
            charge(4_000, on: card, when: date(2026, 1, 20))
        ]
        let outcome = reconcile(card, transactions: transactions, now: date(2026, 1, 25))

        let january = try #require(outcome.statements.first)
        let currentlyOwed = StatementEngine.owedCents(
            account: card, transactions: transactions, asOf: date(2026, 1, 25)
        )

        #expect(january.effectiveBalanceCents == 10_000)
        #expect(currentlyOwed == 14_000)
    }

    @Test("A partial payment is allocated and leaves the remainder due")
    func partialPaymentAllocates() throws {
        let card = visa
        let transactions = [
            charge(10_000, on: card, when: date(2026, 1, 3)),
            Transaction(
                amountCents: 4_000, type: .transferIn, accountID: card.id,
                date: date(2026, 1, 10), transferGroupID: UUID()
            )
        ]

        let outcome = reconcile(card, transactions: transactions, now: date(2026, 1, 20))

        let january = try #require(outcome.statements.first)
        #expect(StatementEngine.paidCents(of: january, payments: outcome.payments) == 4_000)
        #expect(StatementEngine.outstandingCents(
            of: january, payments: outcome.payments
        ) == 6_000)
    }

    @Test("The interest prompt asks once per statement and never again once resolved")
    func interestPromptAsksOnce() {
        var statement = CardStatement(computedBalanceCents: 10_000, isPeriodClosed: true)
        #expect(InterestPrompt.shouldAsk(about: statement))

        statement = InterestPrompt.resolved(statement)

        #expect(InterestPrompt.shouldAsk(about: statement) == false)
    }

    @Test("An open period is never asked about interest")
    func openPeriodIsNotAsked() {
        let statement = CardStatement(computedBalanceCents: 10_000, isPeriodClosed: false)
        #expect(InterestPrompt.shouldAsk(about: statement) == false)
    }

    @Test("An entered interest amount becomes a Bills expense dated to the closing date")
    func interestBecomesExpense() throws {
        let card = visa
        let bills = UUID()
        let statement = CardStatement(
            accountID: card.id, closingDate: date(2026, 1, 5), isPeriodClosed: true
        )

        let charge = try #require(
            InterestPrompt.makeCharge(for: statement, cents: 1_250, billsCategoryID: bills)
        )

        #expect(charge.type == .expense)
        #expect(charge.amountCents == 1_250)
        #expect(charge.categoryID == bills)
        #expect(charge.accountID == card.id)
        #expect(charge.date == statement.closingDate)
    }

    @Test("Dismissing the prompt records no charge", arguments: [0, -100])
    func dismissingRecordsNothing(cents: Int) {
        let statement = CardStatement(accountID: UUID(), isPeriodClosed: true)
        #expect(InterestPrompt.makeCharge(
            for: statement, cents: cents, billsCategoryID: nil
        ) == nil)
    }

    @Test("Reconciling twice writes no duplicate statements or allocations")
    func reconcileIsIdempotent() {
        let card = visa
        let transactions = [charge(10_000, on: card, when: date(2026, 1, 3))]
        let first = reconcile(card, transactions: transactions, now: date(2026, 1, 20))

        let second = reconcile(
            card, transactions: transactions,
            statements: first.statements, payments: first.payments,
            now: date(2026, 1, 20)
        )

        #expect(second.isEmpty)
    }
}

/// Statement balances roll up earlier periods, so a payment must reduce what the
/// current statement shows as due rather than only the superseded one (§4.6).
@Suite("Cumulative statement balances")
struct CumulativeStatementTests {

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

    @Test("A payment reduces what the current statement shows as due")
    func paymentReducesCurrentStatement() {
        let card = Account(name: "Visa", kind: .card)
        let july = CardStatement(
            accountID: card.id, closingDate: date(2026, 7, 5),
            computedBalanceCents: 124_075, isPeriodClosed: true
        )
        let september = CardStatement(
            accountID: card.id, closingDate: date(2026, 9, 5),
            computedBalanceCents: 124_075, isPeriodClosed: true
        )
        let payment = Transaction(
            amountCents: 50_000, type: .transferIn, accountID: card.id,
            date: date(2026, 9, 10), transferGroupID: UUID()
        )

        #expect(StatementEngine.remainingCents(of: september, transactions: [payment]) == 74_075)
        #expect(StatementEngine.remainingCents(of: july, transactions: [payment]) == 74_075)
    }

    @Test("A payment made before a statement closed does not settle it")
    func earlierPaymentDoesNotSettleLaterStatement() {
        let card = Account(name: "Visa", kind: .card)
        let september = CardStatement(
            accountID: card.id, closingDate: date(2026, 9, 5),
            computedBalanceCents: 124_075, isPeriodClosed: true
        )
        let payment = Transaction(
            amountCents: 50_000, type: .transferIn, accountID: card.id,
            date: date(2026, 8, 20), transferGroupID: UUID()
        )

        #expect(StatementEngine.remainingCents(
            of: september, transactions: [payment]
        ) == 124_075, "it was already reflected in the closing balance")
    }

    @Test("Paying more than the statement settles it without going negative")
    func overpaymentSettlesWithoutNegative() {
        let card = Account(name: "Visa", kind: .card)
        let statement = CardStatement(
            accountID: card.id, closingDate: date(2026, 9, 5),
            computedBalanceCents: 10_000, isPeriodClosed: true
        )
        let payment = Transaction(
            amountCents: 15_000, type: .transferIn, accountID: card.id,
            date: date(2026, 9, 10), transferGroupID: UUID()
        )

        #expect(StatementEngine.settledCents(of: statement, transactions: [payment]) == 10_000)
        #expect(StatementEngine.remainingCents(of: statement, transactions: [payment]) == 0)
    }
}
