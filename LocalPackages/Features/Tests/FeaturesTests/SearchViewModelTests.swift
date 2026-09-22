import Foundation
import Testing
@testable import Features
import Domain

/// The global search screen (§7.12).
///
/// One field and one set of chips drive two halves at once: transactions filtered
/// through ``Domain/LedgerFilter``, products through ``Domain/ProductFilter``. What
/// matters here is that the criteria reach both, that the scope really does exclude the
/// other half, and that "nothing matched" stays distinct from "nothing exists" (§7.0).
@MainActor
@Suite("Global search")
struct SearchViewModelTests {

    /// The pieces under test, wired together.
    private struct Harness {
        /// The Ledger view model, shared with the search screen.
        let ledger: LedgerViewModel
        /// The products view model, shared with the search screen.
        let productsModel: ProductsViewModel
        /// The view model under test.
        let model: SearchViewModel
        /// A spending account.
        let chequing: Domain.Account
        /// A second account, for the account filter.
        let visa: Domain.Account
        /// An expense category.
        let groceries: Domain.Category
    }

    /// Builds a loaded search model over two accounts and one category.
    /// - Parameter seed: Adds transactions and products before the models load.
    /// - Returns: The harness.
    private func makeHarness(
        seed: (
            _ transactions: FakeTransactionRepository,
            _ products: FakeProductRepository,
            _ chequing: Domain.Account,
            _ visa: Domain.Account,
            _ groceries: Domain.Category
        ) async -> Void = { _, _, _, _, _ in }
    ) async -> Harness {
        let accounts = FakeAccountRepository()
        let transactions = FakeTransactionRepository(accounts: accounts)
        let categories = FakeCategoryRepository()
        let rules = FakeRecurringRuleRepository()
        let products = FakeProductRepository()
        let chequing = Domain.Account(name: "Chequing", openingBalanceCents: 100_000)
        let visa = Domain.Account(name: "Visa", kind: .card, openingBalanceCents: 0)
        let groceries = Domain.Category(label: "Groceries", context: .expense)
        try? await accounts.save(chequing)
        try? await accounts.save(visa)
        try? await categories.save(groceries)
        await seed(transactions, products, chequing, visa, groceries)

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
        let model = SearchViewModel(ledgerModel: ledger, productsModel: productsModel)
        await model.load()
        return Harness(
            ledger: ledger, productsModel: productsModel, model: model,
            chequing: chequing, visa: visa, groceries: groceries
        )
    }

    /// Stores one transaction.
    /// - Parameters:
    ///   - repository: The transaction fake.
    ///   - merchant: The merchant name.
    ///   - memo: The optional note.
    ///   - tags: The transaction's tags.
    ///   - accountID: The owning account.
    ///   - categoryID: The assigned category.
    /// - Returns: The stored transaction.
    @discardableResult
    private func store(
        _ repository: FakeTransactionRepository,
        merchant: String,
        memo: String? = nil,
        tags: [String] = [],
        accountID: UUID? = nil,
        categoryID: UUID? = nil
    ) async -> Domain.Transaction {
        let transaction = Domain.Transaction(
            amountCents: 1_500,
            type: .expense,
            categoryID: categoryID,
            accountID: accountID,
            date: .now.addingTimeInterval(-86_400),
            merchant: merchant,
            memo: memo,
            tags: tags
        )
        try? await repository.save(transaction)
        return transaction
    }

    // MARK: - Text

    @Test("One term searches transactions and products at once")
    func searchSpansBothHalves() async {
        let harness = await makeHarness { transactions, products, chequing, _, _ in
            let purchase = await store(
                transactions, merchant: "Apple Store", accountID: chequing.id
            )
            await store(transactions, merchant: "Petrol", accountID: chequing.id)
            let airpods = Domain.Product(transactionID: purchase.id, name: "AirPods Pro")
            products.productsByID[airpods.id] = airpods
        }

        harness.model.search = "AirPods"

        #expect(harness.model.productCards.map(\.name) == ["AirPods Pro"])
        #expect(harness.model.transactionRows.isEmpty,
                "no transaction carries that word")
    }

    @Test("A transaction matches on its memo as well as its merchant")
    func searchMatchesMemo() async {
        let harness = await makeHarness { transactions, _, chequing, _, _ in
            await store(
                transactions, merchant: "Shop", memo: "Anniversary dinner",
                accountID: chequing.id
            )
            await store(transactions, merchant: "Petrol", accountID: chequing.id)
        }

        harness.model.search = "anniversary"

        #expect(harness.model.transactionRows.map(\.title) == ["Shop"])
    }

    // MARK: - Scope

    @Test("Narrowing the scope drops the other half entirely")
    func scopeExcludesTheOtherHalf() async {
        let harness = await makeHarness { transactions, products, chequing, _, _ in
            let purchase = await store(
                transactions, merchant: "Apple Store", accountID: chequing.id
            )
            let airpods = Domain.Product(transactionID: purchase.id, name: "AirPods Pro")
            products.productsByID[airpods.id] = airpods
        }

        harness.model.scope = .transactions
        #expect(!harness.model.transactionRows.isEmpty)
        #expect(harness.model.productCards.isEmpty)

        harness.model.scope = .products
        #expect(harness.model.transactionRows.isEmpty)
        #expect(!harness.model.productCards.isEmpty)

        harness.model.scope = .all
        #expect(!harness.model.transactionRows.isEmpty)
        #expect(!harness.model.productCards.isEmpty)
    }

    // MARK: - Filters

    @Test("The account chip narrows the transaction results")
    func accountFilterNarrows() async {
        let harness = await makeHarness { transactions, _, chequing, visa, _ in
            await store(transactions, merchant: "Chequing buy", accountID: chequing.id)
            await store(transactions, merchant: "Card buy", accountID: visa.id)
        }

        harness.model.accountID = harness.visa.id

        #expect(harness.model.transactionRows.map(\.title) == ["Card buy"])
    }

    @Test("The category chip narrows the transaction results")
    func categoryFilterNarrows() async {
        let harness = await makeHarness { transactions, _, chequing, _, groceries in
            await store(
                transactions, merchant: "Sainsbury's",
                accountID: chequing.id, categoryID: groceries.id
            )
            await store(transactions, merchant: "Petrol", accountID: chequing.id)
        }

        harness.model.categoryID = harness.groceries.id

        #expect(harness.model.transactionRows.map(\.title) == ["Sainsbury's"])
    }

    @Test("Choosing two tags narrows rather than widens")
    func tagFiltersAreAnded() async {
        let harness = await makeHarness { transactions, _, chequing, _, _ in
            await store(
                transactions, merchant: "Both", tags: ["work", "travel"],
                accountID: chequing.id
            )
            await store(
                transactions, merchant: "One", tags: ["work"], accountID: chequing.id
            )
        }

        harness.model.tags = ["work"]
        #expect(harness.model.transactionRows.count == 2)

        harness.model.tags = ["work", "travel"]
        #expect(harness.model.transactionRows.map(\.title) == ["Both"])
    }

    @Test("Every tag in use is offered, from transactions and products alike")
    func tagsComeFromBothHalves() async {
        let harness = await makeHarness { transactions, products, chequing, _, _ in
            let purchase = await store(
                transactions, merchant: "Apple Store", tags: ["gadgets"],
                accountID: chequing.id
            )
            var airpods = Domain.Product(transactionID: purchase.id, name: "AirPods Pro")
            airpods.tags = ["audio"]
            products.productsByID[airpods.id] = airpods
        }

        #expect(harness.model.availableTags == ["audio", "gadgets"])
    }

    @Test("The category chips follow the scope, so none of them is dead")
    func categoriesFollowScope() async {
        let harness = await makeHarness { transactions, _, chequing, _, groceries in
            await store(
                transactions, merchant: "Market",
                accountID: chequing.id, categoryID: groceries.id
            )
        }

        harness.model.scope = .transactions
        #expect(harness.model.categories.contains { $0.id == harness.groceries.id })
        harness.model.categoryID = harness.groceries.id

        harness.model.scope = .products
        #expect(!harness.model.categories.contains { $0.id == harness.groceries.id },
                "an expense category can never match a product")
        #expect(harness.model.categoryID == nil,
                "a filter with no chip left to show for it would narrow silently")
    }

    // MARK: - Empty states (§7.0)

    @Test("Nothing matched is a different state from nothing exists")
    func emptyStatesAreDistinct() async {
        let empty = await makeHarness()
        #expect(empty.model.hasNothingToSearch)

        let stocked = await makeHarness { transactions, _, chequing, _, _ in
            await store(transactions, merchant: "Sainsbury's", accountID: chequing.id)
        }
        #expect(!stocked.model.hasNothingToSearch)

        stocked.model.search = "nothing here matches this"
        #expect(stocked.model.hasNoResults)
        #expect(stocked.model.transactionsFilteredToZero)
    }

    @Test("Search defaults to all time, so it cannot silently hide older entries")
    func defaultPeriodIsAllTime() async {
        let harness = await makeHarness { transactions, _, chequing, _, _ in
            let old = Domain.Transaction(
                amountCents: 500,
                type: .expense,
                accountID: chequing.id,
                date: .now.addingTimeInterval(-200 * 86_400),
                merchant: "Last year"
            )
            try? await transactions.save(old)
        }

        #expect(harness.model.period == .allTime)
        #expect(harness.model.transactionRows.map(\.title) == ["Last year"])
    }
}
