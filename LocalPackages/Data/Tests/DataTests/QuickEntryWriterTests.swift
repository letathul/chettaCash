import Foundation
import SwiftData
import Testing
import Domain
@testable import Data

/// One Shortcut entry, one commit (§15).
///
/// A Shortcut can imply four rows at once and runs in a process that ends the moment it
/// returns. The point of these is the failure case: a refused write must leave nothing
/// behind, because there is no screen and no user to notice half an entry.
@Suite("Quick entry writer")
struct QuickEntryWriterTests {

    /// The pieces under test, wired together over one store.
    private struct Harness {
        /// The writer under test.
        let writer: SwiftDataQuickEntryWriter
        /// The account repository, for reading back.
        let accounts: SwiftDataAccountRepository
        /// The transaction repository, for reading back.
        let transactions: SwiftDataTransactionRepository
        /// The category repository, for reading back.
        let categories: SwiftDataCategoryRepository
        /// The pin repository, for reading back.
        let pins: SwiftDataMerchantCategoryRuleRepository
    }

    /// Builds an in-memory stack.
    /// - Returns: The harness.
    /// - Throws: A `SwiftDataError` if the schema fails validation.
    private func makeStore() throws -> Harness {
        let container = try ModelContainerFactory.make(inMemory: true)
        return Harness(
            writer: SwiftDataQuickEntryWriter(modelContainer: container),
            accounts: SwiftDataAccountRepository(modelContainer: container),
            transactions: SwiftDataTransactionRepository(modelContainer: container),
            categories: SwiftDataCategoryRepository(modelContainer: container),
            pins: SwiftDataMerchantCategoryRuleRepository(modelContainer: container)
        )
    }

    /// An expense against an account.
    /// - Parameters:
    ///   - accountID: The account it belongs to.
    ///   - categoryID: The category it lands in.
    /// - Returns: The transaction.
    private func expense(accountID: UUID?, categoryID: UUID? = nil) -> Domain.Transaction {
        Domain.Transaction(
            amountCents: 4_210, type: .expense, categoryID: categoryID,
            accountID: accountID, merchant: "Whole Foods",
            tags: [QuickExpensePlanner.originTag]
        )
    }

    @Test("A created account, category, entry and pin all land together")
    func writesEverythingAtOnce() async throws {
        let store = try makeStore()
        let card = Domain.Account(name: "Card ••9087", kind: .card, last4: "9087")
        let coffee = Domain.Category(label: "Coffee", context: .expense)

        try await store.writer.write(QuickEntryWrite(
            transaction: expense(accountID: card.id, categoryID: coffee.id),
            newAccount: card,
            newCategory: coffee,
            newPin: Domain.MerchantCategoryRule.make(
                merchant: "Whole Foods", categoryID: coffee.id, updatedAt: .now
            )
        ))

        let saved = try #require(try await store.accounts.account(id: card.id))
        #expect(saved.last4 == "9087")
        let categories = try await store.categories.selectableCategories(context: .expense)
        #expect(categories.contains { $0.id == coffee.id })
        let stored = try await store.transactions.transactions(accountID: nil, in: nil)
        #expect(stored.count == 1)
        #expect(stored.first?.categoryID == coffee.id)
        let pins = try await store.pins.rules()
        #expect(pins.first?.categoryID == coffee.id)
    }

    @Test("The created account's balance cache moves by what was recorded against it")
    func rebuildsTheBalanceCache() async throws {
        let store = try makeStore()
        let card = Domain.Account(name: "Card ••9087", kind: .card, last4: "9087")

        try await store.writer.write(QuickEntryWrite(
            transaction: expense(accountID: card.id), newAccount: card
        ))

        let saved = try #require(try await store.accounts.account(id: card.id))
        #expect(
            saved.cachedBalanceCents == -4_210,
            "a cache of zero would mean the entry never reached the account"
        )
    }

    @Test("An entry naming an account that is neither there nor being created writes nothing")
    func refusalLeavesNothingBehind() async throws {
        let store = try makeStore()
        let orphanCategory = Domain.Category(label: "Coffee", context: .expense)

        await #expect(throws: TransactionRepositoryError.self) {
            try await store.writer.write(QuickEntryWrite(
                transaction: expense(accountID: UUID(), categoryID: orphanCategory.id),
                newCategory: orphanCategory
            ))
        }

        let stored = try await store.transactions.transactions(accountID: nil, in: nil)
        #expect(stored.isEmpty)
        let categories = try await store.categories.selectableCategories(context: .expense)
        #expect(
            categories.contains { $0.id == orphanCategory.id } == false,
            "the category invented for a refused entry must not survive it"
        )
        let accounts = try await store.accounts.accounts(includeClosed: true)
        #expect(accounts.isEmpty)
    }

    @Test("A parked entry is written with no account at all")
    func writesAParkedEntry() async throws {
        let store = try makeStore()

        try await store.writer.write(QuickEntryWrite(transaction: expense(accountID: nil)))

        let stored = try await store.transactions.transactions(accountID: nil, in: nil)
        #expect(stored.count == 1)
        #expect(stored.first?.accountID == nil)
    }

    @Test("A pin replaces one sharing its merchant key rather than sitting beside it")
    func upsertsThePinByMerchantKey() async throws {
        let store = try makeStore()
        let account = Domain.Account(name: "Chequing")
        let coffee = Domain.Category(label: "Coffee", context: .expense)
        let transport = Domain.Category(label: "Transport", context: .expense)
        try await store.accounts.save(account)
        try await store.categories.save(coffee)
        try await store.categories.save(transport)

        try await store.writer.write(QuickEntryWrite(
            transaction: expense(accountID: account.id),
            newPin: .make(merchant: "WHOLE FOODS MKT #10234", categoryID: coffee.id, updatedAt: .now)
        ))
        try await store.writer.write(QuickEntryWrite(
            transaction: expense(accountID: account.id),
            newPin: .make(merchant: "Whole Foods Mkt", categoryID: transport.id, updatedAt: .now)
        ))

        let pins = try await store.pins.rules()
        #expect(pins.count == 1, "one merchant, one pin — a second would never win")
        #expect(pins.first?.categoryID == transport.id)
    }
}
