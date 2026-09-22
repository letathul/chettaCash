import Foundation
import Testing
@testable import Domain

/// Which category a Shortcut's expense lands in, and what gets remembered (§4.8).
///
/// A pin beats the category the Shortcut passed, because a Shortcut is built once and
/// run for months while a pin is the newer statement of intent.
@Suite("Quick expense categories")
struct QuickExpenseCategoryTests {

    /// A fixed moment, so results never depend on the wall clock.
    private var now: Date { Date(timeIntervalSince1970: 1_789_000_000) }

    /// The pieces a plan is made against.
    private struct Harness {
        /// The account the expense lands on.
        let accountID = UUID()
        /// An existing expense category.
        let groceries = Category(label: "Groceries", context: .expense)
        /// A second existing expense category.
        let transport = Category(label: "Transport", context: .expense, sortIndex: 1)
    }

    /// Builds the fixture.
    /// - Returns: The harness.
    private func makeHarness() -> Harness { Harness() }

    /// Builds an input with the required fields filled.
    /// - Parameters:
    ///   - harness: The fixture to draw the account from.
    ///   - merchant: The merchant name.
    ///   - categoryText: The category the Shortcut supplied, if any.
    ///   - remembers: Whether to pin the resolved category.
    /// - Returns: The input.
    private func input(
        _ harness: Harness,
        merchant: String = "Whole Foods Mkt",
        categoryText: String? = nil,
        remembers: Bool = true
    ) -> QuickExpenseInput {
        var input = QuickExpenseInput(
            amountCents: 4_210, merchant: merchant, accountID: harness.accountID, date: now
        )
        input.categoryText = categoryText
        input.remembersCategory = remembers
        return input
    }

    /// Builds a context.
    /// - Parameters:
    ///   - harness: The fixture to draw categories from.
    ///   - pins: The pins the user has set.
    /// - Returns: The context.
    private func context(
        _ harness: Harness,
        pins: [MerchantCategoryRule] = []
    ) -> QuickExpenseContext {
        QuickExpenseContext(
            selectableCategories: [harness.groceries, harness.transport], pins: pins
        )
    }

    // MARK: - Category resolution

    @Test("A pinned merchant files under its pin")
    func pinWins() throws {
        let harness = makeHarness()
        let pin = try #require(
            MerchantCategoryRule.make(merchant: "Whole Foods Mkt", categoryID: harness.groceries.id)
        )

        let plan = try QuickExpensePlanner.plan(
            input(harness), in: context(harness, pins: [pin])
        )

        #expect(plan.transaction.categoryID == harness.groceries.id)
    }

    @Test("A pin overrules the category the Shortcut supplied")
    func pinBeatsSuppliedText() throws {
        let harness = makeHarness()
        let pin = try #require(
            MerchantCategoryRule.make(merchant: "Whole Foods Mkt", categoryID: harness.groceries.id)
        )

        let plan = try QuickExpensePlanner.plan(
            input(harness, categoryText: "Transport"), in: context(harness, pins: [pin])
        )

        #expect(plan.transaction.categoryID == harness.groceries.id, "the pin is the newer intent")
        #expect(plan.newCategory == nil)
    }

    @Test("A pin matches whatever spelling the receipt printed")
    func pinMatchesAcrossSpellings() throws {
        let harness = makeHarness()
        let pin = try #require(
            MerchantCategoryRule.make(merchant: "Whole Foods Mkt", categoryID: harness.groceries.id)
        )

        let plan = try QuickExpensePlanner.plan(
            input(harness, merchant: "WHOLE FOODS MKT #10234"),
            in: context(harness, pins: [pin])
        )

        #expect(plan.transaction.categoryID == harness.groceries.id)
    }

    @Test("A pin whose category has been archived is ignored")
    func ignoresPinToAMissingCategory() throws {
        let harness = makeHarness()
        let pin = try #require(
            MerchantCategoryRule.make(merchant: "Whole Foods Mkt", categoryID: UUID())
        )

        let plan = try QuickExpensePlanner.plan(
            input(harness, categoryText: "Transport"), in: context(harness, pins: [pin])
        )

        #expect(
            plan.transaction.categoryID == harness.transport.id,
            "a pin to a category that is gone must not resurrect it"
        )
    }

    @Test("A pin to a system category is never honoured")
    func ignoresSystemPin() throws {
        let harness = makeHarness()
        let pin = try #require(
            MerchantCategoryRule.make(
                merchant: "Whole Foods Mkt", categoryID: SystemCategoryID.transfer
            )
        )

        let plan = try QuickExpensePlanner.plan(
            input(harness), in: context(harness, pins: [pin])
        )

        #expect(plan.transaction.categoryID == nil)
    }

    @Test("Supplied text matches an existing category rather than creating a twin")
    func matchesExistingCategory() throws {
        let harness = makeHarness()

        let plan = try QuickExpensePlanner.plan(
            input(harness, categoryText: "groceries"), in: context(harness)
        )

        #expect(plan.transaction.categoryID == harness.groceries.id)
        #expect(plan.newCategory == nil, "case is not a new category")
    }

    @Test("Supplied text with no match creates a category")
    func createsANewCategory() throws {
        let harness = makeHarness()

        let plan = try QuickExpensePlanner.plan(
            input(harness, categoryText: "Coffee"), in: context(harness)
        )

        let created = try #require(plan.newCategory)
        #expect(created.label == "Coffee")
        #expect(created.context == .expense)
        #expect(created.sortIndex == 2, "it goes after the categories that already exist")
        #expect(plan.transaction.categoryID == created.id)
    }

    @Test("A new category must satisfy the naming rules")
    func refusesAnUnusableNewCategory() {
        let harness = makeHarness()

        #expect(throws: CategoryNaming.Problem.containsEmoji) {
            try QuickExpensePlanner.plan(
                input(harness, categoryText: "Coffee ☕️"), in: context(harness)
            )
        }
    }

    @Test("An existing category is matched whatever its length")
    func matchesLongExistingCategory() throws {
        let harness = makeHarness()
        let long = Category(label: "Household and cleaning", context: .expense, sortIndex: 2)
        let wider = QuickExpenseContext(
            selectableCategories: [harness.groceries, harness.transport, long], pins: []
        )

        let plan = try QuickExpensePlanner.plan(
            input(harness, categoryText: "Household and cleaning"), in: wider
        )

        #expect(
            plan.transaction.categoryID == long.id,
            "the creation cap must not make an existing category unreachable"
        )
        #expect(plan.newCategory == nil)
    }

    @Test("No pin and no supplied category leaves the transaction uncategorised")
    func fallsBackToUncategorised() throws {
        let harness = makeHarness()

        let plan = try QuickExpensePlanner.plan(input(harness), in: context(harness))

        #expect(plan.transaction.categoryID == nil, "an absence is not a category")
        #expect(plan.newCategory == nil)
        #expect(plan.newPin == nil, "there is nothing to remember")
    }

    // MARK: - Pinning

    @Test("Remembering pins the resolved category to the merchant")
    func writesAPin() throws {
        let harness = makeHarness()

        let plan = try QuickExpensePlanner.plan(
            input(harness, categoryText: "Groceries"), in: context(harness)
        )

        let pin = try #require(plan.newPin)
        #expect(pin.categoryID == harness.groceries.id)
        #expect(pin.merchantKey == MerchantCategoryIndex.key(for: "Whole Foods Mkt"))
        #expect(pin.displayName == "Whole Foods Mkt", "Settings shows what the user typed")
    }

    @Test("A newly created category is pinned too")
    func pinsANewCategory() throws {
        let harness = makeHarness()

        let plan = try QuickExpensePlanner.plan(
            input(harness, categoryText: "Coffee"), in: context(harness)
        )

        let created = try #require(plan.newCategory)
        let pin = try #require(plan.newPin)
        #expect(pin.categoryID == created.id)
    }

    @Test("Turning remembering off writes no pin")
    func honoursTheRememberToggle() throws {
        let harness = makeHarness()

        let plan = try QuickExpensePlanner.plan(
            input(harness, categoryText: "Groceries", remembers: false), in: context(harness)
        )

        #expect(plan.newPin == nil)
        #expect(plan.transaction.categoryID == harness.groceries.id, "the category still applies")
    }

    @Test("An already-pinned merchant is not re-pinned")
    func doesNotRewriteAnExistingPin() throws {
        let harness = makeHarness()
        let pin = try #require(
            MerchantCategoryRule.make(merchant: "Whole Foods Mkt", categoryID: harness.groceries.id)
        )

        let plan = try QuickExpensePlanner.plan(
            input(harness, categoryText: "Transport"), in: context(harness, pins: [pin])
        )

        #expect(plan.newPin == nil, "the standing pin stands")
    }

    @Test("A blank merchant is refused rather than stored empty")
    func refusesABlankMerchant() {
        let harness = makeHarness()
        let blank = input(harness, merchant: "   ", categoryText: "Groceries")

        #expect(throws: QuickEntryProblem.missingMerchant) {
            _ = try QuickExpensePlanner.plan(blank, in: context(harness))
        }
    }

    @Test("A merchant that normalises to nothing is kept, but cannot be pinned")
    func doesNotPinAnUnkeyableMerchant() throws {
        let harness = makeHarness()

        let plan = try QuickExpensePlanner.plan(
            input(harness, merchant: "###", categoryText: "Groceries"), in: context(harness)
        )

        #expect(plan.transaction.merchant == "###", "it is what the receipt said")
        #expect(plan.newPin == nil, "but there is no key to pin it under")
        #expect(plan.transaction.categoryID == harness.groceries.id)
    }
}
