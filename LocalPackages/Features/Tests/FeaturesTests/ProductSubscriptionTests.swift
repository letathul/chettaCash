import Foundation
import Testing
@testable import Features
import Domain

/// A product that bills on a schedule (§7.7, §4.5).
///
/// The rule's amount comes from the purchase, so a free purchase bills nothing however
/// the toggle is set.
@MainActor
@Suite("Product subscriptions")
struct ProductSubscriptionTests {

    /// The pieces under test, wired together.
    private struct Harness {
        /// The transaction repository fake.
        let transactions: FakeTransactionRepository
        /// The rule repository fake.
        let rules: FakeRecurringRuleRepository
        /// The view model under test.
        let model: ProductsViewModel
        /// A purchase to hang products off.
        let purchase: Domain.Transaction
    }

    /// Builds a loaded view model with one account and one purchase.
    /// - Parameter purchaseCents: What that purchase cost.
    /// - Returns: The harness.
    private func makeHarness(purchaseCents: Int = 999) async -> Harness {
        let accounts = FakeAccountRepository()
        let transactions = FakeTransactionRepository(accounts: accounts)
        let rules = FakeRecurringRuleRepository()
        let account = Domain.Account(name: "Visa", kind: .card, openingBalanceCents: 0)
        try? await accounts.save(account)
        let purchase = Domain.Transaction(
            amountCents: purchaseCents, type: .expense, accountID: account.id,
            date: .now.addingTimeInterval(-86_400), merchant: "Streaming"
        )
        try? await transactions.save(purchase)
        let model = ProductsViewModel(
            productRepository: FakeProductRepository(),
            transactionRepository: transactions,
            accountRepository: accounts,
            categoryRepository: FakeCategoryRepository(),
            recurringRuleRepository: rules,
            settings: AppSettings()
        )
        await model.load()
        return Harness(
            transactions: transactions, rules: rules, model: model, purchase: purchase
        )
    }

    /// Adds a product through the form, as the UI does.
    /// - Parameters:
    ///   - harness: The harness under test.
    ///   - name: The product name.
    ///   - purchase: The purchase to attach it to, defaulting to the harness's.
    ///   - recurring: Whether it bills on a schedule.
    /// - Returns: The saved product, if the form validated.
    @discardableResult
    private func addProduct(
        _ harness: Harness,
        name: String,
        purchase: Domain.Transaction? = nil,
        recurring: Bool = false
    ) async -> Domain.Product? {
        let form = ProductFormState(purchase: purchase ?? harness.purchase)
        form.name = name
        form.isRecurring = recurring
        guard await harness.model.save(form) else { return nil }
        return harness.model.products.first { $0.name == name }
    }

    @Test("A subscription bills the purchase's amount and generates occurrences")
    func recurringChargeGeneratesLedgerTransactions() async throws {
        let harness = await makeHarness(purchaseCents: 999)
        let product = try #require(
            await addProduct(harness, name: "Streaming", recurring: true)
        )

        let rule = try #require(harness.rules.rulesByID.values.first)
        #expect(rule.productID == product.id)
        #expect(rule.amountCents == 999, "taken from the purchase, not the product")

        let coordinator = RecurringCoordinator(
            transactions: harness.transactions, rules: harness.rules
        )
        try await coordinator.reconcile(now: .now.addingTimeInterval(70 * 86_400))

        let stored = try await harness.transactions.transactions(accountID: nil, in: nil)
        let occurrences = stored.filter { $0.recurringRuleID == rule.id }
        #expect(occurrences.count >= 2, "the Phase 6 engine generated them")
        let allBillTheSame = occurrences.allSatisfy { $0.amountCents == 999 }
        #expect(allBillTheSame)
    }

    @Test("Editing a subscription updates its rule rather than creating a second")
    func editingUpdatesRule() async throws {
        let harness = await makeHarness(purchaseCents: 999)
        let product = try #require(
            await addProduct(harness, name: "Streaming", recurring: true)
        )
        let originalRuleID = try #require(harness.rules.rulesByID.values.first).id

        let edit = ProductFormState(editing: product, purchase: harness.purchase)
        edit.name = "Streaming Plus"
        #expect(await harness.model.save(edit))

        #expect(harness.rules.rulesByID.count == 1)
        let rule = try #require(harness.rules.rulesByID.values.first)
        #expect(rule.id == originalRuleID)
        #expect(rule.name == "Streaming Plus")
    }

    @Test("Switching the recurring toggle off removes the rule")
    func disablingRecurringRemovesRule() async throws {
        let harness = await makeHarness(purchaseCents: 999)
        let product = try #require(
            await addProduct(harness, name: "Streaming", recurring: true)
        )

        let edit = ProductFormState(editing: product, purchase: harness.purchase)
        edit.isRecurring = false
        #expect(await harness.model.save(edit))

        #expect(harness.rules.rulesByID.isEmpty)
        #expect(harness.model.products.first?.recurringRuleID == nil)
    }
}
