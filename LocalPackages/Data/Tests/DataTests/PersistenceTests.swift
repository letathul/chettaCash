import Foundation
import SwiftData
import Testing
import Domain
@testable import Data

/// Phase 1 acceptance criteria: the schema validates and seeding is idempotent.
@Suite("Model container and seeding")
struct PersistenceTests {

    @Test("The container initialises against the full schema")
    func containerInitialises() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        #expect(container.schema.entities.count == 10)
    }

    @Test("Seeding inserts the built-in categories")
    func seedingInsertsCategories() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)

        try CategorySeeder.seedIfNeeded(context: context)

        let all = try context.fetch(FetchDescriptor<CategoryRecord>())
        #expect(all.count == 14)
        #expect(all.filter { $0.context == .expense && !SystemCategoryID.isSystem($0.id) }.count == 6)
        #expect(all.filter { $0.context == .income }.count == 2)
        #expect(all.filter { $0.context == .product }.count == 4)
        let everyCategoryIsBuiltIn = all.allSatisfy(\.isBuiltIn)
        #expect(everyCategoryIsBuiltIn)
    }

    @Test("Seeding twice produces no duplicates")
    func seedingIsIdempotent() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)

        try CategorySeeder.seedIfNeeded(context: context)
        try CategorySeeder.seedIfNeeded(context: context)

        let all = try context.fetch(FetchDescriptor<CategoryRecord>())
        #expect(all.count == 14)
        #expect(Set(all.map(\.id)).count == 14)
    }

    @Test("The system categories are seeded with fixed identifiers and hidden from pickers")
    func systemCategoriesAreHidden() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        try CategorySeeder.seedIfNeeded(context: ModelContext(container))
        let repository = SwiftDataCategoryRepository(modelContainer: container)

        let selectable = try await repository.selectableCategories(context: .expense)
        let all = try await repository.allCategories()

        #expect(all.contains { $0.id == SystemCategoryID.transfer })
        #expect(all.contains { $0.id == SystemCategoryID.balanceAdjustment })
        #expect(selectable.allSatisfy { !SystemCategoryID.isSystem($0.id) })
        #expect(selectable.count == 6)
    }
}

/// Verifies the Data layer honours the money rules the Domain engines define.
@Suite("Repository behaviour")
struct RepositoryTests {

    /// A container seeded with one chequing account and one card.
    private struct Fixture {
        /// The in-memory container.
        let container: ModelContainer
        /// The chequing account, opening at $1,000.00.
        let chequing: Domain.Account
        /// The credit card, opening at $200.00 owed.
        let card: Domain.Account
    }

    /// Builds a container seeded with one chequing account and one card.
    /// - Returns: The fixture.
    private func makeFixture() async throws -> Fixture {
        let container = try ModelContainerFactory.make(inMemory: true)
        let accounts = SwiftDataAccountRepository(modelContainer: container)
        let chequing = Domain.Account(name: "Chequing", openingBalanceCents: 100_000)
        let card = Domain.Account(name: "TD Visa", kind: .card, openingBalanceCents: -20_000)
        try await accounts.save(chequing)
        try await accounts.save(card)
        return Fixture(container: container, chequing: chequing, card: card)
    }

    @Test("An account's card details survive a save and a reload")
    func cardDetailsRoundTrip() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let accounts = SwiftDataAccountRepository(modelContainer: container)
        var card = Domain.Account(name: "TD Visa", kind: .card)
        card.last4 = "4821"
        card.cardNetwork = .visa
        try await accounts.save(card)

        let reloaded = try await accounts.account(id: card.id)

        #expect(reloaded?.last4 == "4821")
        #expect(reloaded?.cardNetwork == .visa)
    }

    @Test("An account saved without card details reads back with none")
    func absentCardDetailsRoundTrip() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let accounts = SwiftDataAccountRepository(modelContainer: container)
        let plain = Domain.Account(name: "Chequing")
        try await accounts.save(plain)

        let reloaded = try await accounts.account(id: plain.id)

        #expect(reloaded?.last4 == nil)
        #expect(reloaded?.cardNetwork == nil)
    }

    @Test("Saving a transaction refreshes the account's balance cache")
    func balanceCacheIsRefreshed() async throws {
        let fixture = try await makeFixture()
        let (container, chequing) = (fixture.container, fixture.chequing)
        let accounts = SwiftDataAccountRepository(modelContainer: container)
        let transactions = SwiftDataTransactionRepository(modelContainer: container)

        try await transactions.save(
            Domain.Transaction(
                amountCents: 2_500,
                type: .expense,
                accountID: chequing.id,
                date: .now.addingTimeInterval(-3_600)
            )
        )

        let stored = try await accounts.account(id: chequing.id)
        #expect(stored?.cachedBalanceCents == 97_500)
    }

    @Test("A future-dated transaction leaves the cached balance untouched")
    func futureTransactionDoesNotAffectCache() async throws {
        let fixture = try await makeFixture()
        let (container, chequing) = (fixture.container, fixture.chequing)
        let accounts = SwiftDataAccountRepository(modelContainer: container)
        let transactions = SwiftDataTransactionRepository(modelContainer: container)

        try await transactions.save(
            Domain.Transaction(
                amountCents: 2_500,
                type: .expense,
                accountID: chequing.id,
                date: .now.addingTimeInterval(86_400 * 5)
            )
        )

        let stored = try await accounts.account(id: chequing.id)
        #expect(stored?.cachedBalanceCents == 100_000)
    }

    @Test("Deleting one transfer leg deletes both and rebuilds both caches")
    func deletingOneLegDeletesBoth() async throws {
        let fixture = try await makeFixture()
        let (container, chequing, card) = (fixture.container, fixture.chequing, fixture.card)
        let accounts = SwiftDataAccountRepository(modelContainer: container)
        let transactions = SwiftDataTransactionRepository(modelContainer: container)
        let legs = try TransferFactory.makeLegs(
            amountCents: 5_000,
            date: .now.addingTimeInterval(-3_600),
            sourceAccountID: chequing.id,
            destinationAccountID: card.id
        )
        try await transactions.saveTransfer(outLeg: legs.out, inLeg: legs.in)
        let cardAfterPayment = try await accounts.account(id: card.id)
        #expect(cardAfterPayment?.cachedBalanceCents == -15_000)

        try await transactions.delete(id: legs.out.id)

        let remaining = try await transactions.transactions(accountID: nil, in: nil)
        let sourceAfterDelete = try await accounts.account(id: chequing.id)
        let cardAfterDelete = try await accounts.account(id: card.id)
        #expect(remaining.isEmpty, "A half-transfer must never exist in the database")
        #expect(sourceAfterDelete?.cachedBalanceCents == 100_000)
        #expect(cardAfterDelete?.cachedBalanceCents == -20_000)
    }

    @Test("Recalculating rebuilds every cache from scratch")
    func recalculateRebuildsCaches() async throws {
        let fixture = try await makeFixture()
        let (container, chequing) = (fixture.container, fixture.chequing)
        let accounts = SwiftDataAccountRepository(modelContainer: container)
        let transactions = SwiftDataTransactionRepository(modelContainer: container)
        try await transactions.save(
            Domain.Transaction(
                amountCents: 1_000,
                type: .income,
                accountID: chequing.id,
                date: .now.addingTimeInterval(-3_600)
            )
        )

        try await accounts.recalculateAllBalances()

        let rebuilt = try await accounts.account(id: chequing.id)
        #expect(rebuilt?.cachedBalanceCents == 101_000)
    }

    @Test("Saving an edited transaction updates it rather than duplicating it")
    func savingEditedTransactionUpserts() async throws {
        let fixture = try await makeFixture()
        let (container, chequing) = (fixture.container, fixture.chequing)
        let accounts = SwiftDataAccountRepository(modelContainer: container)
        let transactions = SwiftDataTransactionRepository(modelContainer: container)
        var entry = Domain.Transaction(
            amountCents: 2_500,
            type: .expense,
            accountID: chequing.id,
            date: .now.addingTimeInterval(-3_600),
            merchant: "Original"
        )
        try await transactions.save(entry)

        entry.amountCents = 4_000
        entry.merchant = "Renamed"
        try await transactions.save(entry)

        let stored = try await transactions.transactions(accountID: nil, in: nil)
        #expect(stored.count == 1)
        #expect(stored.first?.merchant == "Renamed")
        let account = try await accounts.account(id: chequing.id)
        #expect(account?.cachedBalanceCents == 96_000)
    }

    @Test("Closed accounts are excluded from pickers but remain fetchable")
    func closedAccountsStayFetchable() async throws {
        let fixture = try await makeFixture()
        let (container, chequing) = (fixture.container, fixture.chequing)
        let accounts = SwiftDataAccountRepository(modelContainer: container)
        var closing = chequing
        closing.isClosed = true
        closing.closedDate = .now

        try await accounts.save(closing)

        let visible = try await accounts.accounts(includeClosed: false)
        let everything = try await accounts.accounts(includeClosed: true)
        #expect(visible.count == 1)
        #expect(everything.count == 2)
    }
}
