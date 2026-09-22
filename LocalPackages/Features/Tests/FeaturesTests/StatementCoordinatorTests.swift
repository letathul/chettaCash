import Foundation
import Testing
@testable import Features
import Domain

/// Phase 7 acceptance criteria end to end: a partial payment leaves the remainder
/// due, overflow is not allocated, and the interest prompt asks once (§4.6).
@MainActor
@Suite("Card statement coordinator")
struct StatementCoordinatorTests {

    /// The pieces under test, wired together.
    private struct Harness {
        /// The account repository fake.
        let accounts: FakeAccountRepository
        /// The transaction repository fake.
        let transactions: FakeTransactionRepository
        /// The statement repository fake.
        let statements: FakeCardStatementRepository
        /// The coordinator under test.
        let coordinator: StatementCoordinator
        /// The card under test.
        let card: Domain.Account
    }

    /// Builds a card closing on the 5th, opened three months ago.
    /// - Returns: The harness.
    private func makeHarness() async -> Harness {
        let accounts = FakeAccountRepository()
        let transactions = FakeTransactionRepository(accounts: accounts)
        let statements = FakeCardStatementRepository()
        let card = Domain.Account(
            name: "TD Visa",
            kind: .card,
            openingBalanceDate: .now.addingTimeInterval(-90 * 86_400),
            statementDayOfMonth: 5,
            paymentDueDayOfMonth: 25
        )
        try? await accounts.save(card)
        return Harness(
            accounts: accounts, transactions: transactions, statements: statements,
            coordinator: StatementCoordinator(statements: statements, transactions: transactions),
            card: card
        )
    }

    /// Records a charge on the card.
    /// - Parameters:
    ///   - harness: The harness under test.
    ///   - cents: The amount.
    ///   - daysAgo: How long ago it happened.
    private func charge(_ harness: Harness, cents: Int, daysAgo: Int) async {
        try? await harness.transactions.save(Domain.Transaction(
            amountCents: cents, type: .expense, accountID: harness.card.id,
            date: .now.addingTimeInterval(Double(-daysAgo) * 86_400)
        ))
    }

    /// Records a payment onto the card.
    /// - Parameters:
    ///   - harness: The harness under test.
    ///   - cents: The amount.
    ///   - daysAgo: How long ago it happened.
    private func pay(_ harness: Harness, cents: Int, daysAgo: Int) async {
        try? await harness.transactions.save(Domain.Transaction(
            amountCents: cents, type: .transferIn, accountID: harness.card.id,
            date: .now.addingTimeInterval(Double(-daysAgo) * 86_400),
            transferGroupID: UUID()
        ))
    }

    @Test("Reconciling generates statements for every closed period")
    func generatesStatements() async throws {
        let harness = await makeHarness()
        await charge(harness, cents: 10_000, daysAgo: 80)

        try await harness.coordinator.reconcile(account: harness.card)

        let summaries = try await harness.coordinator.summaries(for: harness.card)
        #expect(summaries.count >= 2)
        #expect(summaries.allSatisfy { $0.statement.accountID == harness.card.id })
    }

    @Test("A partial payment leaves the remainder due")
    func partialPaymentLeavesRemainder() async throws {
        let harness = await makeHarness()
        await charge(harness, cents: 10_000, daysAgo: 80)
        await pay(harness, cents: 4_000, daysAgo: 50)

        try await harness.coordinator.reconcile(account: harness.card)

        let summaries = try await harness.coordinator.summaries(for: harness.card)
        let paid = try #require(summaries.first { $0.paidCents > 0 })
        #expect(paid.balanceCents == 10_000)
        #expect(paid.paidCents == 4_000)
        #expect(paid.outstandingCents == 6_000)
        #expect(paid.isPartiallyPaid)
    }

    @Test("Overflow beyond the statement is not allocated")
    func overflowIsNotAllocated() async throws {
        let harness = await makeHarness()
        await charge(harness, cents: 10_000, daysAgo: 80)
        await pay(harness, cents: 15_000, daysAgo: 50)

        try await harness.coordinator.reconcile(account: harness.card)

        let summaries = try await harness.coordinator.summaries(for: harness.card)
        let totalAllocated = summaries.reduce(0) { $0 + $1.paidCents }
        #expect(totalAllocated == 10_000, "only the statement balance is allocated")

        let account = try await harness.accounts.account(id: harness.card.id)
        #expect(account?.cachedBalanceCents == 5_000, "the overflow still reduced the balance")
    }

    @Test("Reconciling twice does not double-allocate")
    func reconcileIsIdempotent() async throws {
        let harness = await makeHarness()
        await charge(harness, cents: 10_000, daysAgo: 80)
        await pay(harness, cents: 4_000, daysAgo: 50)
        try await harness.coordinator.reconcile(account: harness.card)
        let first = try await harness.coordinator.summaries(for: harness.card)

        try await harness.coordinator.reconcile(account: harness.card)

        let second = try await harness.coordinator.summaries(for: harness.card)
        #expect(second.count == first.count)
        #expect(second.reduce(0) { $0 + $1.paidCents } == first.reduce(0) { $0 + $1.paidCents })
    }

    @Test("The interest prompt appears once and never again after dismissal")
    func interestPromptAsksOnce() async throws {
        let harness = await makeHarness()
        await charge(harness, cents: 10_000, daysAgo: 80)
        try await harness.coordinator.reconcile(account: harness.card)
        let summaries = try await harness.coordinator.summaries(for: harness.card)
        let statement = try #require(
            summaries.map(\.statement).first { InterestPrompt.shouldAsk(about: $0) }
        )

        try await harness.coordinator.resolveInterestPrompt(
            for: statement, cents: nil, billsCategoryID: nil
        )

        let after = try await harness.coordinator.summaries(for: harness.card)
        let resolved = try #require(after.first { $0.statement.id == statement.id })
        #expect(InterestPrompt.shouldAsk(about: resolved.statement) == false)

        try await harness.coordinator.reconcile(account: harness.card)
        let afterReconcile = try await harness.coordinator.summaries(for: harness.card)
        let stillResolved = try #require(afterReconcile.first { $0.statement.id == statement.id })
        #expect(stillResolved.statement.interestPromptResolved, "reconciling must not re-ask")
    }

    @Test("An entered interest amount becomes a charge on the card")
    func interestBecomesCharge() async throws {
        let harness = await makeHarness()
        await charge(harness, cents: 10_000, daysAgo: 80)
        try await harness.coordinator.reconcile(account: harness.card)
        let summaries = try await harness.coordinator.summaries(for: harness.card)
        let statement = try #require(
            summaries.map(\.statement).first { InterestPrompt.shouldAsk(about: $0) }
        )
        let bills = UUID()

        try await harness.coordinator.resolveInterestPrompt(
            for: statement, cents: 1_250, billsCategoryID: bills
        )

        let stored = try await harness.transactions.transactions(accountID: nil, in: nil)
        let interest = try #require(stored.first { $0.merchant == "Interest and fees" })
        #expect(interest.amountCents == 1_250)
        #expect(interest.categoryID == bills)
        #expect(interest.date == statement.closingDate)
    }

    @Test("An override replaces the computed statement balance")
    func overrideReplacesComputed() async throws {
        let harness = await makeHarness()
        await charge(harness, cents: 10_000, daysAgo: 80)
        try await harness.coordinator.reconcile(account: harness.card)
        let summaries = try await harness.coordinator.summaries(for: harness.card)
        let statement = try #require(summaries.first { $0.balanceCents == 10_000 }).statement

        try await harness.coordinator.setOverride(on: statement, cents: 10_450)

        let after = try await harness.coordinator.summaries(for: harness.card)
        let overridden = try #require(after.first { $0.statement.id == statement.id })
        #expect(overridden.balanceCents == 10_450)
        #expect(overridden.statement.computedBalanceCents == 10_000, "the computed figure is kept")
    }

    @Test("A spending account never gets statements")
    func spendingAccountsHaveNoStatements() async throws {
        let harness = await makeHarness()
        let chequing = Domain.Account(name: "Chequing", kind: .account)
        try await harness.accounts.save(chequing)

        try await harness.coordinator.reconcile(account: chequing)

        #expect(try await harness.coordinator.summaries(for: chequing).isEmpty)
    }
}
