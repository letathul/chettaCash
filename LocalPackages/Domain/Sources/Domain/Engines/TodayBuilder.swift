import Foundation

/// The inputs the Today digest is built from.
public struct TodayInput: Sendable {
    /// Every account, closed ones included.
    public var accounts: [Account]
    /// Every transaction.
    public var transactions: [Transaction]
    /// Every card statement.
    public var statements: [CardStatement]
    /// Active recurring rules.
    public var rules: [RecurringRule]
    /// Every product.
    public var products: [Product]
    /// The lead time used when a reminder is set to ``ReminderLeadTime/useDefault``.
    public var defaultLeadTime: ReminderLeadTime

    /// Creates the inputs.
    /// - Parameters:
    ///   - accounts: Every account.
    ///   - transactions: Every transaction.
    ///   - statements: Every card statement.
    ///   - rules: Active recurring rules.
    ///   - products: Every product.
    ///   - defaultLeadTime: The fallback reminder lead time.
    public init(
        accounts: [Account] = [],
        transactions: [Transaction] = [],
        statements: [CardStatement] = [],
        rules: [RecurringRule] = [],
        products: [Product] = [],
        defaultLeadTime: ReminderLeadTime = .threeDaysBefore
    ) {
        self.accounts = accounts
        self.transactions = transactions
        self.statements = statements
        self.rules = rules
        self.products = products
        self.defaultLeadTime = defaultLeadTime
    }
}

/// Assembles the Today card and sheet (§7.2).
public enum TodayBuilder {

    /// How far ahead the Upcoming charges section looks.
    public static let upcomingHorizonDays = 30

    /// The fixed lead time on a card payment reminder (§10).
    ///
    /// Not configurable — §10 is explicit that this one has no picker.
    public static let cardReminderLeadDays = 3

    /// Builds the digest.
    /// - Parameters:
    ///   - input: Everything the digest is derived from.
    ///   - now: The moment to evaluate against.
    ///   - calendar: The calendar deciding day boundaries.
    /// - Returns: The digest.
    public static func digest(
        from input: TodayInput,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TodayDigest {
        let today = dayRange(containing: now, calendar: calendar)
        let postedToday = input.transactions.filter {
            today.contains($0.date) && BalanceEngine.isPosted($0, asOf: now)
        }
        return TodayDigest(
            spentTodayCents: TotalsEngine.spendTotalCents(
                transactions: input.transactions, in: today, asOf: now
            ),
            postedTodayCount: postedToday.count,
            dueSoon: dueSoon(input, now: now, calendar: calendar),
            missedPayments: missedPayments(input, now: now, calendar: calendar),
            upcomingCharges: upcomingCharges(input, now: now, calendar: calendar),
            endingSoon: endingSoon(input, now: now, calendar: calendar),
            unassignedEntries: unassignedEntries(input)
        )
    }

    /// Card statements inside their reminder window, or already overdue.
    /// - Parameters:
    ///   - input: The digest inputs.
    ///   - now: The moment to evaluate against.
    ///   - calendar: The calendar deciding day boundaries.
    /// - Returns: The items, soonest due first.
    static func dueSoon(
        _ input: TodayInput,
        now: Date,
        calendar: Calendar
    ) -> [DueStatementItem] {
        let accountsByID = Dictionary(uniqueKeysWithValues: input.accounts.map { ($0.id, $0) })
        guard let horizon = calendar.date(
            byAdding: .day, value: cardReminderLeadDays, to: now
        ) else { return [] }

        // Only the newest closed statement per card is actually due: earlier ones
        // roll up into it, so listing them all would show the same debt twice (§4.6).
        let newestPerCard = Dictionary(
            grouping: input.statements.filter(\.isPeriodClosed),
            by: { $0.accountID }
        ).values.compactMap { $0.max { $0.closingDate < $1.closingDate } }

        return newestPerCard
            .filter { $0.dueDate <= horizon }
            .compactMap { statement -> DueStatementItem? in
                guard let accountID = statement.accountID,
                      let account = accountsByID[accountID],
                      !account.isClosed,
                      account.remindBeforeDueDate else { return nil }
                let cardTransactions = input.transactions.filter { $0.accountID == accountID }
                let outstanding = StatementEngine.remainingCents(
                    of: statement, transactions: cardTransactions
                )
                guard outstanding > 0 else { return nil }
                return DueStatementItem(
                    statement: statement,
                    accountName: account.name,
                    paidCents: StatementEngine.settledCents(
                        of: statement, transactions: cardTransactions
                    ),
                    outstandingCents: outstanding,
                    daysRemaining: days(from: now, to: statement.dueDate, calendar: calendar)
                )
            }
            .sorted { $0.statement.dueDate < $1.statement.dueDate }
    }

    /// The next occurrence of each active rule within the horizon.
    /// - Parameters:
    ///   - input: The digest inputs.
    ///   - now: The moment to evaluate against.
    ///   - calendar: The calendar deciding day boundaries.
    /// - Returns: The items, soonest first.
    static func upcomingCharges(
        _ input: TodayInput,
        now: Date,
        calendar: Calendar
    ) -> [UpcomingChargeItem] {
        let accountsByID = Dictionary(uniqueKeysWithValues: input.accounts.map { ($0.id, $0) })
        guard let horizon = calendar.date(
            byAdding: .day, value: upcomingHorizonDays, to: now
        ) else { return [] }

        return input.rules
            .filter(\.isActive)
            .compactMap { rule -> UpcomingChargeItem? in
                let pending = input.transactions
                    .filter { $0.recurringRuleID == rule.id && $0.date > now }
                    .min { $0.date < $1.date }
                guard let date = pending?.date, date <= horizon else { return nil }
                let name = rule.accountID.flatMap { accountsByID[$0]?.name } ?? ""
                return UpcomingChargeItem(rule: rule, accountName: name, date: date)
            }
            .sorted { $0.date < $1.date }
    }

    /// Trials and warranties approaching expiry, within their own lead times.
    /// - Parameters:
    ///   - input: The digest inputs.
    ///   - now: The moment to evaluate against.
    ///   - calendar: The calendar deciding day boundaries.
    /// - Returns: The items, soonest first.
    static func endingSoon(
        _ input: TodayInput,
        now: Date,
        calendar: Calendar
    ) -> [EndingSoonItem] {
        input.products.flatMap { item -> [EndingSoonItem] in
            var results: [EndingSoonItem] = []
            if item.hasTrial, let date = item.trialEndsDate,
               let entry = endingItem(
                   EndingCandidate(
                       item: item, kind: .trial, date: date, lead: item.trialReminderLeadTime
                   ),
                   defaultLead: input.defaultLeadTime, now: now, calendar: calendar
               ) {
                results.append(entry)
            }
            if item.hasWarranty, let date = item.warrantyExpiresDate,
               let entry = endingItem(
                   EndingCandidate(
                       item: item, kind: .warranty, date: date,
                       lead: item.warrantyReminderLeadTime
                   ),
                   defaultLead: input.defaultLeadTime, now: now, calendar: calendar
               ) {
                results.append(entry)
            }
            return results
        }
        .sorted { $0.date < $1.date }
    }

    /// One candidate expiry date on a product.
    private struct EndingCandidate {
        /// The product.
        let item: Product
        /// Which date is ending.
        let kind: EndingSoonItem.Kind
        /// When it ends.
        let date: Date
        /// That date's own lead time.
        let lead: ReminderLeadTime
    }

    /// Builds one ending-soon entry if the date falls inside its lead window.
    /// - Parameters:
    ///   - candidate: The expiry date being considered.
    ///   - defaultLead: The fallback lead time for ``ReminderLeadTime/useDefault``.
    ///   - now: The moment to evaluate against.
    ///   - calendar: The calendar deciding day boundaries.
    /// - Returns: The entry, or `nil` when out of window or reminders are off.
    private static func endingItem(
        _ candidate: EndingCandidate,
        defaultLead: ReminderLeadTime,
        now: Date,
        calendar: Calendar
    ) -> EndingSoonItem? {
        let (item, kind, date, lead) = (
            candidate.item, candidate.kind, candidate.date, candidate.lead
        )
        let resolved = lead == .useDefault ? defaultLead : lead
        guard let leadDays = resolved.leadDays,
              let horizon = calendar.date(byAdding: .day, value: leadDays, to: now),
              date <= horizon,
              date >= calendar.startOfDay(for: now) else { return nil }
        return EndingSoonItem(
            item: item, kind: kind, date: date,
            daysRemaining: days(from: now, to: date, calendar: calendar)
        )
    }

    /// Whole days between two moments, by calendar day.
    /// - Parameters:
    ///   - start: The earlier moment.
    ///   - end: The later moment.
    ///   - calendar: The calendar deciding day boundaries.
    /// - Returns: The day count, negative when `end` is in the past.
    static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: start),
            to: calendar.startOfDay(for: end)
        ).day ?? 0
    }

    /// The inclusive range covering one calendar day.
    /// - Parameters:
    ///   - date: Any moment inside the day.
    ///   - calendar: The calendar deciding day boundaries.
    /// - Returns: From the day's first instant to its last.
    private static func dayRange(containing date: Date, calendar: Calendar) -> ClosedRange<Date> {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        return start...end.addingTimeInterval(-0.001)
    }
}

/// Lead times expressed in days (§10).
extension ReminderLeadTime {
    /// How many days before the date a reminder fires, or `nil` when off.
    ///
    /// ``useDefault`` returns `nil` here: it means "use the setting", and is resolved
    /// against ``AppSettings/defaultReminderLeadTime`` before this is read.
    public var leadDays: Int? {
        switch self {
        case .useDefault, .off: return nil
        case .sameDay: return 0
        case .oneDayBefore: return 1
        case .threeDaysBefore: return 3
        case .oneWeekBefore: return 7
        }
    }
}
