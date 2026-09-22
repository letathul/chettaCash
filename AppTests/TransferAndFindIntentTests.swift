import Foundation
import Testing
import AppIntents
@testable import Chetta_Cash
import Domain

/// Moving money and reading it back, from a Shortcut (§15.2, §15.3, §4.3).
@Suite("Transfer and Find intents")
@MainActor
struct TransferAndFindIntentTests {

    /// A fixed moment, so nothing depends on the wall clock.
    private var now: Date { Date(timeIntervalSince1970: 1_789_000_000) }

    /// The graph and the two accounts money moves between.
    private struct Harness {
        /// The in-memory dependency graph.
        let dependencies: AppDependencies
        /// A spending account.
        let chequing: Domain.Account
        /// A credit card carrying a balance.
        let card: Domain.Account
    }

    /// Builds an in-memory graph with an account and a card.
    /// - Parameter extras: Further accounts to save.
    /// - Returns: The harness.
    /// - Throws: A `SwiftDataError` if the schema fails validation.
    private func makeHarness(extras: [Domain.Account] = []) async throws -> Harness {
        let dependencies = try AppDependencies(inMemory: true)
        try await dependencies.prepare()
        AppEnvironment.replaceForTesting(with: dependencies)
        let chequing = Domain.Account(
            name: "Chequing", openingBalanceCents: 100_000,
            openingBalanceDate: now.addingTimeInterval(-86_400)
        )
        let card = Domain.Account(
            name: "Visa", kind: .card, openingBalanceCents: -50_000,
            openingBalanceDate: now.addingTimeInterval(-86_400), sortIndex: 1
        )
        try await dependencies.accounts.save(chequing)
        try await dependencies.accounts.save(card)
        for extra in extras { try await dependencies.accounts.save(extra) }
        return Harness(dependencies: dependencies, chequing: chequing, card: card)
    }

    /// An entity for an account.
    /// - Parameter account: The account.
    /// - Returns: The entity, as a saved Shortcut would hold it.
    private func entity(_ account: Domain.Account) -> AccountEntity {
        AccountEntity(id: account.id, name: account.name, last4: account.last4)
    }

    /// Builds a transfer intent.
    /// - Parameters:
    ///   - harness: The graph to point at.
    ///   - amount: The amount, in whole currency units.
    ///   - from: The source account.
    ///   - into: The destination account.
    /// - Returns: The intent.
    private func transfer(
        _ harness: Harness,
        amount: Double = 200,
        from: Domain.Account? = nil,
        into: Domain.Account? = nil
    ) -> TransferIntent {
        let intent = TransferIntent()
        intent.amount = amount
        intent.source = entity(from ?? harness.chequing)
        intent.destination = entity(into ?? harness.card)
        intent.date = now
        return intent
    }

    /// Every transaction currently stored.
    /// - Parameter harness: The graph to read.
    /// - Returns: The transactions.
    /// - Throws: A persistence error if the fetch fails.
    private func transactions(_ harness: Harness) async throws -> [Domain.Transaction] {
        try await harness.dependencies.transactions.transactions(accountID: nil, in: nil)
    }

    // MARK: - Transfer

    @Test("A transfer writes both legs, sharing a group")
    func writesBothLegs() async throws {
        let harness = try await makeHarness()

        _ = try await transfer(harness).perform()

        let stored = try await transactions(harness)
        #expect(stored.count == 2, "a half-transfer must never exist")
        let out = try #require(stored.first { $0.type == .transferOut })
        let into = try #require(stored.first { $0.type == .transferIn })
        #expect(out.transferGroupID == into.transferGroupID)
        #expect(out.accountID == harness.chequing.id)
        #expect(into.accountID == harness.card.id)
        #expect(out.amountCents == 20_000)
        #expect(out.categoryID == nil, "transfers have no category")
        #expect(into.categoryID == nil)
    }

    @Test("Paying a card moves its balance toward zero")
    func aCardPaymentReducesDebt() async throws {
        let harness = try await makeHarness()

        _ = try await transfer(harness).perform()

        let card = try #require(
            try await harness.dependencies.accounts.account(id: harness.card.id)
        )
        let chequing = try #require(
            try await harness.dependencies.accounts.account(id: harness.chequing.id)
        )
        #expect(card.cachedBalanceCents == -50_000 + 20_000)
        #expect(chequing.cachedBalanceCents == 100_000 - 20_000)
    }

    @Test("Neither leg counts toward spending")
    func transfersAreNotSpending() async throws {
        let harness = try await makeHarness()

        _ = try await transfer(harness).perform()

        let stored = try await transactions(harness)
        let spend = TotalsEngine.spendTotalCents(transactions: stored, in: nil, asOf: now)
        #expect(spend == 0, "counting a card payment would double-count every card purchase")
    }

    @Test("A transfer to the same account is refused, and writes nothing")
    func refusesTheSameAccount() async throws {
        let harness = try await makeHarness()
        let intent = transfer(harness, into: harness.chequing)

        await #expect(throws: TransferIntentError.self) { try await intent.perform() }

        let stored = try await transactions(harness)
        #expect(stored.isEmpty)
    }

    @Test("A transfer of nothing is refused", arguments: [0.0, -5.0])
    func refusesAnEmptyTransfer(_ amount: Double) async throws {
        let harness = try await makeHarness()
        let intent = transfer(harness, amount: amount)

        await #expect(throws: TransferIntentError.self) { try await intent.perform() }

        let stored = try await transactions(harness)
        #expect(stored.isEmpty, "two rows describing an event that did not happen")
    }

    @Test("A transfer through a closed account is refused rather than parked")
    func refusesAClosedEnd() async throws {
        let closed = Domain.Account(
            name: "Old Savings", sortIndex: 2, isClosed: true, closedDate: now
        )
        let harness = try await makeHarness(extras: [closed])
        let intent = transfer(harness, into: closed)

        await #expect(throws: TransferIntentError.self) { try await intent.perform() }

        let stored = try await transactions(harness)
        #expect(stored.isEmpty, "a transfer with one end missing is not an entry at all")
    }

    @Test("A transfer through an account that is gone is refused")
    func refusesAVanishedEnd() async throws {
        let harness = try await makeHarness()
        let intent = transfer(harness)
        intent.destination = AccountEntity(id: UUID(), name: "Deleted", last4: nil)

        await #expect(throws: TransferIntentError.self) { try await intent.perform() }

        let stored = try await transactions(harness)
        #expect(stored.isEmpty)
    }

    // MARK: - Find

    /// Builds a find intent over a window around ``now``.
    /// - Parameter harness: The graph to point at.
    /// - Returns: The intent.
    private func find(_ harness: Harness) -> FindTransactionsIntent {
        let intent = FindTransactionsIntent()
        intent.from = now.addingTimeInterval(-7 * 86_400)
        intent.until = now.addingTimeInterval(7 * 86_400)
        return intent
    }

    /// Saves an expense.
    /// - Parameters:
    ///   - harness: The graph to write to.
    ///   - merchant: The merchant.
    ///   - account: The account it belongs to.
    ///   - tags: The tags it carries.
    /// - Throws: A persistence error if the write fails.
    private func save(
        _ harness: Harness,
        merchant: String,
        account: Domain.Account,
        tags: [String] = []
    ) async throws {
        try await harness.dependencies.transactions.save(Domain.Transaction(
            amountCents: 1_000, type: .expense, accountID: account.id,
            date: now, merchant: merchant, tags: tags
        ))
    }

    @Test("Entries inside the window come back")
    func findsInsideTheWindow() async throws {
        let harness = try await makeHarness()
        try await save(harness, merchant: "Blue Bottle", account: harness.chequing)

        let found = try await find(harness).perform().value

        #expect(found?.count == 1)
        #expect(found?.first?.merchant == "Blue Bottle")
        #expect(found?.first?.accountName == "Chequing")
    }

    @Test("Dates handed over backwards are read as the range between them")
    func toleratesABackwardsRange() async throws {
        let harness = try await makeHarness()
        try await save(harness, merchant: "Blue Bottle", account: harness.chequing)
        let intent = find(harness)
        (intent.from, intent.until) = (intent.until, intent.from)

        let found = try await intent.perform().value

        #expect(found?.count == 1, "a Shortcut computing its own dates gets these the wrong way")
    }

    @Test("Restricting to one account leaves the other out")
    func filtersByAccount() async throws {
        let harness = try await makeHarness()
        try await save(harness, merchant: "Blue Bottle", account: harness.chequing)
        try await save(harness, merchant: "Petrol", account: harness.card)
        let intent = find(harness)
        intent.account = entity(harness.card)

        let found = try await intent.perform().value

        #expect(found?.map(\.merchant) == ["Petrol"])
    }

    @Test("Restricting by tag finds what a Shortcut logged")
    func filtersByTag() async throws {
        let harness = try await makeHarness()
        try await save(harness, merchant: "Typed in", account: harness.chequing)
        try await save(
            harness, merchant: "Blue Bottle", account: harness.chequing, tags: ["Shortcut"]
        )
        let intent = find(harness)
        intent.tag = "shortcut"

        let found = try await intent.perform().value

        #expect(found?.map(\.merchant) == ["Blue Bottle"], "tags match whatever the case")
    }

    @Test("The limit is honoured")
    func honoursTheLimit() async throws {
        let harness = try await makeHarness()
        for index in 0..<5 {
            try await save(harness, merchant: "Shop \(index)", account: harness.chequing)
        }
        let intent = find(harness)
        intent.limit = 2

        let found = try await intent.perform().value

        #expect(found?.count == 2)
    }

    @Test("Reading the ledger requires an unlocked device, unlike writing to it")
    func readingIsGated() {
        #expect(FindTransactionsIntent.authenticationPolicy == .requiresAuthentication)
        #expect(AddExpenseIntent.authenticationPolicy == .alwaysAllowed)
        #expect(
            TransferIntent.authenticationPolicy == .alwaysAllowed,
            "a write reveals nothing; a read reveals everything"
        )
    }
}
