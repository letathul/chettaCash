import Foundation
import SwiftData
import Testing
import Domain
@testable import Data

/// A transaction may be unassigned, but it may never point at an account that is not there
/// (§15.5).
///
/// The distinction is the whole point. `accountID == nil` is a parked entry: the Shortcut
/// could not work out where the money came from, said so, and left it for the user. An
/// `accountID` naming a row that does not exist is a different thing entirely — it looks
/// filed but is not, so it shows in the Ledger and counts toward spend totals while no
/// balance moves and nothing announces it.
@Suite("Transaction account integrity")
struct TransactionAccountIntegrityTests {

    /// The pieces under test, wired together.
    private struct Harness {
        /// The account repository.
        let accounts: SwiftDataAccountRepository
        /// The transaction repository.
        let transactions: SwiftDataTransactionRepository
        /// An account that really exists.
        let account: Domain.Account
    }

    /// Builds an in-memory stack with one account already saved.
    /// - Returns: The harness.
    private func makeStore() async throws -> Harness {
        let container = try ModelContainerFactory.make(inMemory: true)
        let accounts = SwiftDataAccountRepository(modelContainer: container)
        let transactions = SwiftDataTransactionRepository(modelContainer: container)
        let account = Domain.Account(name: "Chequing", openingBalanceCents: 100_000)
        try await accounts.save(account)
        return Harness(accounts: accounts, transactions: transactions, account: account)
    }

    @Test("A transaction naming an account that does not exist is refused")
    func refusesAnUnknownAccount() async throws {
        let store = try await makeStore()
        let missing = UUID()
        let stray = Domain.Transaction(
            amountCents: 4_210, type: .expense, accountID: missing, merchant: "Whole Foods"
        )

        await #expect(throws: TransactionRepositoryError.unknownAccount(missing)) {
            try await store.transactions.save(stray)
        }

        let stored = try await store.transactions.transactions(accountID: nil, in: nil)
        #expect(stored.isEmpty, "a refused write leaves nothing behind")
    }

    @Test("A transaction with no account at all is written, because that is a parked entry")
    func acceptsAnUnassignedTransaction() async throws {
        let store = try await makeStore()
        let parked = Domain.Transaction(
            amountCents: 4_210, type: .expense, accountID: nil, merchant: "Whole Foods"
        )

        try await store.transactions.save(parked)

        let stored = try await store.transactions.transactions(accountID: nil, in: nil)
        #expect(stored.count == 1)
        #expect(stored.first?.accountID == nil)
    }

    @Test("Assigning a parked entry moves the balance it was always going to move")
    func assigningAParkedEntryMovesTheBalance() async throws {
        let store = try await makeStore()
        var parked = Domain.Transaction(
            amountCents: 4_210, type: .expense, accountID: nil, merchant: "Whole Foods"
        )
        try await store.transactions.save(parked)

        let before = try await store.accounts.account(id: store.account.id)
        #expect(before?.cachedBalanceCents == 100_000, "an unassigned entry moves nothing")

        parked.accountID = store.account.id
        try await store.transactions.save(parked)

        let after = try await store.accounts.account(id: store.account.id)
        #expect(after?.cachedBalanceCents == 100_000 - 4_210)
    }

    @Test("A bulk write refuses wholesale when any row names an unknown account")
    func refusesAnUnknownAccountInBulk() async throws {
        let store = try await makeStore()
        let good = Domain.Transaction(
            amountCents: 500, type: .expense, accountID: store.account.id, merchant: "Cafe"
        )
        let stray = Domain.Transaction(
            amountCents: 700, type: .expense, accountID: UUID(), merchant: "Ghost"
        )

        await #expect(throws: TransactionRepositoryError.self) {
            try await store.transactions.saveAll([good, stray])
        }

        let stored = try await store.transactions.transactions(accountID: nil, in: nil)
        #expect(stored.isEmpty, "saveAll commits once, so a refusal writes none of the batch")
    }
}
