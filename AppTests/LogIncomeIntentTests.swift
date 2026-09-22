import Foundation
import Testing
import AppIntents
@testable import Chetta_Cash
import Domain

/// Recording money arriving, from a Shortcut (§15.2).
///
/// Log Income shares every decision with Add Expense through ``QuickEntryIntent``, so what is
/// pinned down here is the half that differs: the sign, the category context and the words —
/// plus enough of the shared path to prove the two really are one implementation.
@Suite("Log Income intent")
@MainActor
struct LogIncomeIntentTests {

    /// A fixed moment, so nothing depends on the wall clock.
    private var now: Date { Date(timeIntervalSince1970: 1_789_000_000) }

    /// The graph and the account an intent can be pointed at.
    private struct Harness {
        /// The in-memory dependency graph.
        let dependencies: AppDependencies
        /// An open account.
        let account: Domain.Account
    }

    /// Builds an in-memory graph with one account, and points the intent runtime at it.
    /// - Returns: The harness.
    /// - Throws: A `SwiftDataError` if the schema fails validation.
    private func makeHarness() async throws -> Harness {
        let dependencies = try AppDependencies(inMemory: true)
        try await dependencies.prepare()
        AppEnvironment.replaceForTesting(with: dependencies)
        let account = Domain.Account(name: "Chequing", openingBalanceCents: 100_000)
        try await dependencies.accounts.save(account)
        return Harness(dependencies: dependencies, account: account)
    }

    /// Builds an intent with the required parameters filled.
    /// - Parameters:
    ///   - harness: The graph to point at.
    ///   - amount: The amount, in whole currency units.
    /// - Returns: The intent.
    private func intent(_ harness: Harness, amount: Double = 2_500) -> LogIncomeIntent {
        let intent = LogIncomeIntent()
        intent.amount = amount
        intent.merchant = "Acme Ltd"
        intent.account = AccountEntity(
            id: harness.account.id, name: harness.account.name, last4: nil
        )
        intent.date = now
        intent.rememberCategory = true
        return intent
    }

    /// Every transaction currently stored.
    /// - Parameter harness: The graph to read.
    /// - Returns: The transactions.
    /// - Throws: A persistence error if the fetch fails.
    private func transactions(_ harness: Harness) async throws -> [Domain.Transaction] {
        try await harness.dependencies.transactions.transactions(accountID: nil, in: nil)
    }

    @Test("Income reaches the database as income, in cents")
    func recordsTheIncome() async throws {
        let harness = try await makeHarness()

        _ = try await intent(harness).perform()

        let stored = try #require(try await transactions(harness).first)
        #expect(stored.type == .income)
        #expect(stored.amountCents == 250_000, "the magnitude; the sign lives in the type")
        #expect(stored.merchant == "Acme Ltd")
    }

    @Test("The account's balance goes up, not down")
    func increasesTheBalance() async throws {
        let harness = try await makeHarness()

        _ = try await intent(harness).perform()

        let account = try #require(
            try await harness.dependencies.accounts.account(id: harness.account.id)
        )
        #expect(account.cachedBalanceCents == 100_000 + 250_000)
    }

    @Test("Income is filed under the income categories, not the expense ones")
    func usesTheIncomeCategoryList() async throws {
        let harness = try await makeHarness()
        let intent = intent(harness)
        intent.category = "Salary"

        _ = try await intent.perform()

        let income = try await harness.dependencies.categories
            .selectableCategories(context: .income)
        let salary = try #require(income.first { $0.label == "Salary" })
        let stored = try #require(try await transactions(harness).first)
        #expect(stored.categoryID == salary.id)
        let expense = try await harness.dependencies.categories
            .selectableCategories(context: .expense)
        #expect(
            expense.contains { $0.id == salary.id } == false,
            "a payer must not be filed into the spending list"
        )
    }

    @Test("Income carries the shortcut tag like everything else logged this way")
    func tagsItsOrigin() async throws {
        let harness = try await makeHarness()

        _ = try await intent(harness).perform()

        let stored = try #require(try await transactions(harness).first)
        #expect(stored.tags == ["shortcut"])
    }

    @Test("A repeated run is recognised, exactly as it is for an expense")
    func sharesTheDuplicateGuard() async throws {
        let harness = try await makeHarness()

        _ = try await intent(harness).perform()
        _ = try await intent(harness).perform()

        let stored = try await transactions(harness)
        #expect(stored.count == 1)
    }

    @Test("Income whose account cannot be settled is parked, not lost")
    func sharesTheParkingRule() async throws {
        let harness = try await makeHarness()
        let intent = intent(harness)
        intent.account = nil
        intent.accountName = "Chequng"

        _ = try await intent.perform()

        let stored = try #require(try await transactions(harness).first)
        #expect(stored.accountID == nil)
        #expect(stored.type == .income)
    }

    @Test("A negative amount is refused and nothing is written")
    func refusesANegativeAmount() async throws {
        let harness = try await makeHarness()
        let intent = intent(harness, amount: -5)

        await #expect(throws: QuickEntryError.self) { try await intent.perform() }

        let stored = try await transactions(harness)
        #expect(stored.isEmpty, "which way money moves is the type's business")
    }
}
