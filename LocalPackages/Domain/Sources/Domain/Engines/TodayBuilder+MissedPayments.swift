import Foundation

/// The missed-payment rule (§4.6), kept apart from the rest of the digest.
///
/// It is the one section that looks *backwards* rather than forwards, and the only
/// one that reaches into ``StatementEngine`` for an amount it did not compute.
extension TodayBuilder {

    /// Statements whose due date passed while they were still owed (§4.6).
    ///
    /// Only statements *older* than the newest closed one are considered: the newest is
    /// already reported by ``dueSoon(_:now:calendar:)``, which marks it overdue when its
    /// own date has passed. Paying late clears the warning, because `remainingCents`
    /// counts every payment made after that statement closed.
    ///
    /// - Parameters:
    ///   - input: The digest inputs.
    ///   - now: The moment to evaluate against.
    ///   - calendar: The calendar deciding day boundaries.
    /// - Returns: The items, longest overdue first.
    static func missedPayments(
        _ input: TodayInput,
        now: Date,
        calendar: Calendar
    ) -> [MissedPaymentItem] {
        let accountsByID = Dictionary(uniqueKeysWithValues: input.accounts.map { ($0.id, $0) })
        let newestPerCard = Dictionary(
            grouping: input.statements.filter(\.isPeriodClosed),
            by: { $0.accountID }
        ).compactMapValues { $0.max { $0.closingDate < $1.closingDate } }

        return input.statements
            .filter { $0.isPeriodClosed && $0.dueDate < now }
            .filter { $0.id != newestPerCard[$0.accountID]?.id }
            .compactMap { statement -> MissedPaymentItem? in
                guard let accountID = statement.accountID,
                      let account = accountsByID[accountID],
                      !account.isClosed else { return nil }
                let cardTransactions = input.transactions.filter { $0.accountID == accountID }
                let outstanding = StatementEngine.remainingCents(
                    of: statement, transactions: cardTransactions
                )
                guard outstanding > 0 else { return nil }
                return MissedPaymentItem(
                    statement: statement,
                    accountName: account.name,
                    outstandingCents: outstanding,
                    daysOverdue: abs(days(from: now, to: statement.dueDate, calendar: calendar))
                )
            }
            .sorted { $0.statement.dueDate < $1.statement.dueDate }
    }
}
