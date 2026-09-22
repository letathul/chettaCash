import Foundation
import Testing
import AppIntents
@testable import Chetta_Cash
import Domain

/// Pointing a Shortcut's expense at an account by number or name (§15.4, §15.5, §9.7).
///
/// The pure decision is pinned down in the fast Domain suite. What is pinned down here is
/// the wiring: that a number reaches the right account, that a number naming no account
/// creates one *before* the transaction points at it — the ordering the balance cache
/// depends on — and that every doubt still writes the expense, parked, rather than losing
/// what the user said.
@Suite("Add Expense account resolution")
@MainActor
struct AddExpenseAccountTests {

    /// A fixed moment, so nothing depends on the wall clock.
    private var now: Date { Date(timeIntervalSince1970: 1_789_000_000) }

    /// The graph and the accounts an intent can be pointed at.
    private struct Harness {
        /// The in-memory dependency graph.
        let dependencies: AppDependencies
        /// An open account carrying no card digits.
        let chequing: Domain.Account
        /// An open card ending in 9087.
        let amex: Domain.Account
    }

    /// Builds an in-memory graph and points the intent runtime at it.
    /// - Parameter extras: Further accounts to save, such as a colliding pair.
    /// - Returns: The harness.
    /// - Throws: A `SwiftDataError` if the schema fails validation.
    private func makeHarness(extras: [Domain.Account] = []) async throws -> Harness {
        let dependencies = try AppDependencies(inMemory: true)
        // Seeding moved out of `init` and off the main actor, so a harness that skips
        // it runs against a store no shipped build ever has.
        try await dependencies.prepare()
        AppEnvironment.replaceForTesting(with: dependencies)
        let chequing = Domain.Account(name: "Chequing", openingBalanceCents: 100_000)
        let amex = Domain.Account(
            name: "Amex", kind: .card, sortIndex: 1, last4: "9087"
        )
        try await dependencies.accounts.save(chequing)
        try await dependencies.accounts.save(amex)
        for extra in extras { try await dependencies.accounts.save(extra) }
        return Harness(dependencies: dependencies, chequing: chequing, amex: amex)
    }

    /// Builds an intent that names its account by text rather than by picker.
    /// - Parameters:
    ///   - number: The account number to pass.
    ///   - name: The account name to pass.
    /// - Returns: The intent.
    private func intent(number: String? = nil, name: String? = nil) -> AddExpenseIntent {
        let intent = AddExpenseIntent()
        intent.amount = 42.10
        intent.merchant = "Whole Foods"
        intent.accountNumber = number
        intent.accountName = name
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

    /// Every account currently stored, closed ones included.
    /// - Parameter harness: The graph to read.
    /// - Returns: The accounts.
    /// - Throws: A persistence error if the fetch fails.
    private func accounts(_ harness: Harness) async throws -> [Domain.Account] {
        try await harness.dependencies.accounts.accounts(includeClosed: true)
    }

    // MARK: - Matching an account that exists

    @Test("A number alone reaches the account carrying those digits")
    func matchesByNumber() async throws {
        let harness = try await makeHarness()

        _ = try await intent(number: "9087").perform()

        let stored = try #require(try await transactions(harness).first)
        #expect(stored.accountID == harness.amex.id)
        let all = try await accounts(harness)
        #expect(all.count == 2, "an account that already exists is never duplicated")
    }

    @Test("A full number is reduced to the digits the account carries")
    func matchesByFullNumber() async throws {
        let harness = try await makeHarness()

        _ = try await intent(number: "4532 1122 3344 9087").perform()

        let stored = try #require(try await transactions(harness).first)
        #expect(stored.accountID == harness.amex.id)
    }

    @Test("The number overrules an account picked in the editor")
    func numberBeatsThePicker() async throws {
        let harness = try await makeHarness()
        let intent = intent(number: "9087")
        intent.account = AccountEntity(id: harness.chequing.id, name: "Chequing", last4: nil)

        _ = try await intent.perform()

        let stored = try #require(try await transactions(harness).first)
        #expect(stored.accountID == harness.amex.id)
    }

    @Test("A blank number falls back to the picked account")
    func blankNumberFallsBackToThePicker() async throws {
        let harness = try await makeHarness()
        let intent = intent(number: "  ")
        intent.account = AccountEntity(id: harness.chequing.id, name: "Chequing", last4: nil)

        _ = try await intent.perform()

        let stored = try #require(try await transactions(harness).first)
        #expect(stored.accountID == harness.chequing.id)
    }

    // MARK: - Creating one that does not

    @Test("A number naming no account creates it, and the expense lands on it")
    func createsTheMissingAccount() async throws {
        let harness = try await makeHarness()

        _ = try await intent(number: "5555", name: "Travel Card").perform()

        let created = try #require(
            try await accounts(harness).first { $0.last4 == "5555" }
        )
        #expect(created.name == "Travel Card")
        #expect(created.kind == .card)
        #expect(created.openingBalanceCents == 0)
        #expect(created.isClosed == false)

        let stored = try #require(try await transactions(harness).first)
        #expect(stored.accountID == created.id, "the account must exist before this points at it")
        #expect(
            created.cachedBalanceCents == -4_210,
            "a balance cache of zero would mean the transaction never reached the account"
        )
    }

    @Test("A created account with no name given still says which card it is")
    func createdAccountNamesItself() async throws {
        let harness = try await makeHarness()

        _ = try await intent(number: "5555").perform()

        let created = try #require(
            try await accounts(harness).first { $0.last4 == "5555" }
        )
        #expect(created.name == "Card ••5555")
    }

    @Test("Running the same number twice matches the card rather than creating a second")
    func createsOnlyOnce() async throws {
        let harness = try await makeHarness()
        let second = intent(number: "5555", name: "Travel Card")
        // Two identical runs are otherwise one repeat (§15.6), and this test is about the
        // card, not the entry: both expenses have to land for the question to be asked.
        second.allowsDuplicate = true

        _ = try await intent(number: "5555", name: "Travel Card").perform()
        _ = try await second.perform()

        let created = try await accounts(harness).filter { $0.last4 == "5555" }
        #expect(created.count == 1)
        let stored = try await transactions(harness)
        #expect(stored.count == 2)
        #expect(stored.allSatisfy { $0.accountID == created.first?.id })
    }

    // MARK: - Matching by name

    @Test("A name alone reaches the account that answers to it")
    func matchesByName() async throws {
        let harness = try await makeHarness()

        _ = try await intent(name: "Amex").perform()

        let stored = try #require(try await transactions(harness).first)
        #expect(stored.accountID == harness.amex.id)
        let all = try await accounts(harness)
        #expect(all.count == 2, "an account that already exists is never duplicated")
    }

    @Test("A name matches whatever the case")
    func matchesNameLoosely() async throws {
        let harness = try await makeHarness()

        _ = try await intent(name: "  amex  ").perform()

        let stored = try #require(try await transactions(harness).first)
        #expect(stored.accountID == harness.amex.id)
    }

    @Test("The number overrules the name when both are given")
    func numberBeatsName() async throws {
        let harness = try await makeHarness()

        _ = try await intent(number: "9087", name: "Chequing").perform()

        let stored = try #require(try await transactions(harness).first)
        #expect(stored.accountID == harness.amex.id)
    }

    @Test("A name naming no account parks the expense rather than minting a card")
    func parksOnAnUnrecognisedName() async throws {
        let harness = try await makeHarness()

        _ = try await intent(name: "Apple Card").perform()

        let all = try await accounts(harness)
        #expect(
            all.count == 2,
            "a name is a string that might be a typo — four digits name a card that exists"
        )
        let stored = try #require(try await transactions(harness).first)
        #expect(stored.accountID == nil, "written, but waiting for the user to say where")
        #expect(stored.amountCents == 4_210)
    }

    // MARK: - Doubt parks the expense, and never loses it

    @Test("A name reaching several accounts parks the expense and creates nothing")
    func parksOnAnAmbiguousName() async throws {
        let harness = try await makeHarness(extras: [
            Domain.Account(name: "Visa Gold", kind: .card, sortIndex: 2),
            Domain.Account(name: "Visa Platinum", kind: .card, sortIndex: 3)
        ])

        _ = try await intent(name: "Visa").perform()

        let stored = try #require(try await transactions(harness).first)
        #expect(stored.accountID == nil, "posting to the wrong balance is worse than parking")
        let all = try await accounts(harness)
        #expect(all.count == 4, "an ambiguous name never creates one more beside them")
    }

    @Test("A number naming several accounts parks the expense and creates nothing")
    func parksOnAnAmbiguousNumber() async throws {
        let harness = try await makeHarness(extras: [
            Domain.Account(name: "Visa", kind: .card, sortIndex: 2, last4: "5555"),
            Domain.Account(name: "Mastercard", kind: .card, sortIndex: 3, last4: "5555")
        ])

        _ = try await intent(number: "5555").perform()

        let stored = try #require(try await transactions(harness).first)
        #expect(stored.accountID == nil, "posting to the wrong balance is worse than parking")
        let all = try await accounts(harness)
        #expect(all.count == 4, "an ambiguous number never creates a third card beside them")
    }

    @Test("A number too short to name a card parks the expense and creates nothing")
    func parksOnAShortNumber() async throws {
        let harness = try await makeHarness()

        _ = try await intent(number: "12", name: "Travel Card").perform()

        let stored = try #require(try await transactions(harness).first)
        #expect(stored.accountID == nil)
        let all = try await accounts(harness)
        #expect(all.count == 2)
    }

    @Test("A parked expense moves no balance until it is assigned")
    func aParkedExpenseMovesNoBalance() async throws {
        let harness = try await makeHarness()

        _ = try await intent(name: "Chequng").perform()

        let untouched = try #require(
            try await harness.dependencies.accounts.account(id: harness.chequing.id)
        )
        #expect(untouched.cachedBalanceCents == 100_000, "the typo charged nobody")
    }

    @Test("An expense whose picked account has since been closed is parked, not posted")
    func parksOnAClosedPickedAccount() async throws {
        let closed = Domain.Account(
            name: "Old Chequing", sortIndex: 2, isClosed: true, closedDate: .now
        )
        let harness = try await makeHarness(extras: [closed])
        let intent = intent()
        intent.account = AccountEntity(id: closed.id, name: closed.name, last4: nil)

        _ = try await intent.perform()

        let stored = try #require(try await transactions(harness).first)
        #expect(stored.accountID == nil, "closed accounts are kept for history, not new money")
    }

    @Test("An expense whose picked account is gone is parked rather than filed at nothing")
    func parksOnAVanishedPickedAccount() async throws {
        let harness = try await makeHarness()
        let intent = intent()
        intent.account = AccountEntity(id: UUID(), name: "Deleted", last4: nil)

        _ = try await intent.perform()

        let stored = try #require(try await transactions(harness).first)
        #expect(
            stored.accountID == nil,
            "an identifier naming nothing would file the expense against nothing, silently"
        )
    }

    @Test("A closed account carrying the digits is not reused")
    func skipsAClosedAccount() async throws {
        let harness = try await makeHarness(extras: [
            Domain.Account(
                name: "Old Card", kind: .card, sortIndex: 2,
                isClosed: true, closedDate: .now, last4: "5555"
            )
        ])

        _ = try await intent(number: "5555", name: "New Card").perform()

        let open = try await harness.dependencies.accounts.accounts(includeClosed: false)
        let created = try #require(open.first { $0.last4 == "5555" })
        #expect(created.name == "New Card")
        let stored = try #require(try await transactions(harness).first)
        #expect(stored.accountID == created.id)
    }
}
