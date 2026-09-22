import Foundation
import Testing
@testable import Features
import Domain

/// Adding products from the transaction form (§7.8).
///
/// This is now the primary way a product comes into existence: you record what you
/// bought, then say what was in it. The thing that must not happen is a product ending
/// up attached to nothing — on Add the transaction has no row until Save, so its
/// products are held pending and stamped once it does.
@MainActor
@Suite("Products on a transaction")
struct ProductsOnTransactionTests {

    /// The pieces under test, wired together.
    private struct Harness {
        /// The account repository fake, which holds the balance caches.
        let accounts: FakeAccountRepository
        /// The transaction repository fake.
        let transactions: FakeTransactionRepository
        /// The product repository fake.
        let products: FakeProductRepository
        /// The Products view model, shared with the Ledger.
        let productsModel: ProductsViewModel
        /// The Ledger view model under test.
        let ledger: LedgerViewModel
        /// The account purchases are made with.
        let account: Domain.Account
    }

    /// Builds both view models over one shared repository set.
    /// - Returns: The harness.
    private func makeHarness() async -> Harness {
        let accounts = FakeAccountRepository()
        let transactions = FakeTransactionRepository(accounts: accounts)
        let categories = FakeCategoryRepository()
        let rules = FakeRecurringRuleRepository()
        let products = FakeProductRepository()
        let account = Domain.Account(name: "Visa", kind: .card, openingBalanceCents: 0)
        try? await accounts.save(account)

        let productsModel = ProductsViewModel(
            productRepository: products,
            transactionRepository: transactions,
            accountRepository: accounts,
            categoryRepository: categories,
            recurringRuleRepository: rules,
            settings: AppSettings()
        )
        let ledger = LedgerViewModel(
            transactionRepository: transactions,
            accountRepository: accounts,
            categoryRepository: categories,
            recurringRuleRepository: rules,
            settings: AppSettings(),
            productsModel: productsModel
        )
        await productsModel.load()
        await ledger.load()
        return Harness(
            accounts: accounts,
            transactions: transactions, products: products,
            productsModel: productsModel, ledger: ledger, account: account
        )
    }

    /// Fills in the Add Transaction form.
    /// - Parameters:
    ///   - harness: The harness under test.
    ///   - cents: The typed amount.
    /// - Returns: The form.
    private func form(_ harness: Harness, cents: String = "249.99") -> TransactionFormState {
        let form = TransactionFormState(accountID: harness.account.id)
        form.amountText = cents
        form.merchant = "Sony Store"
        return form
    }

    // MARK: - Adding

    @Test("Products collected on Add are written once the transaction exists")
    func pendingProductsAreWrittenOnSave() async throws {
        let harness = await makeHarness()
        let form = form(harness)
        let pending = form.commitPreview().id
        form.products = [
            Domain.Product(transactionID: pending, name: "Headphones"),
            Domain.Product(transactionID: pending, name: "Carry case")
        ]

        #expect(await harness.ledger.save(form))

        let transaction = try #require(harness.ledger.allTransactions.first)
        let stored = harness.productsModel.products(for: transaction.id)
        #expect(stored.map(\.name) == ["Headphones", "Carry case"])
        let allPointAtThePurchase = stored.allSatisfy { $0.transactionID == transaction.id }
        #expect(allPointAtThePurchase)
    }

    @Test("The form's provisional identifier is the one the save uses")
    func provisionalIdentifierSurvivesTheSave() async throws {
        let harness = await makeHarness()
        let form = form(harness)
        let provisional = form.commitPreview().id

        #expect(await harness.ledger.save(form))

        let transaction = try #require(harness.ledger.allTransactions.first)
        #expect(transaction.id == provisional,
                "products collected before Save must not be orphaned by it")
    }

    @Test("Adding products does not change what the purchase cost")
    func productsDoNotChangeTheTotal() async throws {
        let harness = await makeHarness()
        let form = form(harness)
        let pending = form.commitPreview().id
        form.products = [
            Domain.Product(transactionID: pending, name: "Headphones"),
            Domain.Product(transactionID: pending, name: "Carry case")
        ]

        await harness.ledger.save(form)

        let transaction = try #require(harness.ledger.allTransactions.first)
        #expect(transaction.amountCents == 24_999, "the money is recorded once, on the purchase")
    }

    @Test("A purchase with no products saves exactly as before")
    func productsAreOptional() async throws {
        let harness = await makeHarness()

        #expect(await harness.ledger.save(form(harness)))

        #expect(harness.ledger.allTransactions.count == 1)
        #expect(harness.productsModel.products.isEmpty)
    }

    // MARK: - Adding from above the keyboard (§7.8)

    @Test("On Edit a product added from the transaction form is persisted immediately")
    func productAddedOnEditWritesImmediately() async throws {
        let harness = await makeHarness()
        #expect(await harness.ledger.save(form(harness)))
        let transaction = try #require(harness.ledger.allTransactions.first)

        let product = Domain.Product(transactionID: transaction.id, name: "Headphones")
        #expect(await harness.productsModel.save(product))

        #expect(harness.productsModel.products(for: transaction.id).map(\.name)
                == ["Headphones"])
    }

    // MARK: - A free purchase (§7.8)

    @Test("A zero-cost purchase saves and leaves the balance where it was")
    func zeroCostPurchaseMovesNoBalance() async throws {
        let harness = await makeHarness()
        let form = form(harness, cents: "0")
        form.merchant = "Hand-me-down"
        let pending = form.commitPreview().id
        form.products = [Domain.Product(transactionID: pending, name: "Office Chair")]

        #expect(await harness.ledger.save(form), "a product with no money is still a purchase")

        let transaction = try #require(harness.ledger.allTransactions.first)
        #expect(transaction.amountCents == 0)
        #expect(harness.productsModel.products(for: transaction.id).count == 1)
        let account = try #require(harness.accounts.accountsByID[harness.account.id])
        #expect(account.cachedBalanceCents == 0)
    }

    @Test("A zero-cost purchase contributes nothing to spend totals")
    func zeroCostPurchaseIsNotSpending() async {
        let harness = await makeHarness()
        let form = form(harness, cents: "0")

        await harness.ledger.save(form)

        #expect(harness.ledger.spendCents == 0)
    }

    // MARK: - Editing

    @Test("Editing a purchase loads the products already attached to it")
    func editingLoadsExistingProducts() async throws {
        let harness = await makeHarness()
        #expect(await harness.ledger.save(form(harness)))
        let transaction = try #require(harness.ledger.allTransactions.first)
        try await harness.productsModel.attach(
            [Domain.Product(transactionID: transaction.id, name: "Headphones")],
            to: transaction.id
        )

        let stored = harness.productsModel.products(for: transaction.id)

        #expect(stored.map(\.name) == ["Headphones"])
    }

    @Test("Deleting a purchase removes the products hanging off it")
    func deletingAPurchaseRemovesItsProducts() async throws {
        let harness = await makeHarness()
        let form = form(harness)
        let pending = form.commitPreview().id
        form.products = [Domain.Product(transactionID: pending, name: "Headphones")]
        await harness.ledger.save(form)
        let transaction = try #require(harness.ledger.allTransactions.first)

        // The fake has no cascade, so the products model is what must be reloaded; the
        // SwiftData store's own cascade is covered in DataTests.
        harness.products.productsByID = [:]
        await harness.ledger.delete(transaction)

        #expect(harness.productsModel.products.isEmpty)
    }

    // MARK: - Wiring

    @Test("A Ledger with no Products model simply has no product section")
    func productsModelIsOptional() async {
        let accounts = FakeAccountRepository()
        let ledger = LedgerViewModel(
            transactionRepository: FakeTransactionRepository(accounts: accounts),
            accountRepository: accounts,
            categoryRepository: FakeCategoryRepository(),
            recurringRuleRepository: FakeRecurringRuleRepository(),
            settings: AppSettings()
        )

        #expect(ledger.productsModel == nil)
        #expect(ledger.receiptStorage == nil)
    }
}
