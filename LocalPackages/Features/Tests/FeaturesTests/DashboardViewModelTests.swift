import Foundation
import Testing
@testable import Features
import Domain

/// Phase 8 acceptance criteria end to end: the headline figures match hand
/// calculation, and the Today card goes quiet when nothing needs attention (§7.1, §7.2).
@MainActor
@Suite("Dashboard")
struct DashboardViewModelTests {

    /// The pieces under test, wired together.
    private struct Harness {
        /// The account repository fake.
        let accounts: FakeAccountRepository
        /// The transaction repository fake.
        let transactions: FakeTransactionRepository
        /// The rule repository fake.
        let rules: FakeRecurringRuleRepository
        /// The statement repository fake.
        let statements: FakeCardStatementRepository
        /// The product repository fake.
        let products: FakeProductRepository
        /// The view model under test.
        let model: DashboardViewModel
        /// A spending account.
        let chequing: Domain.Account
        /// A credit card.
        let card: Domain.Account
    }

    /// Builds a loaded view model with one account and one card.
    /// - Parameter includeAccounts: Whether to seed any accounts at all.
    /// - Returns: The harness.
    private func makeHarness(includeAccounts: Bool = true) async -> Harness {
        let accounts = FakeAccountRepository()
        let transactions = FakeTransactionRepository(accounts: accounts)
        let categories = FakeCategoryRepository()
        let rules = FakeRecurringRuleRepository()
        let statements = FakeCardStatementRepository()
        let products = FakeProductRepository()
        let chequing = Domain.Account(
            name: "Chequing", openingBalanceCents: 500_000,
            openingBalanceDate: .now.addingTimeInterval(-200 * 86_400)
        )
        let card = Domain.Account(
            name: "Visa", kind: .card, openingBalanceCents: -120_000,
            openingBalanceDate: .now.addingTimeInterval(-200 * 86_400),
            statementDayOfMonth: 5, paymentDueDayOfMonth: 25
        )
        if includeAccounts {
            try? await accounts.save(chequing)
            try? await accounts.save(card)
        }
        let model = DashboardViewModel(
            accountRepository: accounts,
            transactionRepository: transactions,
            categoryRepository: categories,
            recurringRuleRepository: rules,
            statementRepository: statements,
            productRepository: products,
            settings: AppSettings()
        )
        await model.load()
        return Harness(
            accounts: accounts, transactions: transactions, rules: rules,
            statements: statements, products: products, model: model,
            chequing: chequing, card: card
        )
    }

    // MARK: - Parked entries (§15.5)

    @Test("A parked entry is offered with the open accounts it can be filed into")
    func offersOnlyOpenAccounts() async throws {
        let harness = await makeHarness()
        var closed = harness.card
        closed.isClosed = true
        closed.closedDate = .now
        try await harness.accounts.save(closed)
        try await harness.transactions.save(parkedExpense())
        await harness.model.load()

        #expect(harness.model.digest.unassignedEntries.count == 1)
        #expect(
            harness.model.assignableAccounts.map(\.id) == [harness.chequing.id],
            "a closed account is kept for history, not for money that has been waiting"
        )
    }

    @Test("Filing a parked entry moves the balance it was always going to move")
    func assigningMovesTheBalance() async throws {
        let harness = await makeHarness()
        try await harness.transactions.save(parkedExpense())
        await harness.model.load()
        let before = availableCash(harness.model)
        let item = try #require(harness.model.digest.unassignedEntries.first)

        await harness.model.assign(item, to: harness.chequing.id)

        #expect(before == 500_000, "a parked entry charges nobody")
        #expect(availableCash(harness.model) == 500_000 - 4_210)
        #expect(
            harness.model.digest.unassignedEntries.isEmpty,
            "and it leaves the Today card once it is filed"
        )
    }

    /// An expense with no account, as a Shortcut parks one.
    /// - Returns: The transaction.
    private func parkedExpense() -> Domain.Transaction {
        Domain.Transaction(
            amountCents: 4_210, type: .expense, accountID: nil,
            date: .now.addingTimeInterval(-3_600), merchant: "Whole Foods"
        )
    }

    /// Spendable cash across the model's accounts, for tests of balance movement.
    /// - Parameter model: The loaded view model.
    /// - Returns: The sum of open spending accounts, in cents.
    private func availableCash(_ model: DashboardViewModel) -> Int {
        BalanceEngine.availableCashCents(
            accounts: model.accounts, transactions: model.transactions
        )
    }

    @Test("The month's spend counts posted expenses and ignores income")
    func monthSpendIgnoresIncome() async {
        let harness = await makeHarness()

        try? await harness.transactions.save(Domain.Transaction(
            amountCents: 4_500, type: .expense, accountID: harness.chequing.id,
            date: .now.addingTimeInterval(-60)
        ))
        try? await harness.transactions.save(Domain.Transaction(
            amountCents: 300_000, type: .income, accountID: harness.chequing.id,
            date: .now.addingTimeInterval(-60)
        ))
        await harness.model.load()

        #expect(harness.model.spendSummary.monthSpendCents == 4_500)
        #expect(harness.model.spendSummary.transactionCount == 1)
    }

    @Test("Spent by account lists each account that took spending, largest first")
    func spendByAccount() async {
        let harness = await makeHarness()
        for (cents, account) in [(1_000, harness.chequing), (7_000, harness.card)] {
            try? await harness.transactions.save(Domain.Transaction(
                amountCents: cents, type: .expense, accountID: account.id,
                date: .now.addingTimeInterval(-60)
            ))
        }
        await harness.model.load()

        #expect(harness.model.accountSpendRows.map(\.name) == ["Visa", "Chequing"])
        #expect(harness.model.accountSpendRows.map(\.spendCents) == [7_000, 1_000])
    }

    @Test("A parked entry shows as spending with no account")
    func parkedEntryAppearsInAccountRows() async throws {
        let harness = await makeHarness()
        try await harness.transactions.save(parkedExpense())
        await harness.model.load()

        let parked = harness.model.accountSpendRows.first { $0.id == nil }
        let row = try #require(parked)
        #expect(row.name == "No account")
        #expect(row.spendCents == 4_210)
    }

    @Test("The empty state applies only when there are zero accounts")
    func emptyStateOnlyWithoutAccounts() async {
        let empty = await makeHarness(includeAccounts: false)
        let populated = await makeHarness()

        #expect(empty.model.hasNoAccounts)
        #expect(populated.model.hasNoAccounts == false)
    }

    @Test("A day with nothing happening is quiet")
    func quietDay() async {
        let harness = await makeHarness()

        #expect(harness.model.digest.isQuietDay)
    }

    @Test("Spending today ends the quiet day")
    func spendingEndsQuietDay() async {
        let harness = await makeHarness()

        try? await harness.transactions.save(Domain.Transaction(
            amountCents: 2_450, type: .expense, accountID: harness.chequing.id,
            date: .now.addingTimeInterval(-600)
        ))
        await harness.model.load()

        #expect(harness.model.digest.isQuietDay == false)
        #expect(harness.model.digest.spentTodayCents == 2_450)
    }

    @Test("The account strip shows open accounts only")
    func stripExcludesClosedAccounts() async {
        let harness = await makeHarness()
        var closed = harness.chequing
        closed.isClosed = true
        try? await harness.accounts.save(closed)
        await harness.model.load()

        #expect(harness.model.openAccounts.count == 1)
        #expect(harness.model.accounts.count == 2, "closed accounts stay in history")
    }

    @Test("Recent activity lists posted transactions newest first")
    func recentIsNewestFirst() async {
        let harness = await makeHarness()
        for days in [1, 3, 2] {
            try? await harness.transactions.save(Domain.Transaction(
                amountCents: 1_000 * days, type: .expense, accountID: harness.chequing.id,
                date: .now.addingTimeInterval(Double(-days) * 86_400),
                merchant: "Day \(days)"
            ))
        }
        await harness.model.load()

        #expect(harness.model.recentTransactions.map(\.merchant) == ["Day 1", "Day 2", "Day 3"])
    }

    @Test("Recent activity excludes future transactions")
    func recentExcludesFuture() async {
        let harness = await makeHarness()
        try? await harness.transactions.save(Domain.Transaction(
            amountCents: 9_000, type: .expense, accountID: harness.chequing.id,
            date: .now.addingTimeInterval(86_400 * 3), merchant: "Later"
        ))
        await harness.model.load()

        #expect(harness.model.recentTransactions.isEmpty)
    }

    @Test("Subscriptions list every active rule and only active ones")
    func subscriptionsListActiveRules() async {
        let harness = await makeHarness()
        let live = Domain.RecurringRule(
            name: "Streaming", amountCents: 999, accountID: harness.chequing.id
        )
        var ended = Domain.RecurringRule(name: "Gym", accountID: harness.chequing.id)
        ended.isActive = false
        try? await harness.rules.save(live)
        try? await harness.rules.save(ended)
        await harness.model.load()

        #expect(harness.model.activeSubscriptions.map(\.name) == ["Streaming"])
    }

    @Test("The spend trend covers six months and ends at this month's spend")
    func trendSeriesShape() async {
        let harness = await makeHarness()

        #expect(harness.model.spendTrend.points.count == 6)
        #expect(harness.model.spendTrend.currentCents == harness.model.spendSummary.monthSpendCents)
    }

    @Test("A load failure surfaces a retryable banner")
    func loadFailureShowsBanner() async {
        let harness = await makeHarness()
        harness.accounts.failure = URLError(.notConnectedToInternet)

        await harness.model.load()

        #expect(harness.model.errorMessage == "Could not load your dashboard.")
    }
}
