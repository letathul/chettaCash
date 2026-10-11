import Foundation
import Testing
@testable import Features
import Domain

/// The focused-account setting, the Today/Recent fallback, and the hero card's
/// category insight (§7.1). Split from ``DashboardViewModelTests`` to keep each file
/// within the 300-line limit.
@MainActor
@Suite("Dashboard focus and insights")
struct DashboardFocusInsightsTests {

    /// The pieces under test, wired together.
    private struct Harness {
        /// The account repository fake.
        let accounts: FakeAccountRepository
        /// The transaction repository fake.
        let transactions: FakeTransactionRepository
        /// The category repository fake.
        let categories: FakeCategoryRepository
        /// The view model under test.
        let model: DashboardViewModel
        /// A spending account.
        let chequing: Domain.Account
        /// A credit card.
        let card: Domain.Account
    }

    /// Builds a loaded view model with one account and one card.
    /// - Returns: The harness.
    private func makeHarness() async -> Harness {
        let accounts = FakeAccountRepository()
        let transactions = FakeTransactionRepository(accounts: accounts)
        let categories = FakeCategoryRepository()
        let chequing = Domain.Account(
            name: "Chequing", openingBalanceCents: 500_000,
            openingBalanceDate: .now.addingTimeInterval(-200 * 86_400)
        )
        let card = Domain.Account(
            name: "Visa", kind: .card, openingBalanceCents: -120_000,
            openingBalanceDate: .now.addingTimeInterval(-200 * 86_400),
            statementDayOfMonth: 5, paymentDueDayOfMonth: 25
        )
        try? await accounts.save(chequing)
        try? await accounts.save(card)
        let model = DashboardViewModel(
            accountRepository: accounts,
            transactionRepository: transactions,
            categoryRepository: categories,
            recurringRuleRepository: FakeRecurringRuleRepository(),
            statementRepository: FakeCardStatementRepository(),
            productRepository: FakeProductRepository(),
            settings: AppSettings()
        )
        await model.load()
        return Harness(
            accounts: accounts, transactions: transactions, categories: categories,
            model: model, chequing: chequing, card: card
        )
    }

    /// Today, at midnight — always inside the current month and always posted.
    private var thisMonth: Date { Calendar.current.startOfDay(for: .now) }

    /// The same day one calendar month back, so it always lands in the prior month.
    private var lastMonth: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth
    }

    // MARK: - Focused account

    @Test("Focusing an account scopes the headline figures to it alone")
    func focusingAnAccountScopesFigures() async {
        let harness = await makeHarness()

        harness.model.setFocusedAccount(harness.chequing.id)

        #expect(harness.model.availableCashCents == 500_000, "the card contributes nothing")
        #expect(harness.model.netWorthCents == 500_000, "scoped to the chequing account alone")
        #expect(harness.model.displayedAccounts.map(\.id) == [harness.chequing.id])
        #expect(harness.model.openAccounts.count == 2, "the picker still offers every account")
    }

    @Test("Focusing on a closed or unknown account behaves like no focus")
    func focusingAnInvalidAccountFallsBackToAll() async {
        let harness = await makeHarness()

        harness.model.setFocusedAccount(UUID())

        #expect(harness.model.availableCashCents == 500_000)
        #expect(harness.model.netWorthCents == 380_000)
        #expect(harness.model.displayedAccounts.map(\.id) == harness.model.openAccounts.map(\.id))
    }

    @Test("Clearing the focus returns to every account")
    func clearingFocusReturnsToEveryAccount() async {
        let harness = await makeHarness()
        harness.model.setFocusedAccount(harness.chequing.id)

        harness.model.setFocusedAccount(nil)

        #expect(harness.model.netWorthCents == 380_000)
        #expect(harness.model.displayedAccounts.count == 2)
    }

    // MARK: - Today, falling back to Recent

    @Test("A transaction posted today takes over the Recent section")
    func todaysTransactionsReplaceRecent() async {
        let harness = await makeHarness()
        try? await harness.transactions.save(Domain.Transaction(
            amountCents: 625, type: .expense, accountID: harness.chequing.id,
            date: .now, merchant: "Blue Bottle Coffee"
        ))
        await harness.model.load()

        #expect(harness.model.recentSectionTitle == "Today")
        #expect(harness.model.recentRows.map(\.title) == ["Blue Bottle Coffee"])
        #expect(harness.model.recentTransactions.isEmpty, "Today rows come from recentRows instead")
    }

    @Test("With nothing posted today, Recent falls back to the most recent transactions")
    func recentFallsBackWhenTodayIsQuiet() async {
        let harness = await makeHarness()
        try? await harness.transactions.save(Domain.Transaction(
            amountCents: 4_500, type: .expense, accountID: harness.chequing.id,
            date: .now.addingTimeInterval(-3 * 86_400), merchant: "Whole Foods"
        ))
        await harness.model.load()

        #expect(harness.model.recentSectionTitle == "Recent")
        #expect(harness.model.recentRows.map(\.title) == ["Whole Foods"])
    }

    // MARK: - Insights

    @Test("A category spending more than last month drives the hero card's insight")
    func categoryRiseDrivesTheHeroInsight() async {
        let harness = await makeHarness()
        let food = Domain.Category(label: "Food & drink", context: .expense, isBuiltIn: true)
        try? await harness.categories.save(food)
        try? await harness.transactions.save(Domain.Transaction(
            amountCents: 20_000, type: .expense, categoryID: food.id,
            accountID: harness.chequing.id, date: lastMonth
        ))
        try? await harness.transactions.save(Domain.Transaction(
            amountCents: 40_000, type: .expense, categoryID: food.id,
            accountID: harness.chequing.id, date: thisMonth
        ))
        await harness.model.load()

        let insight = harness.model.heroPages.first?.insight
        #expect(insight?.isFavourable == false)
        #expect(insight?.glyph == "flame.fill")
        #expect(insight?.message == "Food & drink is up 100% ($200.00) this month")
    }

    @Test("No insight is produced without a prior month to compare against")
    func noInsightWithoutHistory() async {
        let harness = await makeHarness()

        let anyInsight = harness.model.heroPages.contains { $0.insight != nil }
        #expect(anyInsight == false)
    }

    @Test("An account's page carries only its own account's insight")
    func insightIsScopedToItsPage() async {
        let harness = await makeHarness()
        let food = Domain.Category(label: "Food & drink", context: .expense, isBuiltIn: true)
        try? await harness.categories.save(food)
        try? await harness.transactions.save(Domain.Transaction(
            amountCents: 20_000, type: .expense, categoryID: food.id,
            accountID: harness.chequing.id, date: lastMonth
        ))
        try? await harness.transactions.save(Domain.Transaction(
            amountCents: 40_000, type: .expense, categoryID: food.id,
            accountID: harness.chequing.id, date: thisMonth
        ))
        await harness.model.load()

        let cardPage = harness.model.heroPages.first { $0.accountID == harness.card.id }
        #expect(cardPage?.insight == nil, "the spending happened on the chequing account")
    }
}
