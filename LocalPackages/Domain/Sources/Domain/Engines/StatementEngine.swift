import Foundation

/// One billing period's boundaries.
public struct StatementPeriod: Equatable, Sendable {
    /// First day covered by the statement.
    public let periodStart: Date
    /// The day the period closes.
    public let closingDate: Date
    /// The day payment is due, always after the closing date.
    public let dueDate: Date

    /// Creates a period.
    /// - Parameters:
    ///   - periodStart: First day covered.
    ///   - closingDate: The day the period closes.
    ///   - dueDate: The day payment is due.
    public init(periodStart: Date, closingDate: Date, dueDate: Date) {
        self.periodStart = periodStart
        self.closingDate = closingDate
        self.dueDate = dueDate
    }
}

/// Derives credit-card statements and payment allocation (§4.6).
///
/// A card carries two figures and both must be shown: the **current balance**, which
/// includes charges made after the period closed, and the **statement balance**,
/// which is what was owed at closing and is what is actually due.
///
/// No APR is stored and no interest is calculated — the user's real statement is the
/// source of truth, and anything it charged is entered by hand.
public enum StatementEngine {

    /// The most periods one pass will generate for a single card.
    public static let generationLimit = 240

    /// Generates the billing periods that have begun for a card.
    ///
    /// The closing day comes from the account; the due date is the next occurrence
    /// of the payment day strictly after closing, so a card closing on the 25th and
    /// due on the 15th correctly bills into the following month.
    ///
    /// - Parameters:
    ///   - account: The card to schedule.
    ///   - upTo: Generate periods whose closing date falls on or before this moment.
    ///   - calendar: The calendar to compute in.
    /// - Returns: The periods, oldest first.
    public static func periods(
        for account: Account,
        upTo: Date,
        calendar: Calendar = .current
    ) -> [StatementPeriod] {
        guard account.kind == .card,
              let closingDay = account.statementDayOfMonth,
              let dueDay = account.paymentDueDayOfMonth else { return [] }

        var periods: [StatementPeriod] = []
        var periodStart = account.openingBalanceDate
        var cursor = account.openingBalanceDate

        while periods.count < generationLimit {
            guard let closing = nextDay(closingDay, strictlyAfter: cursor, calendar: calendar),
                  closing <= upTo,
                  let due = nextDay(dueDay, strictlyAfter: closing, calendar: calendar)
            else { break }

            periods.append(
                StatementPeriod(periodStart: periodStart, closingDate: closing, dueDate: due)
            )
            periodStart = calendar.date(byAdding: .second, value: 1, to: closing) ?? closing
            cursor = closing
        }
        return periods
    }

    /// The amount owed on a card at a moment in time, as a positive figure.
    ///
    /// Card balances are negative when money is owed (§4.1), so this flips the sign
    /// and floors at zero — a card in credit owes nothing.
    ///
    /// - Parameters:
    ///   - account: The card to evaluate.
    ///   - transactions: Transactions to consider.
    ///   - asOf: The moment to evaluate at, normally a closing date.
    /// - Returns: The amount owed in cents, never negative.
    public static func owedCents(
        account: Account,
        transactions: [Transaction],
        asOf: Date
    ) -> Int {
        let balance = BalanceEngine.currentBalanceCents(
            account: account, transactions: transactions, asOf: asOf
        )
        return max(0, -balance)
    }

    /// The statement balance computed from the period's transactions.
    ///
    /// This is what was owed as of the closing date. A user override supersedes it
    /// when the real statement differs — see ``CardStatement/effectiveBalanceCents``.
    ///
    /// - Parameters:
    ///   - account: The card the statement belongs to.
    ///   - transactions: Transactions to consider.
    ///   - closingDate: The day the period closed.
    /// - Returns: The computed statement balance in cents.
    public static func computedBalanceCents(
        account: Account,
        transactions: [Transaction],
        closingDate: Date
    ) -> Int {
        owedCents(account: account, transactions: transactions, asOf: closingDate)
    }

    /// How much of a statement is still unpaid, from its allocations.
    /// - Parameters:
    ///   - statement: The statement to evaluate.
    ///   - payments: Allocations recorded against it.
    /// - Returns: The outstanding amount in cents, never negative.
    public static func outstandingCents(
        of statement: CardStatement,
        payments: [StatementPayment]
    ) -> Int {
        max(0, statement.effectiveBalanceCents - paidCents(of: statement, payments: payments))
    }

    /// How much has been paid toward a statement since it closed.
    ///
    /// A statement balance is what was owed **as of** its closing date, so it rolls
    /// up everything still outstanding from earlier periods. What settles it is
    /// therefore every payment made after it closed, not just the allocations
    /// recorded against that one row — otherwise a payment applied to an older,
    /// superseded statement would leave the current one looking untouched.
    ///
    /// - Parameters:
    ///   - statement: The statement to evaluate.
    ///   - transactions: Every transaction on that card.
    /// - Returns: The amount settled in cents, capped at the statement balance.
    public static func settledCents(
        of statement: CardStatement,
        transactions: [Transaction]
    ) -> Int {
        let paid = transactions
            .filter { $0.type == .transferIn && $0.date > statement.closingDate }
            .reduce(0) { $0 + $1.amountCents }
        return min(paid, statement.effectiveBalanceCents)
    }

    /// How much of a statement is still unpaid, given the card's payment history.
    /// - Parameters:
    ///   - statement: The statement to evaluate.
    ///   - transactions: Every transaction on that card.
    /// - Returns: The outstanding amount in cents, never negative.
    public static func remainingCents(
        of statement: CardStatement,
        transactions: [Transaction]
    ) -> Int {
        max(0, statement.effectiveBalanceCents - settledCents(of: statement, transactions: transactions))
    }

    /// How much has been allocated against a statement.
    /// - Parameters:
    ///   - statement: The statement to evaluate.
    ///   - payments: Allocations recorded against it.
    /// - Returns: The paid amount in cents.
    public static func paidCents(
        of statement: CardStatement,
        payments: [StatementPayment]
    ) -> Int {
        payments
            .filter { $0.statementID == statement.id }
            .reduce(0) { $0 + $1.amountCents }
    }
}

/// Date helpers used when generating billing periods.
extension StatementEngine {
    /// Finds the next occurrence of a day of the month after a date, at end of day.
    ///
    /// Uses `.previousTimePreservingSmallerComponents` so a 31st closing day lands on
    /// the last day of a shorter month rather than spilling into the next one.
    ///
    /// The result is the **last instant** of that day rather than its first. A card
    /// closes at the end of its closing day, so a charge made that day belongs to
    /// the statement it closed, not to the next period.
    ///
    /// - Parameters:
    ///   - day: The day of the month to match.
    ///   - date: The date to search after.
    ///   - calendar: The calendar to compute in.
    /// - Returns: The matching date, or `nil` if the calendar cannot produce one.
    static func nextDay(
        _ day: Int,
        strictlyAfter date: Date,
        calendar: Calendar
    ) -> Date? {
        guard let matched = calendar.nextDate(
            after: date,
            matching: DateComponents(day: day),
            matchingPolicy: .previousTimePreservingSmallerComponents
        ) else { return nil }
        return calendar.date(bySettingHour: 23, minute: 59, second: 59, of: matched) ?? matched
    }
}
