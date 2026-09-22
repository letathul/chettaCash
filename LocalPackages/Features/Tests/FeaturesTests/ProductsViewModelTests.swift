import Foundation
import Testing
@testable import Features
import Domain

/// Acceptance criteria for the Products screen: a product is always part of a
/// purchase, carries no money of its own, and its subscription bills from the
/// purchase's amount (§7.3, §7.7, §7.8).
@MainActor
@Suite("Products screen")
struct ProductsViewModelTests {

    /// The pieces under test, wired together.
    private struct Harness {
        /// The account repository fake, which holds the balance caches.
        let accounts: FakeAccountRepository
        /// The product repository fake.
        let products: FakeProductRepository
        /// The transaction repository fake.
        let transactions: FakeTransactionRepository
        /// The rule repository fake.
        let rules: FakeRecurringRuleRepository
        /// The view model under test.
        let model: ProductsViewModel
        /// The account purchases are made with.
        let account: Domain.Account
        /// A purchase to hang products off.
        let purchase: Domain.Transaction
    }

    /// Builds a loaded view model with one account and one purchase.
    /// - Parameter purchaseCents: What that purchase cost.
    /// - Returns: The harness.
    private func makeHarness(purchaseCents: Int = 24_999) async -> Harness {
        let accounts = FakeAccountRepository()
        let transactions = FakeTransactionRepository(accounts: accounts)
        let categories = FakeCategoryRepository()
        let rules = FakeRecurringRuleRepository()
        let products = FakeProductRepository()
        let account = Domain.Account(name: "Visa", kind: .card, openingBalanceCents: 0)
        try? await accounts.save(account)
        try? await categories.save(Domain.Category(label: "Subscription", context: .product))
        let purchase = Domain.Transaction(
            amountCents: purchaseCents, type: .expense, accountID: account.id,
            date: .now.addingTimeInterval(-86_400), merchant: "Sony Store"
        )
        try? await transactions.save(purchase)
        let model = ProductsViewModel(
            productRepository: products,
            transactionRepository: transactions,
            accountRepository: accounts,
            categoryRepository: categories,
            recurringRuleRepository: rules,
            settings: AppSettings()
        )
        await model.load()
        return Harness(
            accounts: accounts, products: products, transactions: transactions, rules: rules,
            model: model, account: account, purchase: purchase
        )
    }

    /// Adds a product through the form, as the UI does.
    /// - Parameters:
    ///   - harness: The harness under test.
    ///   - name: The product name.
    ///   - purchase: The purchase to attach it to, defaulting to the harness's.
    ///   - tags: Its labels.
    ///   - recurring: Whether it bills on a schedule.
    /// - Returns: The saved product, if the form validated.
    @discardableResult
    private func addProduct(
        _ harness: Harness,
        name: String,
        purchase: Domain.Transaction? = nil,
        tags: [String] = [],
        recurring: Bool = false
    ) async -> Domain.Product? {
        let form = ProductFormState(purchase: purchase ?? harness.purchase)
        form.name = name
        form.tags = tags
        form.isRecurring = recurring
        guard await harness.model.save(form) else { return nil }
        return harness.model.products.first { $0.name == name }
    }

    // MARK: - The purchase link (§7.8)

    @Test("A saved product points at the purchase it was created from")
    func productBelongsToItsPurchase() async throws {
        let harness = await makeHarness()

        let product = try #require(await addProduct(harness, name: "Headphones"))

        #expect(product.transactionID == harness.purchase.id)
    }

    @Test("Saving a product creates no transaction of its own")
    func savingCreatesNoExtraTransaction() async throws {
        let harness = await makeHarness()
        let before = try await harness.transactions.transactions(accountID: nil, in: nil).count

        await addProduct(harness, name: "Headphones")

        let after = try await harness.transactions.transactions(accountID: nil, in: nil).count
        #expect(after == before, "the money was already spent on the purchase")
    }

    @Test("The form pre-fills its name from the merchant")
    func formPrefillsFromTheMerchant() async {
        let harness = await makeHarness()

        let form = ProductFormState(purchase: harness.purchase)

        #expect(form.name == "Sony Store")
        #expect(form.purchase.amountCents == 24_999)
    }

    @Test("Several products share one purchase, and so one receipt")
    func manyProductsOnePurchase() async throws {
        let harness = await makeHarness()
        var withReceipt = harness.purchase
        withReceipt.receiptFileID = "Receipts/2026/2026-09/r.jpg"
        try await harness.transactions.save(withReceipt)
        await harness.model.load()

        await addProduct(harness, name: "Desk Lamp")
        await addProduct(harness, name: "Hallway Rug")

        let listings = harness.model.listings
        #expect(listings.count == 2)
        let allHaveReceipt = listings.allSatisfy(\.hasReceipt)
        #expect(allHaveReceipt, "one image, however many products it covers")
        #expect(harness.model.products(for: harness.purchase.id).count == 2)
    }

    @Test("A listing reports the whole purchase, never a per-product share")
    func listingReportsTheWholePurchase() async throws {
        let harness = await makeHarness()
        await addProduct(harness, name: "Desk Lamp")
        await addProduct(harness, name: "Hallway Rug")

        let amounts = harness.model.listings.map(\.amountCents)

        #expect(amounts == [24_999, 24_999])
    }

    // MARK: - The free-purchase path (§7.8)

    @Test("A free product still gets a purchase, and moves no balance")
    func freeProductGetsAZeroPurchase() async throws {
        let harness = await makeHarness()

        let free = try #require(await harness.model.makeFreePurchase())
        let product = try #require(await addProduct(harness, name: "Gift", purchase: free))

        #expect(free.amountCents == 0)
        #expect(product.transactionID == free.id)
        let account = try #require(harness.accounts.accountsByID[harness.account.id])
        #expect(account.cachedBalanceCents == -24_999, "only the real purchase moved it")
    }

    @Test("A free purchase bills nothing even with the recurring toggle on")
    func freePurchaseBillsNothing() async throws {
        let harness = await makeHarness()
        let free = try #require(await harness.model.makeFreePurchase())

        await addProduct(harness, name: "Gift", purchase: free, recurring: true)

        #expect(harness.rules.rulesByID.isEmpty)
    }

    // MARK: - Validation and browsing (§7.11, §7.3)

    @Test("Saving without a name is refused and reveals the error")
    func validationBlocksSave() async {
        let harness = await makeHarness()
        let form = ProductFormState(purchase: harness.purchase)
        form.name = "   "

        let saved = await harness.model.save(form)

        #expect(saved == false)
        #expect(form.nameError == "Product name is required.")
        #expect(harness.model.products.isEmpty)
    }

    @Test("A price is no longer required, because the product has none")
    func priceIsNotRequired() async {
        let harness = await makeHarness()
        let form = ProductFormState(purchase: harness.purchase)
        form.name = "Headphones"

        #expect(form.isValid)
        #expect(await harness.model.save(form))
    }

    @Test("Edit validates identically to Add")
    func editValidatesLikeAdd() async throws {
        let harness = await makeHarness()
        let product = try #require(await addProduct(harness, name: "Thing"))

        let edit = ProductFormState(editing: product, purchase: harness.purchase)
        edit.name = "   "
        let saved = await harness.model.save(edit)

        #expect(saved == false)
        #expect(edit.nameError == "Product name is required.")
    }

    @Test("Filtering to nothing is a filtered state, not the first-run empty state")
    func filteredToZeroIsDistinct() async {
        let harness = await makeHarness()
        await addProduct(harness, name: "Headphones")

        harness.model.filter.search = "zzz"

        #expect(harness.model.visibleListings.isEmpty)
        #expect(harness.model.isFilteredToZero)
        #expect(harness.model.isEmpty == false)
    }

    @Test("Every tag in use is offered to the tag filter")
    func tagsAreCollectedForFiltering() async {
        let harness = await makeHarness()
        await addProduct(harness, name: "Headphones", tags: ["work", "audio"])
        await addProduct(harness, name: "Lamp", tags: ["work"])

        #expect(harness.model.availableTags == ["audio", "work"])
    }

    @Test("Only expenses and income are offered as purchases to attach to")
    func transfersAreNotAttachable() async throws {
        let harness = await makeHarness()
        let legs = try TransferFactory.makeLegs(
            amountCents: 5_000, date: .now, sourceAccountID: harness.account.id,
            destinationAccountID: UUID(), merchant: "Move"
        )
        try await harness.transactions.saveTransfer(outLeg: legs.out, inLeg: legs.in)
        await harness.model.load()

        let offered = harness.model.attachablePurchases

        #expect(offered.map(\.id) == [harness.purchase.id])
    }

    // MARK: - Deleting (§7.8)

    @Test("Deleting a product leaves its purchase in the Ledger")
    func deleteKeepsThePurchase() async throws {
        let harness = await makeHarness()
        let product = try #require(await addProduct(harness, name: "Headphones"))

        await harness.model.delete(product)

        #expect(harness.model.products.isEmpty)
        let stored = try await harness.transactions.transactions(accountID: nil, in: nil)
        #expect(stored.contains { $0.id == harness.purchase.id },
                "the money was real and the receipt may cover siblings")
    }

    @Test("Deleting a subscription product ends its billing rule")
    func deleteEndsBilling() async throws {
        let harness = await makeHarness(purchaseCents: 999)
        let product = try #require(
            await addProduct(harness, name: "Streaming", recurring: true)
        )

        await harness.model.delete(product)

        #expect(harness.rules.rulesByID.isEmpty)
    }

    // MARK: - Pending products from the Add Transaction form (§7.8)

    @Test("Products collected before a transaction exists are stamped with its id")
    func pendingProductsAreStamped() async throws {
        let harness = await makeHarness()
        let stranded = UUID()
        let pending = [
            Domain.Product(transactionID: stranded, name: "Desk Lamp"),
            Domain.Product(transactionID: stranded, name: "Hallway Rug")
        ]

        try await harness.model.attach(pending, to: harness.purchase.id)

        let stored = harness.model.products(for: harness.purchase.id)
        #expect(stored.map(\.name) == ["Desk Lamp", "Hallway Rug"])
        #expect(stored.map(\.sortIndex) == [0, 1])
    }
}
