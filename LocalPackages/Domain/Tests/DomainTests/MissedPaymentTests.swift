import Foundation
import Testing
@testable import Domain

/// A missed card payment is announced rather than silently rolled forward
/// (§7.2, §4.6 — closes finding B7a).
///
/// Statement balances are cumulative, so an unpaid month is never *lost*: it rolls into
/// the next statement. But that statement has its own later due date, which would
/// otherwise leave the user unaware they are behind.
@Suite("Missed card payments")
struct MissedPaymentTests {

    /// A fixed UTC calendar, so results never depend on the runner's locale.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// The moment every test evaluates against.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 18)) ?? .now
    }

    /// A date offset from ``now`` by whole days, at midday.
    /// - Parameter days: Days to offset.
    /// - Returns: The offset date.
    private func day(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))?
            .addingTimeInterval(12 * 3_600) ?? now
    }

    /// The card under test.
    private var card: Account {
        Account(
            name: "TD Visa", kind: .card, openingBalanceCents: -124_075,
            openingBalanceDate: day(-200), statementDayOfMonth: 5, paymentDueDayOfMonth: 25
        )
    }

    /// Builds a closed statement.
    /// - Parameters:
    ///   - card: The card it belongs to.
    ///   - closedDaysAgo: How long ago the period closed.
    ///   - dueDaysFromNow: When it falls due, relative to now.
    ///   - balance: The statement balance.
    /// - Returns: The statement.
    private func statement(
        on card: Account,
        closedDaysAgo: Int,
        dueDaysFromNow: Int,
        balance: Int
    ) -> CardStatement {
        CardStatement(
            accountID: card.id,
            closingDate: day(-closedDaysAgo),
            dueDate: day(dueDaysFromNow),
            computedBalanceCents: balance,
            isPeriodClosed: true
        )
    }

    /// Builds a payment onto the card.
    /// - Parameters:
    ///   - cents: The amount.
    ///   - card: The card.
    ///   - daysAgo: How long ago it was made.
    /// - Returns: The transaction.
    private func payment(_ cents: Int, to card: Account, daysAgo: Int) -> Transaction {
        Transaction(
            amountCents: cents, type: .transferIn, accountID: card.id,
            date: day(-daysAgo), transferGroupID: UUID()
        )
    }

    /// Builds a digest.
    /// - Parameters:
    ///   - card: The card to include.
    ///   - statements: Its statements.
    ///   - transactions: Its transactions.
    /// - Returns: The digest.
    private func digest(
        card: Account,
        statements: [CardStatement],
        transactions: [Transaction] = []
    ) -> TodayDigest {
        TodayBuilder.digest(
            from: TodayInput(
                accounts: [card], transactions: transactions, statements: statements
            ),
            now: now,
            calendar: calendar
        )
    }

    /// August closed and fell due before today; September closed but is not due yet.
    /// - Parameter card: The card they belong to.
    /// - Returns: The August and September statements.
    private func twoMonths(on card: Account) -> (august: CardStatement, september: CardStatement) {
        (
            august: statement(on: card, closedDaysAgo: 38, dueDaysFromNow: -18, balance: 74_075),
            september: statement(on: card, closedDaysAgo: 7, dueDaysFromNow: 13, balance: 104_075)
        )
    }

    @Test("An unpaid statement past its due date is announced")
    func unpaidStatementWarns() throws {
        let card = self.card
        let months = twoMonths(on: card)

        let result = digest(card: card, statements: [months.august, months.september])

        let missed = try #require(result.missedPayments.first)
        #expect(missed.accountName == "TD Visa")
        #expect(missed.outstandingCents == 74_075)
        #expect(missed.daysOverdue == 18)
        #expect(result.isQuietDay == false, "being behind is never a quiet day")
    }

    @Test("Nothing is announced while the newest statement is not yet due")
    func newestStatementIsNotAMissedPayment() {
        let card = self.card
        let september = statement(on: card, closedDaysAgo: 7, dueDaysFromNow: 13, balance: 104_075)

        let result = digest(card: card, statements: [september])

        #expect(result.missedPayments.isEmpty, "it has not been missed — it is not due yet")
    }

    @Test("Paying late clears the warning")
    func payingLateClearsWarning() {
        let card = self.card
        let months = twoMonths(on: card)
        let late = payment(74_075, to: card, daysAgo: 2)

        let result = digest(
            card: card, statements: [months.august, months.september], transactions: [late]
        )

        #expect(result.missedPayments.isEmpty)
    }

    @Test("A partial late payment still leaves the remainder announced")
    func partialLatePaymentStillWarns() throws {
        let card = self.card
        let months = twoMonths(on: card)
        let partial = payment(24_075, to: card, daysAgo: 2)

        let result = digest(
            card: card, statements: [months.august, months.september], transactions: [partial]
        )

        let missed = try #require(result.missedPayments.first)
        #expect(missed.outstandingCents == 50_000)
    }

    @Test("A statement settled before its due date is never announced")
    func settledStatementNeverWarns() {
        let card = self.card
        let months = twoMonths(on: card)
        let onTime = payment(74_075, to: card, daysAgo: 20)

        let result = digest(
            card: card, statements: [months.august, months.september], transactions: [onTime]
        )

        #expect(result.missedPayments.isEmpty)
    }

    @Test("A closed card is never announced")
    func closedCardNeverWarns() {
        var card = self.card
        card.isClosed = true
        let months = twoMonths(on: card)

        let result = digest(card: card, statements: [months.august, months.september])

        #expect(result.missedPayments.isEmpty)
    }

    @Test("Several missed months are announced oldest first")
    func severalMissedMonthsAreOrdered() {
        let card = self.card
        let july = statement(on: card, closedDaysAgo: 69, dueDaysFromNow: -49, balance: 50_000)
        let months = twoMonths(on: card)

        let result = digest(
            card: card, statements: [months.september, months.august, july]
        )

        #expect(result.missedPayments.count == 2)
        #expect(result.missedPayments.map(\.statement.id) == [july.id, months.august.id])
    }

    @Test("A card with no statements at all is a quiet day")
    func noStatementsIsQuiet() {
        #expect(digest(card: card, statements: []).isQuietDay)
    }
}
