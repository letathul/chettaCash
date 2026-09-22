import Foundation
import Testing
@testable import Features
import Domain

/// Phase 6 acceptance criteria end to end: generation reaches the stores, and the
/// three edit and delete scopes persist correctly (§4.5).
@MainActor
@Suite("Recurring coordinator")
struct RecurringCoordinatorTests {

    /// The pieces under test, wired together.
    private struct Harness {
        /// The account repository fake.
        let accounts: FakeAccountRepository
        /// The transaction repository fake.
        let transactions: FakeTransactionRepository
        /// The rule repository fake.
        let rules: FakeRecurringRuleRepository
        /// The coordinator under test.
        let coordinator: RecurringCoordinator
        /// The account occurrences are recorded against.
        let account: Domain.Account
    }

    /// Builds a coordinator over empty stores.
    /// - Returns: The harness.
    private func makeHarness() async -> Harness {
        let accounts = FakeAccountRepository()
        let transactions = FakeTransactionRepository(accounts: accounts)
        let rules = FakeRecurringRuleRepository()
        let account = Domain.Account(name: "Chequing", openingBalanceCents: 500_000)
        try? await accounts.save(account)
        return Harness(
            accounts: accounts, transactions: transactions, rules: rules,
            coordinator: RecurringCoordinator(transactions: transactions, rules: rules),
            account: account
        )
    }

    /// Builds a monthly rule starting a number of days ago.
    /// - Parameters:
    ///   - harness: The harness under test.
    ///   - daysAgo: How far back the series starts.
    ///   - limit: An optional occurrence cap.
    /// - Returns: The saved rule.
    private func makeRule(
        _ harness: Harness,
        daysAgo: Int,
        limit: Int? = nil
    ) async -> Domain.RecurringRule {
        let rule = Domain.RecurringRule(
            name: "Rent",
            amountCents: 150_000,
            accountID: harness.account.id,
            frequency: .monthly,
            startDate: .now.addingTimeInterval(Double(-daysAgo) * 86_400),
            occurrenceLimit: limit
        )
        try? await harness.rules.save(rule)
        return rule
    }

    /// Fetches every stored occurrence of a rule, oldest first.
    /// - Parameters:
    ///   - harness: The harness under test.
    ///   - rule: The rule to list.
    /// - Returns: Its occurrences.
    private func occurrences(
        _ harness: Harness,
        of rule: Domain.RecurringRule
    ) async -> [Domain.Transaction] {
        let all = (try? await harness.transactions.transactions(accountID: nil, in: nil)) ?? []
        return all.filter { $0.recurringRuleID == rule.id }.sorted { $0.date < $1.date }
    }

    @Test("Reconcile writes missed occurrences and exactly one future one")
    func reconcileWritesOccurrences() async throws {
        let harness = await makeHarness()
        let rule = await makeRule(harness, daysAgo: 70)

        try await harness.coordinator.reconcile()

        let stored = await occurrences(harness, of: rule)
        #expect(stored.count == 4, "three monthly charges have passed, plus one upcoming")
        #expect(stored.filter { $0.date > .now }.count == 1)
        #expect(stored.map(\.date) == stored.map(\.date).sorted())
    }

    @Test("Reconcile is idempotent: a second pass writes nothing")
    func reconcileIsIdempotent() async throws {
        let harness = await makeHarness()
        let rule = await makeRule(harness, daysAgo: 70)
        try await harness.coordinator.reconcile()
        let firstCount = await occurrences(harness, of: rule).count

        let written = try await harness.coordinator.reconcile()

        #expect(written == 0)
        let secondCount = await occurrences(harness, of: rule).count
        #expect(secondCount == firstCount)
    }

    @Test("Posted occurrences update the account balance silently")
    func postedOccurrencesMoveTheBalance() async throws {
        let harness = await makeHarness()
        _ = await makeRule(harness, daysAgo: 40)

        try await harness.coordinator.reconcile()

        let account = try await harness.accounts.account(id: harness.account.id)
        #expect(account?.cachedBalanceCents == 500_000 - 300_000, "two charges have posted")
    }

    @Test("An occurrence limit stops generation and deactivates the rule")
    func limitDeactivatesRule() async throws {
        let harness = await makeHarness()
        let rule = await makeRule(harness, daysAgo: 100, limit: 2)

        try await harness.coordinator.reconcile()

        let stored = await occurrences(harness, of: rule)
        #expect(stored.count == 2)
        let updated = try await harness.rules.rule(id: rule.id)
        #expect(updated?.isActive == false)
    }

    @Test("Editing this occurrence only detaches it and leaves the series running")
    func editThisOccurrenceOnly() async throws {
        let harness = await makeHarness()
        let rule = await makeRule(harness, daysAgo: 70)
        try await harness.coordinator.reconcile()
        let stored = await occurrences(harness, of: rule)
        var edited = try #require(stored.first)
        edited.amountCents = 99_900

        try await harness.coordinator.applyEdit(
            rule: rule, target: stored[0], scope: .thisOccurrence, edited: edited
        )

        let after = await occurrences(harness, of: rule)
        #expect(after.first?.amountCents == 99_900)
        #expect(after.first?.isSeriesOverride == true)
        #expect(after.dropFirst().allSatisfy { $0.amountCents == 150_000 })
        let unchanged = try await harness.rules.rule(id: rule.id)
        #expect(unchanged?.amountCents == 150_000)
    }

    @Test("Editing this and future splits the series in two")
    func editThisAndFuture() async throws {
        let harness = await makeHarness()
        let rule = await makeRule(harness, daysAgo: 70)
        try await harness.coordinator.reconcile()
        let stored = await occurrences(harness, of: rule)
        var edited = stored[2]
        edited.amountCents = 175_000

        try await harness.coordinator.applyEdit(
            rule: rule, target: stored[2], scope: .thisAndFuture, edited: edited
        )

        let old = try await harness.rules.rule(id: rule.id)
        #expect(old?.isActive == false)
        #expect(harness.rules.rulesByID.count == 2)
        let successor = try #require(harness.rules.rulesByID.values.first { $0.id != rule.id })
        #expect(successor.amountCents == 175_000)

        let untouched = await occurrences(harness, of: rule)
        #expect(untouched.count == 2, "the first two stay with the old rule")
        #expect(untouched.allSatisfy { $0.amountCents == 150_000 })
        let moved = await occurrences(harness, of: successor)
        #expect(moved.count == 2)
        #expect(moved.allSatisfy { $0.amountCents == 175_000 })
    }

    @Test("Editing all including past rewrites already-recorded history")
    func editAllIncludingPast() async throws {
        let harness = await makeHarness()
        let rule = await makeRule(harness, daysAgo: 70)
        try await harness.coordinator.reconcile()
        let stored = await occurrences(harness, of: rule)
        var edited = stored[2]
        edited.amountCents = 120_000

        try await harness.coordinator.applyEdit(
            rule: rule, target: stored[2], scope: .allIncludingPast, edited: edited
        )

        let after = await occurrences(harness, of: rule)
        #expect(after.count == stored.count)
        #expect(after.allSatisfy { $0.amountCents == 120_000 })
        let updated = try await harness.rules.rule(id: rule.id)
        #expect(updated?.amountCents == 120_000)
    }

    @Test("Deleting one occurrence does not bring it back on the next reconcile")
    func deletedOccurrenceStaysDeleted() async throws {
        let harness = await makeHarness()
        let rule = await makeRule(harness, daysAgo: 70)
        try await harness.coordinator.reconcile()
        let stored = await occurrences(harness, of: rule)
        let pending = try #require(stored.last)

        try await harness.coordinator.applyDelete(
            rule: rule, target: pending, scope: .thisOccurrence
        )
        try await harness.coordinator.reconcile()

        let after = await occurrences(harness, of: rule)
        #expect(!after.contains { $0.id == pending.id })
        #expect(!after.contains { $0.date == pending.date }, "the cursor moved past this date")
    }

    @Test("Deleting this and future stops the series but keeps earlier history")
    func deleteThisAndFuture() async throws {
        let harness = await makeHarness()
        let rule = await makeRule(harness, daysAgo: 70)
        try await harness.coordinator.reconcile()
        let stored = await occurrences(harness, of: rule)

        try await harness.coordinator.applyDelete(
            rule: rule, target: stored[2], scope: .thisAndFuture
        )

        let after = await occurrences(harness, of: rule)
        #expect(after.count == 2)
        let updated = try await harness.rules.rule(id: rule.id)
        #expect(updated?.isActive == false)

        try await harness.coordinator.reconcile()
        let afterReconcile = await occurrences(harness, of: rule)
        #expect(afterReconcile.count == 2, "an ended series does not resume")
    }

    @Test("Deleting all including past removes every occurrence and the rule")
    func deleteAllIncludingPast() async throws {
        let harness = await makeHarness()
        let rule = await makeRule(harness, daysAgo: 70)
        try await harness.coordinator.reconcile()
        let stored = await occurrences(harness, of: rule)

        try await harness.coordinator.applyDelete(
            rule: rule, target: stored[0], scope: .allIncludingPast
        )

        #expect(await occurrences(harness, of: rule).isEmpty)
        #expect(try await harness.rules.rule(id: rule.id) == nil)
        let account = try await harness.accounts.account(id: harness.account.id)
        #expect(account?.cachedBalanceCents == 500_000, "balances revert with the history")
    }
}
