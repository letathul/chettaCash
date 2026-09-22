import Foundation
import Testing
import AppIntents
import UIKit
@testable import Chetta_Cash
import Domain

/// What Siri may see and do while the phone is locked (§15.3, §11).
///
/// The rule itself is pure and tested in the fast Domain suite. What is pinned down here is
/// the wiring: which query methods consult it, which deliberately do not, and that writing
/// stays open.
@Suite("Add Expense and the app lock")
@MainActor
struct AddExpenseLockTests {

    /// Builds an in-memory graph with one account, and points the intent runtime at it.
    /// - Parameter lockEnabled: Whether the §11 app lock is on.
    /// - Returns: The graph and the account.
    /// - Throws: A `SwiftDataError` if the schema fails validation.
    private func makeHarness(
        lockEnabled: Bool
    ) async throws -> (dependencies: AppDependencies, account: Domain.Account) {
        let dependencies = try AppDependencies(inMemory: true)
        // Seeding moved out of `init` and off the main actor, so a harness that skips
        // it runs against a store no shipped build ever has.
        try await dependencies.prepare()
        dependencies.settings.appLockEnabled = lockEnabled
        AppEnvironment.replaceForTesting(with: dependencies)
        let account = Domain.Account(name: "Chequing", openingBalanceCents: 100_000, last4: "9087")
        try await dependencies.accounts.save(account)
        return (dependencies, account)
    }

    @Test("The picker lists accounts on an unlocked phone")
    func listsAccountsWhenUnlocked() async throws {
        _ = try await makeHarness(lockEnabled: true)

        let suggested = try await AccountEntityQuery().suggestedEntities()

        // The simulator runs with protected data available, so this is the unlocked case
        // whatever the lock setting says. The locked case is the Domain suite's to prove.
        #expect(UIApplication.shared.isProtectedDataAvailable)
        #expect(suggested.count == 1)
        #expect(suggested.first?.last4 == "9087")
    }

    @Test("Looking up an identifier the caller already holds is never withheld")
    func resolvesAKnownIdentifier() async throws {
        let harness = try await makeHarness(lockEnabled: true)

        let found = try await AccountEntityQuery().entities(for: [harness.account.id])

        #expect(
            found.first?.id == harness.account.id,
            "blanking this would break every saved Shortcut, including the write the owner wants"
        )
    }

    @Test("Logging an expense needs no authentication")
    func writingStaysOpen() async throws {
        let harness = try await makeHarness(lockEnabled: true)
        let intent = AddExpenseIntent()
        intent.amount = 4.20
        intent.merchant = "Blue Bottle"
        intent.account = AccountEntity(
            id: harness.account.id, name: harness.account.name, last4: "9087"
        )

        #expect(AddExpenseIntent.authenticationPolicy == .alwaysAllowed)

        _ = try await intent.perform()

        let stored = try await harness.dependencies.transactions.transactions(
            accountID: nil, in: nil
        )
        #expect(stored.count == 1, "a write discloses nothing, so it is not gated")
    }
}
