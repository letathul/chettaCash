import Foundation

/// How much one category took out of the month.
public struct CategorySpend: Identifiable, Equatable, Sendable {
    /// The category, or `nil` for spending that has none.
    public let categoryID: UUID?
    /// The total in cents, always positive.
    public let cents: Int

    /// The row's identity.
    public var id: UUID? { categoryID }

    /// Creates a row.
    /// - Parameters:
    ///   - categoryID: The category, or `nil` when uncategorised.
    ///   - cents: The total in cents.
    public init(categoryID: UUID?, cents: Int) {
        self.categoryID = categoryID
        self.cents = cents
    }
}

/// How much went through one account in the month.
public struct AccountSpend: Identifiable, Equatable, Sendable {
    /// The account, or `nil` for entries still waiting for one (§15.5).
    public let accountID: UUID?
    /// The total in cents, always positive.
    public let cents: Int

    /// The row's identity.
    public var id: UUID? { accountID }

    /// Creates a row.
    /// - Parameters:
    ///   - accountID: The account, or `nil` when unassigned.
    ///   - cents: The total in cents.
    public init(accountID: UUID?, cents: Int) {
        self.accountID = accountID
        self.cents = cents
    }
}

/// The Dashboard's expense figures for the current month.
///
/// Every number here is derived from expenses alone. Nothing depends on income having
/// been logged, so the Dashboard reads correctly for someone who only tracks spending.
public struct SpendSummary: Equatable, Sendable {
    /// Posted expenses so far this month, in cents.
    public var monthSpendCents = 0
    /// What was spent by the same point last month, in cents.
    public var previousMonthToDateCents = 0
    /// Running spend at the end of each day this month, day one first.
    public var cumulativeThisMonth: [Int] = []
    /// Running spend at the end of each day of last month, day one first.
    public var cumulativePreviousMonth: [Int] = []
    /// How many priced expenses were posted this month.
    public var transactionCount = 0
    /// The largest single expense this month, in cents.
    public var largestPurchaseCents = 0
    /// The merchant of that expense, empty when it had none.
    public var largestPurchaseMerchant = ""
    /// The date of that expense.
    public var largestPurchaseDate: Date?
    /// How many of this month's priced expenses have a receipt.
    public var receiptsAttached = 0
    /// How many of this month's priced expenses have none.
    public var receiptsMissing = 0
    /// How many products this month's purchases contained.
    public var productCount = 0
    /// How many purchases those products came from.
    public var purchaseWithProductsCount = 0
    /// What the active subscriptions cost per month, in cents.
    public var subscriptionMonthlyCents = 0
    /// How many subscriptions are active.
    public var subscriptionCount = 0
    /// This month's spending by category, largest first.
    public var byCategory: [CategorySpend] = []
    /// This month's spending by account, largest first.
    public var byAccount: [AccountSpend] = []

    /// Spend this month minus spend by the same point last month.
    public var deltaAgainstPreviousCents: Int { monthSpendCents - previousMonthToDateCents }

    /// Creates an empty summary.
    public init() {}
}

/// Builds the ``SpendSummary`` the Dashboard shows.
///
/// The usual exclusions apply (§4.2, §4.3, §4.4): unposted entries are inert, and
/// transfers and adjustments are not spending. Income is ignored entirely.
public enum SpendSummaryEngine {

    /// Summarises the month containing `reference`.
    ///
    /// - Parameters:
    ///   - transactions: Every transaction.
    ///   - products: Every product.
    ///   - rules: Every recurring rule.
    ///   - reference: The moment the month is read at. Defaults to now.
    ///   - calendar: The calendar deciding month boundaries.
    /// - Returns: The summary, or an empty one when the calendar cannot place `reference`.
    public static func summary(
        transactions: [Transaction],
        products: [Product],
        rules: [RecurringRule],
        reference: Date = .now,
        calendar: Calendar = .current
    ) -> SpendSummary {
        guard let month = calendar.dateInterval(of: .month, for: reference),
              let previousStart = calendar.date(byAdding: .month, value: -1, to: month.start),
              let previousCutoff = calendar.date(byAdding: .month, value: -1, to: reference)
        else { return SpendSummary() }

        let expenses = transactions.filter {
            TotalsEngine.countsTowardTotals($0, asOf: reference) && $0.type == .expense
        }
        let thisMonth = expenses.filter { $0.date >= month.start && $0.date <= reference }
        let lastMonth = expenses.filter { $0.date >= previousStart && $0.date < month.start }

        var summary = SpendSummary()
        // A zero-cent entry exists to hold a free product (§7.8). It moves no total and
        // is not a purchase worth a receipt, but its products still count.
        let priced = thisMonth.filter { $0.amountCents > 0 }

        summary.monthSpendCents = priced.reduce(0) { $0 + $1.amountCents }
        summary.previousMonthToDateCents = lastMonth
            .filter { $0.date <= previousCutoff }
            .reduce(0) { $0 + $1.amountCents }
        summary.cumulativeThisMonth = cumulative(
            thisMonth, days: calendar.component(.day, from: reference), calendar: calendar
        )
        summary.cumulativePreviousMonth = cumulative(
            lastMonth,
            days: calendar.range(of: .day, in: .month, for: previousStart)?.count ?? 0,
            calendar: calendar
        )

        summary.transactionCount = priced.count
        if let largest = priced.max(by: { $0.amountCents < $1.amountCents }) {
            summary.largestPurchaseCents = largest.amountCents
            summary.largestPurchaseMerchant = largest.merchant
            summary.largestPurchaseDate = largest.date
        }
        summary.receiptsAttached = priced.filter { $0.receiptFileID != nil }.count
        summary.receiptsMissing = priced.count - summary.receiptsAttached

        applyProducts(products, purchases: thisMonth, to: &summary)
        applySubscriptions(rules, to: &summary)

        summary.byCategory = ranked(priced, by: \.categoryID).map {
            CategorySpend(categoryID: $0.key, cents: $0.cents)
        }
        summary.byAccount = ranked(priced, by: \.accountID).map {
            AccountSpend(accountID: $0.key, cents: $0.cents)
        }
        return summary
    }

    /// Totals what is about to leave within a number of days.
    ///
    /// Counts card statements due in the window and subscription charges landing in it.
    /// A statement already past due is reported separately, so it is left out here.
    ///
    /// - Parameters:
    ///   - digest: What the Today card reports.
    ///   - days: The length of the window, counting today.
    ///   - reference: The moment the window starts. Defaults to now.
    /// - Returns: The total in cents.
    public static func dueWithinCents(
        digest: TodayDigest,
        days: Int,
        reference: Date = .now
    ) -> Int {
        let statements = digest.dueSoon
            .filter { !$0.isOverdue && $0.daysRemaining <= days }
            .reduce(0) { $0 + $1.outstandingCents }
        let cutoff = reference.addingTimeInterval(Double(days) * 86_400)
        let charges = digest.upcomingCharges
            .filter { $0.date <= cutoff }
            .reduce(0) { $0 + $1.rule.amountCents }
        return statements + charges
    }

    /// Counts the products this month's purchases contained.
    /// - Parameters:
    ///   - products: Every product.
    ///   - purchases: This month's posted expenses, free ones included.
    ///   - summary: The summary to fill in.
    private static func applyProducts(
        _ products: [Product],
        purchases: [Transaction],
        to summary: inout SpendSummary
    ) {
        let purchaseIDs = Set(purchases.map(\.id))
        let monthProducts = products.filter { purchaseIDs.contains($0.transactionID) }
        summary.productCount = monthProducts.count
        summary.purchaseWithProductsCount = Set(monthProducts.map(\.transactionID)).count
    }

    /// Totals what the active subscriptions cost per month.
    /// - Parameters:
    ///   - rules: Every recurring rule.
    ///   - summary: The summary to fill in.
    private static func applySubscriptions(_ rules: [RecurringRule], to summary: inout SpendSummary) {
        let subscriptions = rules.filter { $0.isActive && $0.type == .expense }
        summary.subscriptionCount = subscriptions.count
        summary.subscriptionMonthlyCents = subscriptions.reduce(0) {
            $0 + monthlyCents(amountCents: $1.amountCents, frequency: $1.frequency)
        }
    }

    /// Converts a recurring amount to its cost per month.
    /// - Parameters:
    ///   - amountCents: The amount charged each time.
    ///   - frequency: How often it is charged.
    /// - Returns: The monthly cost in cents, rounded to the nearest cent.
    static func monthlyCents(amountCents: Int, frequency: RecurringFrequency) -> Int {
        switch frequency {
        case .weekly: return (amountCents * 52 * 2 + 12) / 24
        case .biweekly: return (amountCents * 26 * 2 + 12) / 24
        case .monthly: return amountCents
        case .yearly: return (amountCents * 2 + 12) / 24
        }
    }

    /// Builds running totals by day of month.
    /// - Parameters:
    ///   - transactions: The expenses to total, all within one month.
    ///   - days: How many days to cover.
    ///   - calendar: The calendar deciding the day of month.
    /// - Returns: The running total at the end of each day, day one first.
    private static func cumulative(
        _ transactions: [Transaction],
        days: Int,
        calendar: Calendar
    ) -> [Int] {
        guard days > 0 else { return [] }
        var daily = [Int](repeating: 0, count: days)
        for transaction in transactions {
            let index = calendar.component(.day, from: transaction.date) - 1
            if daily.indices.contains(index) { daily[index] += transaction.amountCents }
        }
        var running = 0
        return daily.map { amount in
            running += amount
            return running
        }
    }

    /// One group's total.
    private struct Group {
        /// The grouping key.
        let key: UUID?
        /// The group's total in cents.
        let cents: Int
    }

    /// Groups expenses by an optional identifier, largest group first.
    /// - Parameters:
    ///   - transactions: The expenses to group.
    ///   - keyPath: Which identifier to group by.
    /// - Returns: The groups, ties broken by identifier so the order is stable.
    private static func ranked(
        _ transactions: [Transaction],
        by keyPath: KeyPath<Transaction, UUID?>
    ) -> [Group] {
        var totals: [UUID?: Int] = [:]
        for transaction in transactions {
            totals[transaction[keyPath: keyPath], default: 0] += transaction.amountCents
        }
        return totals
            .map { Group(key: $0.key, cents: $0.value) }
            .sorted {
                if $0.cents != $1.cents { return $0.cents > $1.cents }
                return ($0.key?.uuidString ?? "") < ($1.key?.uuidString ?? "")
            }
    }
}
