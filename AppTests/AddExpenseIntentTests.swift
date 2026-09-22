import Foundation
import Testing
import AppIntents
import UIKit
@testable import Chetta_Cash
import Domain

/// Logging an expense from a Shortcut, end to end (§4.2, §9.3).
///
/// Hosted by the app because the intent, the composition root and the SwiftData
/// container only exist there. What the planner decides is pinned down in the fast
/// Domain suite; what is pinned down here is the wiring — that the decision reaches
/// the database, with the right cents, the right receipt and the right pin.
@Suite("Add Expense intent")
@MainActor
struct AddExpenseIntentTests {

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
        // Seeding moved out of `init` and off the main actor, so a harness that skips
        // it runs against a store no shipped build ever has.
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
    private func intent(_ harness: Harness, amount: Double = 42.10) -> AddExpenseIntent {
        let intent = AddExpenseIntent()
        intent.amount = amount
        intent.merchant = "Whole Foods"
        intent.account = AccountEntity(
            id: harness.account.id, name: harness.account.name, last4: harness.account.last4
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

    @Test("An expense reaches the database with the amount in cents")
    func recordsTheExpense() async throws {
        let harness = try await makeHarness()
        let intent = intent(harness)

        _ = try await intent.perform()

        let stored = try #require(try await transactions(harness).first)
        #expect(stored.amountCents == 4_210, "money is cents, never a Double")
        #expect(stored.type == .expense)
        #expect(stored.accountID == harness.account.id)
        #expect(stored.merchant == "Whole Foods")
        #expect(stored.date == now)
    }

    @Test("Every transaction logged this way is tagged so it can be found")
    func tagsItsOrigin() async throws {
        let harness = try await makeHarness()
        let intent = intent(harness)
        intent.tags = ["weekly"]

        _ = try await intent.perform()

        let stored = try #require(try await transactions(harness).first)
        #expect(stored.tags == ["weekly", "shortcut"])
    }

    @Test("The account's cached balance moves by the amount spent")
    func updatesTheBalanceCache() async throws {
        let harness = try await makeHarness()

        _ = try await intent(harness).perform()

        let account = try #require(
            try await harness.dependencies.accounts.account(id: harness.account.id)
        )
        #expect(account.cachedBalanceCents == 100_000 - 4_210)
    }

    @Test("A negative amount is refused and nothing is written")
    func refusesANegativeAmount() async throws {
        let harness = try await makeHarness()
        let intent = intent(harness, amount: -5)

        await #expect(throws: QuickEntryError.self) { try await intent.perform() }

        let stored = try await transactions(harness)
        #expect(stored.isEmpty, "which way money moves is the type's business")
    }

    @Test("An awkward decimal still lands on the right cent")
    func convertsAwkwardDecimalsExactly() async throws {
        let harness = try await makeHarness()

        _ = try await intent(harness, amount: 8.20).perform()

        let stored = try #require(try await transactions(harness).first)
        #expect(stored.amountCents == 820, "8.20 is not representable in binary")
    }

    @Test("A free item is still a purchase")
    func acceptsAZeroAmount() async throws {
        let harness = try await makeHarness()

        _ = try await intent(harness, amount: 0).perform()

        let stored = try #require(try await transactions(harness).first)
        #expect(stored.amountCents == 0)
    }

    @Test("A category name carrying emoji is refused and nothing is written")
    func refusesAnEmojiCategory() async throws {
        let harness = try await makeHarness()
        let intent = intent(harness)
        intent.category = "Coffee ☕️"

        await #expect(throws: QuickEntryError.self) { try await intent.perform() }

        let stored = try await transactions(harness)
        #expect(stored.isEmpty)
    }

    @Test("A supplied category is created and pinned to the merchant")
    func createsAndPinsTheCategory() async throws {
        let harness = try await makeHarness()
        let intent = intent(harness)
        intent.category = "Coffee"

        _ = try await intent.perform()

        let categories = try await harness.dependencies.categories
            .selectableCategories(context: .expense)
        let coffee = try #require(categories.first { $0.label == "Coffee" })
        let stored = try #require(try await transactions(harness).first)
        #expect(stored.categoryID == coffee.id)

        let pins = try await harness.dependencies.merchantRules.rules()
        #expect(pins.first?.categoryID == coffee.id, "next time the shop files itself")
    }

    @Test("A pinned merchant overrules the category the Shortcut passes")
    func pinBeatsTheSuppliedCategory() async throws {
        let harness = try await makeHarness()
        let first = intent(harness)
        first.category = "Coffee"
        _ = try await first.perform()

        let second = intent(harness)
        second.category = "Transport"
        // Two identical runs are otherwise one repeat (§15.6), and this test is about which
        // category wins: both entries have to land for "all of them" to mean anything.
        second.allowsDuplicate = true
        _ = try await second.perform()

        let categories = try await harness.dependencies.categories
            .selectableCategories(context: .expense)
        let coffee = try #require(categories.first { $0.label == "Coffee" })
        let stored = try await transactions(harness)
        #expect(stored.count == 2)
        #expect(
            stored.allSatisfy { $0.categoryID == coffee.id },
            "the pin is the newer statement of intent"
        )
    }

    @Test("Turning remembering off writes no pin")
    func honoursTheRememberToggle() async throws {
        let harness = try await makeHarness()
        let intent = intent(harness)
        intent.category = "Coffee"
        intent.rememberCategory = false

        _ = try await intent.perform()

        let pins = try await harness.dependencies.merchantRules.rules()
        #expect(pins.isEmpty)
    }

    // MARK: - What comes back (§15)

    @Test("The entry comes back, so a Shortcut can carry on with it")
    func returnsTheTransaction() async throws {
        let harness = try await makeHarness()

        let result = try await intent(harness).perform()

        let entity = try #require(result.value)
        let stored = try #require(try await transactions(harness).first)
        #expect(entity.id == stored.id)
        #expect(entity.merchant == "Whole Foods")
        #expect(entity.accountName == "Chequing")
        #expect(entity.amount == 42.10)
    }

    @Test("A repeat hands back the entry that already exists")
    func aRepeatReturnsTheExistingEntry() async throws {
        let harness = try await makeHarness()
        let first = try await intent(harness).perform()

        let second = try await intent(harness).perform()

        #expect(
            second.value?.id == first.value?.id,
            "which is what makes a retry idempotent rather than merely quiet"
        )
    }

    // MARK: - Duplicates (§15.6)

    @Test("Running the same Shortcut twice leaves one entry, not two")
    func recognisesARepeatedRun() async throws {
        let harness = try await makeHarness()

        _ = try await intent(harness).perform()
        _ = try await intent(harness).perform()

        let stored = try await transactions(harness)
        #expect(stored.count == 1, "a Siri retry is one purchase, not two")
        #expect(stored.first?.amountCents == 4_210)
    }

    @Test("A repeat moves the balance once")
    func aRepeatMovesTheBalanceOnce() async throws {
        let harness = try await makeHarness()

        _ = try await intent(harness).perform()
        _ = try await intent(harness).perform()

        let account = try #require(
            try await harness.dependencies.accounts.account(id: harness.account.id)
        )
        #expect(account.cachedBalanceCents == 100_000 - 4_210)
    }

    @Test("Allowing duplicates records the second one")
    func honoursTheAllowDuplicateToggle() async throws {
        let harness = try await makeHarness()
        _ = try await intent(harness).perform()
        let second = intent(harness)
        second.allowsDuplicate = true

        _ = try await second.perform()

        let stored = try await transactions(harness)
        #expect(stored.count == 2, "someone really did buy the same thing twice")
    }

    @Test("A different amount at the same shop is a different purchase")
    func allowsADifferentAmount() async throws {
        let harness = try await makeHarness()

        _ = try await intent(harness).perform()
        _ = try await intent(harness, amount: 9.99).perform()

        let stored = try await transactions(harness)
        #expect(stored.count == 2)
    }

    @Test("Several files become the pages of one receipt on one transaction")
    func attachesAMultiPageReceipt() async throws {
        let harness = try await makeHarness()
        let intent = intent(harness)
        intent.receipts = [page(named: "page1.jpg"), page(named: "page2.jpg")]

        _ = try await intent.perform()

        let stored = try #require(try await transactions(harness).first)
        let fileID = try #require(stored.receiptFileID)
        #expect(stored.receiptFileName == "page1.jpg")
        let uploaded = try await harness.dependencies.receiptStore.list(
            path: ReceiptNaming.path(for: stored.date)
        )
        let pages = uploaded.filter { ReceiptNaming.isPage($0.fileID, ofBaseFileID: fileID) }
        #expect(pages.count == 2, "two photographs of one till receipt are one receipt")
    }

    @Test("A transaction with no receipt records none")
    func recordsNoReceiptWhenNoneIsGiven() async throws {
        let harness = try await makeHarness()

        _ = try await intent(harness).perform()

        let stored = try #require(try await transactions(harness).first)
        #expect(stored.receiptFileID == nil)
        #expect(stored.receiptUploadState == .none)
    }

    /// A one-pixel JPEG, as the Shortcuts app would hand one over.
    /// - Parameter name: The file name.
    /// - Returns: The file.
    private func page(named name: String) -> IntentFile {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let data = image.jpegData(compressionQuality: 0.7) ?? Data([0xFF, 0xD8, 0xFF])
        return IntentFile(data: data, filename: name, type: .jpeg)
    }
}
