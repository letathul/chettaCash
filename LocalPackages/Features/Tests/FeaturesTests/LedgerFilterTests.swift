import Foundation
import Testing
@testable import Features
import Domain

/// Phase 5 acceptance criteria continued: filters combine, and transfers and
/// adjustments stay out of the summary totals while remaining visible (§7.4, §4.3).
@MainActor
@Suite("Ledger filters and totals")
struct LedgerFilterTests {

    /// The pieces under test, wired together.
    private struct Harness {
        /// The account repository fake.
        let accounts: FakeAccountRepository
        /// The recurring rule repository fake.
        let rules: FakeRecurringRuleRepository
        /// The view model under test.
        let model: LedgerViewModel
        /// A spending account.
        let chequing: Domain.Account
        /// A credit card.
        let visa: Domain.Account
        /// An expense category.
        let groceries: Domain.Category
    }

    /// Builds a loaded view model with two accounts and one category.
    /// - Returns: The harness.
    private func makeHarness() async -> Harness {
        let accounts = FakeAccountRepository()
        let transactions = FakeTransactionRepository(accounts: accounts)
        let categories = FakeCategoryRepository()
        let rules = FakeRecurringRuleRepository()
        let chequing = Domain.Account(name: "Chequing", openingBalanceCents: 100_000)
        let visa = Domain.Account(name: "Visa", kind: .card, openingBalanceCents: -20_000)
        let groceries = Domain.Category(label: "Groceries", context: .expense)
        try? await accounts.save(chequing)
        try? await accounts.save(visa)
        try? await categories.save(groceries)
        let model = LedgerViewModel(
            transactionRepository: transactions,
            accountRepository: accounts,
            categoryRepository: categories,
            recurringRuleRepository: rules,
            settings: AppSettings()
        )
        await model.load()
        return Harness(
            accounts: accounts, rules: rules, model: model,
            chequing: chequing, visa: visa, groceries: groceries
        )
    }

    /// Saves an expense or income entry through the form.
    /// - Parameters:
    ///   - harness: The harness under test.
    ///   - mode: Expense or income.
    ///   - amount: The typed amount.
    ///   - account: The owning account.
    ///   - category: The category to assign.
    ///   - date: When it occurred.
    /// - Returns: Whether the form validated and saved.
    @discardableResult
    private func saveEntry(
        _ harness: Harness,
        mode: TransactionFormMode = .expense,
        amount: String,
        account: Domain.Account,
        category: Domain.Category? = nil,
        date: Date = .now.addingTimeInterval(-3_600)
    ) async -> Bool {
        let form = TransactionFormState(accountID: account.id)
        form.mode = mode
        form.amountText = amount
        form.categoryID = category?.id
        form.date = date
        form.merchant = "Test"
        return await harness.model.save(form)
    }

    // MARK: - Filters combine (§7.4)

    @Test("Account and category filters combine with AND")
    func filtersCombine() async {
        let harness = await makeHarness()
        let transport = Domain.Category(label: "Transport", context: .expense)
        await harness.model.addCategory(label: transport.label, context: .expense)
        await saveEntry(harness, amount: "10.00", account: harness.chequing, category: harness.groceries)
        await saveEntry(harness, amount: "20.00", account: harness.visa, category: harness.groceries)
        let model = harness.model

        model.filter.accountID = harness.chequing.id
        #expect(model.filteredTransactions.count == 1)

        model.filter.categoryID = harness.groceries.id
        #expect(model.filteredTransactions.count == 1)

        model.filter.categoryID = UUID()
        #expect(model.filteredTransactions.isEmpty)
        #expect(model.isFilteredToZero, "filtered-to-zero is distinct from first-run empty")
        #expect(model.isEmpty == false)
    }

    @Test("Only categories some transaction carries reach the filter row")
    func filterCategoriesFollowTheData() async {
        let harness = await makeHarness()
        await harness.model.addCategory(label: "Gifts", context: .expense)
        await saveEntry(
            harness, amount: "10.00", account: harness.chequing, category: harness.groceries
        )

        let offered = harness.model.filterCategories
        #expect(offered.contains { $0.id == harness.groceries.id })
        #expect(!offered.contains { $0.label == "Gifts" },
                "nothing is filed under it, so the chip could only ever match nothing")
        #expect(harness.model.selectableCategories(for: .expense).contains { $0.label == "Gifts" },
                "the picker keeps it, or it could never come to be used")
    }

    @Test("The selected category keeps its chip even once nothing carries it")
    func selectedFilterCategorySurvives() async {
        let harness = await makeHarness()
        await saveEntry(
            harness, amount: "10.00", account: harness.chequing, category: harness.groceries
        )
        harness.model.filter.categoryID = harness.groceries.id

        await harness.model.delete(harness.model.allTransactions[0])

        #expect(harness.model.filterCategories.contains { $0.id == harness.groceries.id },
                "an active filter must never become invisible")
    }

    @Test("Last month excludes this month's transactions")
    func periodFilterExcludesOtherMonths() async {
        let harness = await makeHarness()
        await saveEntry(harness, amount: "10.00", account: harness.chequing)
        let model = harness.model

        model.filter.period = .lastMonth

        #expect(model.filteredTransactions.isEmpty)
        model.filter.period = .allTime
        #expect(model.filteredTransactions.count == 1)
    }

    // MARK: - Summary totals (§4.3, §4.4)

    @Test("Transfers and adjustments are visible as rows but absent from the totals")
    func totalsExcludeTransfersAndAdjustments() async {
        let harness = await makeHarness()
        await saveEntry(harness, amount: "60.00", account: harness.visa, category: harness.groceries)
        let transfer = TransactionFormState(accountID: harness.chequing.id)
        transfer.mode = .transfer
        transfer.amountText = "60.00"
        transfer.destinationAccountID = harness.visa.id
        transfer.date = .now.addingTimeInterval(-3_600)
        await harness.model.save(transfer)
        let model = harness.model

        #expect(model.spendCents == 6_000, "the card payment must not double-count the purchase")
        #expect(model.incomeCents == 0)
        #expect(model.bannerCount == 1)
        #expect(model.items.count == 2, "the purchase and the collapsed transfer both render")
    }

    @Test("A transfer collapses to one row, or one leg under an account filter")
    func transferRowCollapsing() async {
        let harness = await makeHarness()
        let form = TransactionFormState(accountID: harness.chequing.id)
        form.mode = .transfer
        form.amountText = "40.00"
        form.destinationAccountID = harness.visa.id
        form.date = .now.addingTimeInterval(-3_600)
        await harness.model.save(form)
        let model = harness.model

        #expect(model.items.count == 1)
        if case .transfer = model.items[0] {} else { Issue.record("Expected a collapsed row") }

        model.filter.accountID = harness.visa.id
        #expect(model.items.count == 1)
        if case .single(let leg) = model.items[0] {
            #expect(leg.type == .transferIn)
        } else {
            Issue.record("Expected a single leg under an account filter")
        }
    }

    // MARK: - Upcoming and closed accounts (§7.4)

    @Test("A future-dated transaction lands in Upcoming and not in the totals")
    func futureTransactionIsUpcoming() async {
        let harness = await makeHarness()
        await saveEntry(
            harness, amount: "30.00", account: harness.chequing,
            date: .now.addingTimeInterval(86_400 * 3)
        )
        let model = harness.model

        #expect(model.upcomingItems.count == 1)
        #expect(model.postedDays.isEmpty)
        #expect(model.spendCents == 0)
        #expect(model.bannerCount == 0)
    }

    @Test("Transactions on a closed account render but are not tappable")
    func closedAccountRowsAreNotEditable() async {
        let harness = await makeHarness()
        await saveEntry(harness, amount: "15.00", account: harness.chequing)
        var closed = harness.chequing
        closed.isClosed = true
        try? await harness.accounts.save(closed)
        await harness.model.load()
        let model = harness.model

        #expect(model.items.count == 1)
        #expect(model.isEditable(model.items[0]) == false)
    }

    @Test("A transaction whose account has not loaded yet stays editable")
    func unloadedAccountRowsStayEditable() async {
        let harness = await makeHarness()
        await saveEntry(harness, amount: "15.00", account: harness.chequing)
        let item = harness.model.items[0]
        // The Dashboard and the search screen open a detail screen against a Ledger
        // model that may not have loaded — an unresolvable account is not a closed one.
        let fresh = LedgerViewModel(
            transactionRepository: FakeTransactionRepository(accounts: FakeAccountRepository()),
            accountRepository: FakeAccountRepository(),
            categoryRepository: FakeCategoryRepository(),
            recurringRuleRepository: FakeRecurringRuleRepository(),
            settings: AppSettings()
        )

        #expect(fresh.isEditable(item) == true)
    }

    // MARK: - Recurring and product bridge (§7.8)

    @Test("The Recurring toggle persists a rule linked to the transaction")
    func recurringTogglePersistsRule() async {
        let harness = await makeHarness()
        let form = TransactionFormState(accountID: harness.chequing.id)
        form.amountText = "9.99"
        form.merchant = "Streaming"
        form.date = .now.addingTimeInterval(-3_600)
        form.isRecurring = true
        form.frequency = .monthly

        await harness.model.save(form)

        #expect(harness.rules.rulesByID.count == 1)
        let rule = harness.rules.rulesByID.values.first
        #expect(rule?.amountCents == 999)
        #expect(rule?.frequency == .monthly)
        #expect(harness.model.allTransactions.first?.recurringRuleID == rule?.id)
    }

    @Test("A zero-cost purchase saves and counts as nothing")
    func zeroCostPurchaseIsValid() async {
        // The free-product path (§7.8) writes one of these, so the Ledger has to
        // accept it and then treat it as the nothing it is.
        let harness = await makeHarness()
        let form = TransactionFormState(accountID: harness.chequing.id)
        form.amountText = "0"
        form.merchant = "Hand-me-down"
        form.date = .now.addingTimeInterval(-3_600)

        #expect(await harness.model.save(form))

        #expect(harness.model.allTransactions.contains { $0.merchant == "Hand-me-down" })
        #expect(harness.model.spendCents == 0)
    }

    @Test("A custom category is created once and reused case-insensitively")
    func customCategoryDeduplicates() async {
        let harness = await makeHarness()

        let first = await harness.model.addCategory(label: "Coffee", context: .expense)
        let second = await harness.model.addCategory(label: "coffee", context: .expense)

        #expect(first == second)
        #expect(harness.model.selectableCategories(for: .expense).count == 2)
    }
}
