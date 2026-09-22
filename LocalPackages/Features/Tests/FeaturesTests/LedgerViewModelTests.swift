import Foundation
import Testing
@testable import Features
import Domain

/// Phase 5 acceptance criteria: all three transaction types create and edit with
/// validation, all three filters combine, and transfers and adjustments stay out of
/// the summary totals while remaining visible (§7.4, §7.8, §7.11).
@MainActor
@Suite("Ledger and transactions")
struct LedgerViewModelTests {

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

    // MARK: - Creating each type (§7.8)

    @Test("An expense can be created")
    func createsExpense() async {
        let harness = await makeHarness()

        let saved = await saveEntry(
            harness, amount: "25.00", account: harness.chequing, category: harness.groceries
        )

        #expect(saved)
        #expect(harness.model.allTransactions.count == 1)
        #expect(harness.model.spendCents == 2_500)
        #expect(harness.model.incomeCents == 0)
    }

    @Test("Income can be created and reads as income, not negative spend")
    func createsIncome() async {
        let harness = await makeHarness()

        await saveEntry(harness, mode: .income, amount: "1,200.00", account: harness.chequing)

        #expect(harness.model.incomeCents == 120_000)
        #expect(harness.model.spendCents == 0)
        #expect(harness.model.netCents == 120_000)
    }

    @Test("A transfer creates both legs sharing one group")
    func createsTransfer() async {
        let harness = await makeHarness()
        let form = TransactionFormState(accountID: harness.chequing.id)
        form.mode = .transfer
        form.amountText = "150.00"
        form.destinationAccountID = harness.visa.id
        form.date = .now.addingTimeInterval(-3_600)

        let saved = await harness.model.save(form)

        #expect(saved)
        #expect(harness.model.allTransactions.count == 2)
        let groups = Set(harness.model.allTransactions.compactMap(\.transferGroupID))
        #expect(groups.count == 1)
        #expect(harness.model.allTransactions.allSatisfy { $0.categoryID == nil })
    }

    // MARK: - Validation (§7.11)

    @Test("Saving with no amount is refused and reveals the error")
    func amountIsRequired() async {
        let harness = await makeHarness()
        let form = TransactionFormState(accountID: harness.chequing.id)

        let saved = await harness.model.save(form)

        #expect(saved == false)
        #expect(form.amountError == "Enter an amount to continue.")
        #expect(harness.model.allTransactions.isEmpty)
    }

    @Test("Saving with no account is refused")
    func accountIsRequired() async {
        let harness = await makeHarness()
        let form = TransactionFormState()
        form.amountText = "10.00"

        let saved = await harness.model.save(form)

        #expect(saved == false)
        #expect(form.accountError == "Choose an account to continue.")
    }

    @Test("A transfer to the same account is refused")
    func transferAccountsMustDiffer() async {
        let harness = await makeHarness()
        let form = TransactionFormState(accountID: harness.chequing.id)
        form.mode = .transfer
        form.amountText = "10.00"
        form.destinationAccountID = harness.chequing.id

        let saved = await harness.model.save(form)

        #expect(saved == false)
        #expect(form.destinationError == "Choose a different account.")
        #expect(harness.model.allTransactions.isEmpty)
    }

    @Test("Validation stays hidden until Save is attempted")
    func validationHiddenBeforeSave() {
        let form = TransactionFormState()
        #expect(form.amountError == nil)
        #expect(form.accountError == nil)
        #expect(form.destinationError == nil)
    }

    @Test("A negative amount does not count as an amount")
    func negativeAmountIsInvalid() {
        // The sign comes from the transaction's type, never from the typed figure.
        let form = TransactionFormState(accountID: UUID())
        form.amountText = "-5.00"
        #expect(form.attemptSave() == false)
        #expect(form.amountError == "Enter an amount to continue.")
    }

    @Test("Zero is a real amount for an expense, because free things are still bought")
    func zeroAmountIsValidForAnExpense() {
        // What a product with no cost hangs off (§7.8).
        let form = TransactionFormState(accountID: UUID())
        form.amountText = "0"

        #expect(form.attemptSave())
        #expect(form.amountError == nil)
        #expect(form.commitSingle()?.amountCents == 0)
    }

    @Test("Zero is refused for a transfer, where it can only be a mistake")
    func zeroAmountIsInvalidForATransfer() {
        let form = TransactionFormState(accountID: UUID())
        form.mode = .transfer
        form.destinationAccountID = UUID()
        form.amountText = "0"

        #expect(form.attemptSave() == false)
        #expect(form.amountError == "A transfer needs an amount above zero.")
    }

    // MARK: - Editing (§7.8, §4.3)

    @Test("An expense can be edited without changing its identity")
    func editsExpense() async {
        let harness = await makeHarness()
        await saveEntry(harness, amount: "25.00", account: harness.chequing)
        guard let original = harness.model.allTransactions.first else { return }

        let form = TransactionFormState(editing: original)
        form.amountText = "40.00"
        form.merchant = "Renamed"
        let saved = await harness.model.save(form)

        #expect(saved)
        #expect(harness.model.allTransactions.count == 1)
        #expect(harness.model.allTransactions.first?.id == original.id)
        #expect(harness.model.spendCents == 4_000)
    }

    @Test("Editing a transfer rewrites both legs and never leaves a half-transfer")
    func editingTransferKeepsBothLegs() async {
        let harness = await makeHarness()
        let form = TransactionFormState(accountID: harness.chequing.id)
        form.mode = .transfer
        form.amountText = "100.00"
        form.destinationAccountID = harness.visa.id
        form.date = .now.addingTimeInterval(-3_600)
        await harness.model.save(form)
        guard let leg = harness.model.allTransactions.first(where: { $0.type == .transferOut })
        else { return }

        let edit = TransactionFormState(
            editing: leg, counterpartAccountID: harness.model.counterpartAccountID(for: leg)
        )
        edit.amountText = "175.00"
        await harness.model.save(edit)

        #expect(harness.model.allTransactions.count == 2)
        #expect(harness.model.allTransactions.allSatisfy { $0.amountCents == 17_500 })
        let groups = Set(harness.model.allTransactions.compactMap(\.transferGroupID))
        #expect(groups.count == 1)
    }

    @Test("Deleting one transfer leg deletes both")
    func deletingTransferDeletesBoth() async {
        let harness = await makeHarness()
        let form = TransactionFormState(accountID: harness.chequing.id)
        form.mode = .transfer
        form.amountText = "50.00"
        form.destinationAccountID = harness.visa.id
        form.date = .now.addingTimeInterval(-3_600)
        await harness.model.save(form)
        guard let leg = harness.model.allTransactions.first else { return }

        await harness.model.delete(leg)

        #expect(harness.model.allTransactions.isEmpty)
    }
}
