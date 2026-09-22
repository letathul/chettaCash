import Foundation
import SwiftData
import Testing
import Domain
@testable import Data

/// The import fingerprint column and the bulk write behind statement import (§4.2).
@Suite("Statement import persistence")
struct StatementImportPersistenceTests {

    /// The pieces under test, wired together.
    private struct Harness {
        /// The account repository.
        let accounts: SwiftDataAccountRepository
        /// The transaction repository.
        let transactions: SwiftDataTransactionRepository
        /// The card every transaction in a test is recorded against.
        let card: Domain.Account
    }

    /// Builds an in-memory stack with one card already saved.
    /// - Returns: The harness.
    private func makeStore() async throws -> Harness {
        let container = try ModelContainerFactory.make(inMemory: true)
        let accounts = SwiftDataAccountRepository(modelContainer: container)
        let transactions = SwiftDataTransactionRepository(modelContainer: container)
        let card = Domain.Account(
            name: "Visa", kind: .card, openingBalanceCents: 0, last4: "4417", cardNetwork: .visa
        )
        try await accounts.save(card)
        return Harness(accounts: accounts, transactions: transactions, card: card)
    }

    @Test("A saved transaction stores its fingerprint")
    func hashIsPersisted() async throws {
        let store = try await makeStore()
        let purchase = Domain.Transaction(
            amountCents: 675, type: .expense, accountID: store.card.id, merchant: "Blue Bottle"
        )

        try await store.transactions.save(purchase)

        let stored = try await store.transactions.transactions(accountID: store.card.id, in: nil)
        let saved = try #require(stored.first)
        #expect(saved.transactionHash == purchase.transactionHash)
        #expect(!saved.transactionHash.isEmpty)
    }

    @Test("Editing a transaction moves its fingerprint with it")
    func hashFollowsAnEdit() async throws {
        // The reason the Domain side is computed: a stored hash left behind by an edit
        // would let the same purchase import a second time.
        let store = try await makeStore()
        var purchase = Domain.Transaction(
            amountCents: 675, type: .expense, accountID: store.card.id, merchant: "Blue Bottle"
        )
        try await store.transactions.save(purchase)
        let before = purchase.transactionHash

        purchase.merchant = "Blue Bottle Coffee Roasters"
        try await store.transactions.save(purchase)

        let stored = try await store.transactions.transactions(accountID: store.card.id, in: nil)
        let saved = try #require(stored.first)
        #expect(saved.transactionHash != before)
        #expect(saved.transactionHash == purchase.transactionHash)
    }

    @Test("Saving a batch writes every row once")
    func batchInserts() async throws {
        let store = try await makeStore()
        let batch = (1...25).map { index in
            Domain.Transaction(
                amountCents: index * 100, type: .expense, accountID: store.card.id,
                date: Date.now.addingTimeInterval(Double(-index) * 86_400),
                merchant: "Shop \(index)"
            )
        }

        try await store.transactions.saveAll(batch)

        let stored = try await store.transactions.transactions(accountID: store.card.id, in: nil)
        #expect(stored.count == 25)
    }

    @Test("Saving a batch upserts by id rather than appending")
    func batchUpserts() async throws {
        let store = try await makeStore()
        var purchase = Domain.Transaction(
            amountCents: 675, type: .expense, accountID: store.card.id, merchant: "Blue Bottle"
        )
        try await store.transactions.saveAll([purchase])

        purchase.amountCents = 700
        try await store.transactions.saveAll([purchase])

        let stored = try await store.transactions.transactions(accountID: store.card.id, in: nil)
        #expect(stored.count == 1)
        #expect(stored.first?.amountCents == 700)
    }

    @Test("A batch leaves every affected account's balance cache correct")
    func batchRefreshesBalances() async throws {
        // The whole reason `saveAll` exists is to refresh once instead of per row — so the
        // figure it leaves behind has to be the same one per-row saving would have.
        let store = try await makeStore()
        let other = Domain.Account(name: "Chequing", kind: .account, openingBalanceCents: 100_000)
        try await store.accounts.save(other)
        let yesterday = Date.now.addingTimeInterval(-86_400)

        try await store.transactions.saveAll([
            Domain.Transaction(amountCents: 2_000, type: .expense, accountID: store.card.id,
                               date: yesterday, merchant: "A"),
            Domain.Transaction(amountCents: 3_000, type: .expense, accountID: store.card.id,
                               date: yesterday, merchant: "B"),
            Domain.Transaction(amountCents: 1_000, type: .expense, accountID: other.id,
                               date: yesterday, merchant: "C")
        ])

        let card = try #require(try await store.accounts.account(id: store.card.id))
        let chequing = try #require(try await store.accounts.account(id: other.id))
        // A card's balance is negative when money is owed (§4.1).
        #expect(card.cachedBalanceCents == -5_000)
        #expect(chequing.cachedBalanceCents == 99_000)
    }

    @Test("Saving an empty batch does nothing rather than failing")
    func emptyBatchIsSafe() async throws {
        let store = try await makeStore()

        try await store.transactions.saveAll([])

        let stored = try await store.transactions.transactions(accountID: store.card.id, in: nil)
        #expect(stored.isEmpty)
    }
}
