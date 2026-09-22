import Foundation
import Testing
@testable import Features
import Domain

/// Row content is built by the view model, not derived in the row's body (§7.4).
///
/// It moved there so a list body does no formatting or lookup work per frame. That also
/// makes it reachable from a test for the first time — these pin the strings the Ledger
/// actually renders, and the rebuild contract the caching depends on.
@MainActor
@Suite("Ledger row rendering")
struct LedgerRowModelTests {

    /// The pieces under test, wired together.
    private struct Harness {
        /// The view model under test.
        let model: LedgerViewModel
        /// A spending account.
        let chequing: Domain.Account
        /// A credit card.
        let visa: Domain.Account
        /// An expense category.
        let groceries: Domain.Category
        /// The shared preferences object.
        let settings: AppSettings
    }

    /// Builds a loaded view model with two accounts and one category.
    /// - Returns: The harness.
    private func makeHarness() async -> Harness {
        let accounts = FakeAccountRepository()
        let transactions = FakeTransactionRepository(accounts: accounts)
        let categories = FakeCategoryRepository()
        let chequing = Domain.Account(name: "Chequing", openingBalanceCents: 100_000)
        let visa = Domain.Account(name: "Visa", kind: .card, openingBalanceCents: -20_000)
        let groceries = Domain.Category(label: "Groceries", context: .expense)
        try? await accounts.save(chequing)
        try? await accounts.save(visa)
        try? await categories.save(groceries)
        let settings = AppSettings()
        let model = LedgerViewModel(
            transactionRepository: transactions,
            accountRepository: accounts,
            categoryRepository: categories,
            recurringRuleRepository: FakeRecurringRuleRepository(),
            settings: settings
        )
        await model.load()
        return Harness(
            model: model, chequing: chequing, visa: visa,
            groceries: groceries, settings: settings
        )
    }

    /// Saves one expense through the form.
    /// - Parameters:
    ///   - harness: The harness under test.
    ///   - merchant: The merchant name.
    ///   - amount: The typed amount.
    private func addExpense(
        _ harness: Harness, merchant: String, amount: String
    ) async {
        let form = TransactionFormState(accountID: harness.chequing.id)
        form.amountText = amount
        form.categoryID = harness.groceries.id
        form.merchant = merchant
        form.date = .now.addingTimeInterval(-3_600)
        await harness.model.save(form)
    }

    /// The one posted row, whichever day it landed on.
    /// - Parameter model: The view model to read.
    /// - Returns: The row, or `nil` when none posted.
    private func onlyPostedRow(_ model: LedgerViewModel) -> LedgerRowModel? {
        model.postedDays.flatMap(\.rows).first
    }

    @Test("An expense reads as merchant, Category · Account, and a negative amount")
    func expenseRowRenders() async {
        let harness = await makeHarness()
        await addExpense(harness, merchant: "Whole Foods", amount: "60.00")

        let row = onlyPostedRow(harness.model)
        #expect(row?.title == "Whole Foods")
        #expect(row?.subtitle == "Groceries · Chequing")
        #expect(row?.tone == .primary, "an expense is not an error, so it is not red")
        #expect(row?.amountText.hasPrefix("−") == true)
        #expect(row?.isRecurring == false)
        #expect(row?.isEditable == true)
    }

    @Test("Income reads green and positive")
    func incomeRowRenders() async {
        let harness = await makeHarness()
        let form = TransactionFormState(accountID: harness.chequing.id)
        form.mode = .income
        form.amountText = "500.00"
        form.merchant = "Payroll"
        form.date = .now.addingTimeInterval(-3_600)
        await harness.model.save(form)

        let row = onlyPostedRow(harness.model)
        #expect(row?.tone == .positive)
        #expect(row?.amountText.hasPrefix("+") == true)
    }

    @Test("A transfer collapses to one row naming both sides, with no sign")
    func transferRowRenders() async {
        let harness = await makeHarness()
        let form = TransactionFormState(accountID: harness.chequing.id)
        form.mode = .transfer
        form.amountText = "40.00"
        form.destinationAccountID = harness.visa.id
        form.date = .now.addingTimeInterval(-3_600)
        await harness.model.save(form)

        let row = onlyPostedRow(harness.model)
        #expect(row?.title == "Chequing → Visa")
        #expect(row?.subtitle == "Transfer")
        #expect(row?.tone == .secondary)
        // Neither money in nor money out: signing it would pick one leg arbitrarily.
        #expect(row?.amountText.contains("−") == false)
        #expect(row?.amountText.contains("+") == false)
    }

    @Test("A merchant-less expense falls back rather than rendering blank")
    func blankMerchantFallsBack() async {
        let harness = await makeHarness()
        await addExpense(harness, merchant: "", amount: "12.00")

        #expect(onlyPostedRow(harness.model)?.title == "No merchant")
    }

    @Test("A future transaction lands in Upcoming, not in the posted days")
    func futureRowsGoToUpcoming() async {
        let harness = await makeHarness()
        let form = TransactionFormState(accountID: harness.chequing.id)
        form.amountText = "20.00"
        form.merchant = "Later"
        form.date = .now.addingTimeInterval(86_400)
        await harness.model.save(form)

        #expect(harness.model.upcomingRows.count == 1)
        #expect(harness.model.upcomingRows.first?.title == "Later")
        #expect(harness.model.postedDays.isEmpty)
    }

    @Test("Moving the filter rebuilds the rows, not just the underlying items")
    func filterChangeRebuildsRows() async {
        let harness = await makeHarness()
        await addExpense(harness, merchant: "Whole Foods", amount: "60.00")
        #expect(onlyPostedRow(harness.model) != nil)

        harness.model.filter.categoryID = UUID()
        #expect(harness.model.postedDays.isEmpty, "rows follow the filter without a reload")
        #expect(harness.model.isFilteredToZero)
    }

    @Test("Changing the display currency re-renders the cached amounts")
    func currencyChangeRebuildsAmounts() async {
        let harness = await makeHarness()
        await addExpense(harness, merchant: "Whole Foods", amount: "60.00")
        let before = onlyPostedRow(harness.model)?.amountText

        harness.settings.currencyCode = "JPY"
        harness.model.refresh()

        let after = onlyPostedRow(harness.model)?.amountText
        #expect(before != after, "a cached amount must not outlive its currency")
    }

    @Test("The banner totals are computed once and match the filtered set")
    func bannerTotalsMatch() async {
        let harness = await makeHarness()
        await addExpense(harness, merchant: "Whole Foods", amount: "60.00")
        await addExpense(harness, merchant: "Corner Shop", amount: "15.00")

        #expect(harness.model.spendCents == 7_500)
        #expect(harness.model.incomeCents == 0)
        #expect(harness.model.netCents == -7_500)
        #expect(harness.model.bannerCount == 2)
        #expect(harness.model.scopeLabel == "This month · All accounts")
    }

    @Test("Filtering to one account names it in the scope label")
    func scopeLabelNamesTheAccount() async {
        let harness = await makeHarness()
        harness.model.filter.accountID = harness.chequing.id

        #expect(harness.model.scopeLabel == "This month · Chequing")
    }
}
