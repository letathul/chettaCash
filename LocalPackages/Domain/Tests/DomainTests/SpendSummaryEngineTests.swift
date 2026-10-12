import Foundation
import Testing
@testable import Domain

/// The Dashboard's expense-only month figures (§7.1).
@Suite("Spend summary")
struct SpendSummaryEngineTests {

    /// A fixed UTC calendar, so results never depend on the runner's locale.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// The moment the summaries are read at: 12 October 2026, midday.
    private var now: Date { date(2026, 10, 12) }

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
    ///   - when: The date.
    ///   - category: The category, if any.
    ///   - account: The account, if any.
    ///   - receipt: Whether a receipt is attached.
    /// - Returns: The transaction.
    private func expense(
        _ cents: Int,
        _ when: Date,
        category: UUID? = nil,
        account: UUID? = nil,
        receipt: Bool = false
    ) -> Transaction {
        Transaction(
            amountCents: cents, type: .expense, categoryID: category, accountID: account,
            date: when, merchant: "Shop", receiptFileID: receipt ? "r" : nil
        )
    }

    /// Summarises with the fixed clock and calendar.
    /// - Parameters:
    ///   - transactions: Every transaction.
    ///   - products: Every product.
    ///   - rules: Every rule.
    /// - Returns: The summary.
    private func summarise(
        _ transactions: [Transaction],
        products: [Product] = [],
        rules: [RecurringRule] = []
    ) -> SpendSummary {
        SpendSummaryEngine.summary(
            transactions: transactions, products: products, rules: rules,
            reference: now, calendar: calendar
        )
    }

    @Test("Month spend counts posted expenses from the first of the month")
    func monthSpend() {
        let summary = summarise([
            expense(1_000, date(2026, 10, 1)),
            expense(2_500, date(2026, 10, 11)),
            expense(9_999, date(2026, 9, 30)),
            expense(7_000, date(2026, 10, 20))
        ])

        #expect(summary.monthSpendCents == 3_500)
        #expect(summary.transactionCount == 2)
    }

    @Test("Income, transfers and adjustments are not spending")
    func exclusions() {
        let income = Transaction(amountCents: 500_000, type: .income, date: date(2026, 10, 2))
        let transfer = Transaction(
            amountCents: 40_000, type: .transferOut, date: date(2026, 10, 3),
            transferGroupID: UUID()
        )
        let adjustment = Transaction(
            amountCents: 100, type: .adjustment, signedOverrideCents: -100,
            date: date(2026, 10, 4)
        )

        let summary = summarise([income, transfer, adjustment, expense(1_200, date(2026, 10, 5))])

        #expect(summary.monthSpendCents == 1_200)
        #expect(summary.transactionCount == 1)
    }

    @Test("The comparison stops at the same point last month")
    func previousMonthToDate() {
        let summary = summarise([
            expense(1_000, date(2026, 9, 3)),
            expense(2_000, date(2026, 9, 12)),
            expense(50_000, date(2026, 9, 20)),
            expense(4_000, date(2026, 10, 4))
        ])

        #expect(summary.previousMonthToDateCents == 3_000)
        #expect(summary.deltaAgainstPreviousCents == 1_000)
    }

    @Test("Running totals cover each day so far and each day of last month")
    func cumulativeSeries() {
        let summary = summarise([
            expense(1_000, date(2026, 10, 1)),
            expense(500, date(2026, 10, 3)),
            expense(700, date(2026, 9, 2))
        ])

        #expect(summary.cumulativeThisMonth.count == 12)
        #expect(summary.cumulativeThisMonth.first == 1_000)
        #expect(summary.cumulativeThisMonth.last == 1_500)
        #expect(summary.cumulativePreviousMonth.count == 30)
        #expect(summary.cumulativePreviousMonth.last == 700)
    }

    @Test("The largest purchase is the biggest single expense this month")
    func largestPurchase() {
        let summary = summarise([
            expense(1_000, date(2026, 10, 1)),
            expense(21_200, date(2026, 10, 4)),
            expense(90_000, date(2026, 9, 4))
        ])

        #expect(summary.largestPurchaseCents == 21_200)
        #expect(summary.largestPurchaseDate == date(2026, 10, 4))
    }

    @Test("Receipts split priced purchases into attached and missing")
    func receipts() {
        let summary = summarise([
            expense(1_000, date(2026, 10, 1), receipt: true),
            expense(2_000, date(2026, 10, 2), receipt: true),
            expense(3_000, date(2026, 10, 3)),
            expense(0, date(2026, 10, 4))
        ])

        #expect(summary.receiptsAttached == 2)
        #expect(summary.receiptsMissing == 1, "a zero-cent entry is not a purchase to document")
    }

    @Test("Products are counted by the purchases they belong to, free ones included")
    func products() {
        let paid = expense(5_000, date(2026, 10, 2))
        let free = expense(0, date(2026, 10, 3))
        let old = expense(5_000, date(2026, 9, 2))
        let items = [
            Product(transactionID: paid.id, name: "A"),
            Product(transactionID: paid.id, name: "B"),
            Product(transactionID: free.id, name: "C"),
            Product(transactionID: old.id, name: "D")
        ]

        let summary = summarise([paid, free, old], products: items)

        #expect(summary.productCount == 3)
        #expect(summary.purchaseWithProductsCount == 2)
    }

    @Test("Subscriptions are normalised to a monthly cost")
    func subscriptions() {
        var inactive = RecurringRule(name: "Gym", amountCents: 9_900)
        inactive.isActive = false
        let rules = [
            RecurringRule(name: "Music", amountCents: 1_099, frequency: .monthly),
            RecurringRule(name: "Cloud", amountCents: 12_000, frequency: .yearly),
            RecurringRule(name: "Paper", amountCents: 300, frequency: .weekly),
            inactive
        ]

        let summary = summarise([], rules: rules)

        #expect(summary.subscriptionCount == 3)
        // 1,099 + 12,000 / 12 + 300 × 52 / 12 = 1,099 + 1,000 + 1,300
        #expect(summary.subscriptionMonthlyCents == 3_399)
    }

    @Test("Categories and accounts are ranked largest first")
    func rankings() {
        let food = UUID()
        let fun = UUID()
        let checking = UUID()
        let card = UUID()

        let summary = summarise([
            expense(1_000, date(2026, 10, 1), category: fun, account: checking),
            expense(4_000, date(2026, 10, 2), category: food, account: card),
            expense(2_000, date(2026, 10, 3), category: food, account: checking),
            expense(500, date(2026, 10, 4))
        ])

        #expect(summary.byCategory.map(\.cents) == [6_000, 1_000, 500])
        #expect(summary.byCategory.first?.categoryID == food)
        #expect(summary.byCategory.last?.categoryID == nil)
        #expect(summary.byAccount.map(\.cents) == [4_000, 3_000, 500])
        #expect(summary.byAccount.first?.accountID == card)
    }

    @Test("Due within the window counts upcoming statements and charges, not overdue ones")
    func dueWithin() {
        let rule = RecurringRule(name: "Music", amountCents: 1_099)
        let digest = TodayDigest(
            dueSoon: [
                DueStatementItem(
                    statement: CardStatement(
                        periodStart: now, closingDate: now, dueDate: now
                    ),
                    accountName: "Amex", paidCents: 0, outstandingCents: 19_090,
                    daysRemaining: 3
                ),
                DueStatementItem(
                    statement: CardStatement(
                        periodStart: now, closingDate: now, dueDate: now
                    ),
                    accountName: "Visa", paidCents: 0, outstandingCents: 72_435,
                    daysRemaining: -4
                )
            ],
            upcomingCharges: [
                UpcomingChargeItem(
                    rule: rule, accountName: "Checking", date: now.addingTimeInterval(2 * 86_400)
                ),
                UpcomingChargeItem(
                    rule: rule, accountName: "Checking", date: now.addingTimeInterval(20 * 86_400)
                )
            ]
        )

        let total = SpendSummaryEngine.dueWithinCents(digest: digest, days: 7, reference: now)

        #expect(total == 19_090 + 1_099)
    }

    @Test("A month with nothing in it is all zeros")
    func emptyMonth() {
        let summary = summarise([])

        #expect(summary.monthSpendCents == 0)
        #expect(summary.largestPurchaseCents == 0)
        #expect(summary.byCategory.isEmpty)
    }
}
