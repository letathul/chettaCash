import Foundation
import Testing
@testable import Features
import Domain

/// A receipt attached to a transaction (§7.8, §9.3).
///
/// The receipt belongs to the **purchase**, which is what makes one image able to cover
/// several products. Before the redesign it could only be attached from a product form,
/// so the Ledger could never acquire one at all despite `Transaction` carrying the
/// fields for it.
@MainActor
@Suite("Transaction receipts")
struct TransactionReceiptTests {

    /// The pieces under test, wired together.
    private struct Harness {
        /// The account repository fake, which holds the balance caches.
        let accounts: FakeAccountRepository
        /// The transaction repository fake.
        let transactions: FakeTransactionRepository
        /// The product repository fake.
        let products: FakeProductRepository
        /// The receipt store fake.
        let store: FakeReceiptStore
        /// The storage coordinator.
        let storage: ReceiptStorageCoordinator
        /// The Ledger view model under test.
        let model: LedgerViewModel
        /// The Products view model the Ledger writes products through.
        let productsModel: ProductsViewModel
        /// The account purchases are made with.
        let account: Domain.Account
    }

    /// Builds a loaded Ledger view model wired to a receipt store.
    /// - Returns: The harness.
    private func makeHarness() async -> Harness {
        let accounts = FakeAccountRepository()
        let transactions = FakeTransactionRepository(accounts: accounts)
        let categories = FakeCategoryRepository()
        let rules = FakeRecurringRuleRepository()
        let products = FakeProductRepository()
        let store = FakeReceiptStore()
        let account = Domain.Account(name: "Visa", kind: .card, openingBalanceCents: 0)
        try? await accounts.save(account)

        let storage = ReceiptStorageCoordinator(
            store: store, transactions: transactions,
            backups: FakeBackupWriter(), settings: AppSettings()
        )
        let productsModel = ProductsViewModel(
            productRepository: products,
            transactionRepository: transactions,
            accountRepository: accounts,
            categoryRepository: categories,
            recurringRuleRepository: rules,
            settings: AppSettings(),
            receiptStorage: storage
        )
        let model = LedgerViewModel(
            transactionRepository: transactions,
            accountRepository: accounts,
            categoryRepository: categories,
            recurringRuleRepository: rules,
            settings: AppSettings(),
            productsModel: productsModel,
            receiptStorage: storage
        )
        await model.load()
        return Harness(
            accounts: accounts,
            transactions: transactions, products: products, store: store,
            storage: storage, model: model, productsModel: productsModel, account: account
        )
    }

    /// Fills in the Add Transaction form.
    /// - Parameter harness: The harness under test.
    /// - Returns: The form.
    private func form(_ harness: Harness) -> TransactionFormState {
        let form = TransactionFormState(accountID: harness.account.id)
        form.amountText = "249.99"
        form.merchant = "Sony Store"
        return form
    }

    /// The image bytes a scan would hand over.
    private var imageData: Data { Data(repeating: 7, count: 2_048) }

    // MARK: - Attaching

    @Test("A scanned receipt is stored against the transaction")
    func receiptAttachesToTheTransaction() async throws {
        let harness = await makeHarness()

        let saved = await harness.model.save(form(harness), receiptImageData: imageData)

        #expect(saved)
        let stored = try #require(harness.model.allTransactions.first)
        #expect(stored.receiptFileID != nil)
        #expect(stored.receiptUploadState != .none)
    }

    @Test("The receipt's identifier is keyed to the transaction")
    func fileIsNamedAfterTheTransaction() async throws {
        let harness = await makeHarness()

        await harness.model.save(form(harness), receiptImageData: imageData)

        let stored = try #require(harness.model.allTransactions.first)
        let fileID = try #require(stored.receiptFileID)
        #expect(fileID.contains("sony-store"))
        #expect(fileID.hasSuffix("\(ReceiptNaming.shortID(stored.id)).jpg"))
    }

    @Test("Every product on the purchase reports the same receipt")
    func oneReceiptCoversEveryProduct() async throws {
        let harness = await makeHarness()
        let form = form(harness)
        let pending = form.commitPreview().id
        form.products = [
            Domain.Product(transactionID: pending, name: "Headphones"),
            Domain.Product(transactionID: pending, name: "Case")
        ]

        await harness.model.save(form, receiptImageData: imageData)

        let listings = harness.productsModel.listings
        #expect(listings.count == 2)
        let allHaveReceipt = listings.allSatisfy(\.hasReceipt)
        #expect(allHaveReceipt, "one image, however many products it covers")
    }

    @Test("Saving without a scan leaves any existing receipt alone")
    func savingWithoutAScanKeepsTheReceipt() async throws {
        let harness = await makeHarness()
        await harness.model.save(form(harness), receiptImageData: imageData)
        let original = try #require(harness.model.allTransactions.first)

        let edit = TransactionFormState(editing: original)
        edit.merchant = "Sony Store Online"
        await harness.model.save(edit)

        let updated = try #require(harness.model.allTransactions.first)
        #expect(updated.merchant == "Sony Store Online")
        #expect(updated.receiptFileID == original.receiptFileID)
    }

    @Test("A transfer never acquires a receipt")
    func transfersCarryNoReceipt() async throws {
        let harness = await makeHarness()
        let destination = Domain.Account(name: "Chequing", kind: .account)
        try await harness.accounts.save(destination)
        await harness.model.load()
        let form = TransactionFormState(accountID: harness.account.id)
        form.mode = .transfer
        form.amountText = "50.00"
        form.destinationAccountID = destination.id

        await harness.model.save(form, receiptImageData: imageData)

        let legs = harness.model.allTransactions.filter { $0.transferGroupID != nil }
        #expect(legs.count == 2)
        let noneCarryAReceipt = legs.allSatisfy { $0.receiptFileID == nil }
        #expect(noneCarryAReceipt)
    }

    // MARK: - Replacing and removing

    @Test("Replacing a receipt deletes the one it displaced")
    func replacingDeletesTheOldFile() async throws {
        let harness = await makeHarness()
        await harness.model.save(form(harness), receiptImageData: imageData)
        let original = try #require(harness.model.allTransactions.first)
        let originalFileID = try #require(original.receiptFileID)
        await harness.storage.flushUploads()

        let edit = TransactionFormState(editing: original)
        edit.merchant = "Sony Store Online"
        await harness.model.save(edit, receiptImageData: Data(repeating: 9, count: 1_024))

        let updated = try #require(harness.model.allTransactions.first)
        #expect(updated.receiptFileID != originalFileID)
        let remaining = await harness.store.files.keys.contains(originalFileID)
        #expect(remaining == false, "the displaced image must not linger in storage")
    }

    @Test("Removing a receipt clears the link and deletes the file")
    func removingDeletesTheFile() async throws {
        let harness = await makeHarness()
        await harness.model.save(form(harness), receiptImageData: imageData)
        let original = try #require(harness.model.allTransactions.first)
        let fileID = try #require(original.receiptFileID)
        await harness.storage.flushUploads()

        let edit = TransactionFormState(editing: original)
        edit.receiptFileID = nil
        await harness.model.save(edit)

        let updated = try #require(harness.model.allTransactions.first)
        #expect(updated.receiptFileID == nil)
        let remaining = await harness.store.files.keys.contains(fileID)
        #expect(remaining == false)
    }

    // MARK: - Deleting the purchase

    @Test("Deleting a transaction takes its receipt with it")
    func deletingDiscardsTheReceipt() async throws {
        let harness = await makeHarness()
        await harness.model.save(form(harness), receiptImageData: imageData)
        let stored = try #require(harness.model.allTransactions.first)
        let fileID = try #require(stored.receiptFileID)
        await harness.storage.flushUploads()

        await harness.model.delete(stored)

        let remaining = await harness.store.files.keys.contains(fileID)
        #expect(remaining == false, "nothing is left pointing at it")
    }

    // MARK: - Reading it back

    @Test("A stored receipt is served from the cache while it is warm")
    func servesFromCache() async {
        let harness = await makeHarness()
        let fileID = harness.storage.capture(
            imageData, for: Domain.Transaction(amountCents: 1_000, merchant: "Shop")
        )

        let loaded = await harness.storage.image(for: fileID)

        #expect(loaded == imageData)
    }

    @Test("A receipt comes back from the store once the cache is cold")
    func fallsBackToTheStore() async {
        let harness = await makeHarness()
        let fileID = harness.storage.capture(
            imageData, for: Domain.Transaction(amountCents: 1_000, merchant: "Shop")
        )
        await harness.storage.flushUploads()
        // The cache is in memory only, so a relaunch looks exactly like this.
        await harness.storage.clearCache()

        let loaded = await harness.storage.image(for: fileID)

        #expect(loaded == imageData)
    }

    @Test("A receipt the store cannot produce reads as absent rather than crashing")
    func missingReceiptReadsAsNil() async {
        let harness = await makeHarness()

        let loaded = await harness.storage.image(for: "Receipts/2026/2026-09/gone.jpg")

        #expect(loaded == nil)
    }
}
