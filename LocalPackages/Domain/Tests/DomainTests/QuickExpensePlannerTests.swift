import Foundation
import Testing
@testable import Domain

/// Logging an expense from a Shortcut, without opening the app (§4.2, §4.8).
///
/// The interesting decision is the category: a pin is a standing instruction and beats
/// whatever the Shortcut passed, because a Shortcut is built once and run for months
/// while a pin is the newer statement of intent.
@Suite("Quick expense planning")
struct QuickExpensePlannerTests {

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
        remembers: Bool = true,
        cents: Int = 4_210
    ) -> QuickExpenseInput {
        var input = QuickExpenseInput(
            amountCents: cents, merchant: merchant, accountID: harness.accountID, date: now
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

    // MARK: - The transaction itself

    @Test("The transaction carries what the Shortcut supplied")
    func buildsTheTransaction() throws {
        let harness = makeHarness()
        var supplied = input(harness)
        supplied.location = "  Toronto  "
        supplied.memo = "  weekly shop "

        let plan = try QuickExpensePlanner.plan(supplied, in: context(harness))

        #expect(plan.transaction.amountCents == 4_210)
        #expect(plan.transaction.type == .expense)
        #expect(plan.transaction.accountID == harness.accountID)
        #expect(plan.transaction.date == now)
        #expect(plan.transaction.merchant == "Whole Foods Mkt")
        #expect(plan.transaction.location == "Toronto", "padding is not a location")
        #expect(plan.transaction.memo == "weekly shop")
        #expect(plan.transaction.transferGroupID == nil)
        #expect(plan.transaction.signedOverrideCents == nil)
    }

    @Test("Blank optional text becomes absence rather than an empty string")
    func blankOptionalsBecomeNil() throws {
        let harness = makeHarness()
        var supplied = input(harness)
        supplied.location = "   "
        supplied.memo = ""

        let plan = try QuickExpensePlanner.plan(supplied, in: context(harness))

        #expect(plan.transaction.location == nil)
        #expect(plan.transaction.memo == nil)
    }

    // MARK: - Limits (§15.8)

    @Test("An amount at the ceiling is recorded")
    func acceptsTheLargestAllowedAmount() throws {
        let harness = makeHarness()

        let plan = try QuickExpensePlanner.plan(
            input(harness, cents: QuickEntryLimits.maximumCents), in: context(harness)
        )

        #expect(plan.transaction.amountCents == QuickEntryLimits.maximumCents)
    }

    @Test("An amount past the ceiling is refused")
    func refusesAnAbsurdAmount() {
        let harness = makeHarness()
        let absurd = input(harness, cents: QuickEntryLimits.maximumCents + 1)

        #expect(
            throws: QuickEntryProblem.amountTooLarge,
            "a figure this size flattens every chart axis in the app until it is found"
        ) {
            _ = try QuickExpensePlanner.plan(absurd, in: context(harness))
        }
    }

    @Test("A merchant name at the limit is kept")
    func acceptsTheLongestAllowedMerchant() throws {
        let harness = makeHarness()
        let long = String(repeating: "A", count: QuickEntryLimits.maximumMerchantLength)

        let plan = try QuickExpensePlanner.plan(input(harness, merchant: long), in: context(harness))

        #expect(plan.transaction.merchant == long, "a bank descriptor is long and still true")
    }

    @Test("A merchant name past the limit is refused")
    func refusesAWholeParsedMessage() {
        let harness = makeHarness()
        let tooLong = String(repeating: "A", count: QuickEntryLimits.maximumMerchantLength + 1)

        #expect(throws: QuickEntryProblem.merchantTooLong) {
            _ = try QuickExpensePlanner.plan(input(harness, merchant: tooLong), in: context(harness))
        }
    }

    @Test("A zero-cent expense is a real purchase")
    func acceptsZero() throws {
        let harness = makeHarness()
        var supplied = input(harness)
        supplied.amountCents = 0

        let plan = try QuickExpensePlanner.plan(supplied, in: context(harness))

        #expect(plan.transaction.amountCents == 0, "something acquired free is still logged")
    }

    // MARK: - Tags

    @Test("Every transaction logged this way carries the shortcut tag")
    func alwaysTagsItsOrigin() throws {
        let harness = makeHarness()

        let plan = try QuickExpensePlanner.plan(input(harness), in: context(harness))

        #expect(plan.transaction.tags == [QuickExpensePlanner.originTag])
    }

    @Test("The shortcut tag is appended after the user's own")
    func appendsAfterUserTags() throws {
        let harness = makeHarness()
        var supplied = input(harness)
        supplied.tags = ["weekly", "shared"]

        let plan = try QuickExpensePlanner.plan(supplied, in: context(harness))

        #expect(plan.transaction.tags == ["weekly", "shared", QuickExpensePlanner.originTag])
    }

    @Test("A user who types the origin tag does not get it twice")
    func doesNotDuplicateTheOriginTag() throws {
        let harness = makeHarness()
        var supplied = input(harness)
        supplied.tags = ["Shortcut"]

        let plan = try QuickExpensePlanner.plan(supplied, in: context(harness))

        #expect(plan.transaction.tags == ["Shortcut"], "case does not split one tag into two")
    }

    @Test("Blank and repeated tags are dropped")
    func dropsBlankAndRepeatedTags() throws {
        let harness = makeHarness()
        var supplied = input(harness)
        supplied.tags = ["weekly", "  ", "WEEKLY", " shared "]

        let plan = try QuickExpensePlanner.plan(supplied, in: context(harness))

        #expect(plan.transaction.tags == ["weekly", "shared", QuickExpensePlanner.originTag])
    }
}
