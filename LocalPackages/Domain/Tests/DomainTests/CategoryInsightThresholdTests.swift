import Foundation
import Testing
@testable import Domain

/// The floors that stop the hero card shouting about noise (§7.1).
@Suite("Category insight thresholds")
struct CategoryInsightThresholdTests {

    private typealias Given = InsightFixtures

    /// Runs the engine at a chosen moment.
    /// - Parameters:
    ///   - transactions: The transactions to consider.
    ///   - categories: The categories in play.
    ///   - reference: The moment to evaluate at.
    /// - Returns: The top insight, if any.
    private func top(
        _ transactions: [Transaction],
        _ categories: [Domain.Category],
        at reference: Date = InsightFixtures.reference
    ) -> CategorySpendInsight? {
        CategoryInsightEngine.topMovingCategory(
            transactions: transactions, categories: categories,
            reference: reference, calendar: SeriesFixtures.utc
        )
    }

    @Test("A six dollar coffee habit rising to eight dollars is too small to say anything about")
    func theCoffeeHabitStaysQuiet() {
        let food = Given.category("Food & drink")
        let transactions = [
            Given.spend(600, food, when: Given.lastMonth(5)),
            Given.spend(800, food, when: Given.thisMonth(5))
        ]

        #expect(top(transactions, [food]) == nil)
    }

    @Test("A category below the spend floor in both months is never chosen")
    func belowTheSpendFloor() {
        let food = Given.category("Food & drink")
        let belowFloor = CategoryInsightEngine.minimumSpendCents - 1
        let transactions = [
            Given.spend(100, food, when: Given.lastMonth(5)),
            Given.spend(belowFloor, food, when: Given.thisMonth(5))
        ]

        #expect(top(transactions, [food]) == nil)
    }

    @Test("A move below the ten dollar delta floor is never chosen")
    func belowTheDeltaFloor() {
        let bills = Given.category("Bills")
        let move = CategoryInsightEngine.minimumDeltaCents - 1
        let transactions = [
            Given.spend(50_000, bills, when: Given.lastMonth(5)),
            Given.spend(50_000 + move, bills, when: Given.thisMonth(5))
        ]

        #expect(top(transactions, [bills]) == nil)
    }

    @Test("A rise under ten percent is treated as noise and dropped")
    func belowThePercentageFloor() {
        let bills = Given.category("Bills")
        // $2.00 on $500.00 is 0.4% — well over the delta floor, well under 10%.
        let transactions = [
            Given.spend(500_000, bills, when: Given.lastMonth(5)),
            Given.spend(502_000, bills, when: Given.thisMonth(5))
        ]

        #expect(top(transactions, [bills]) == nil)
    }

    @Test("A category whose spend did not change at all is never chosen")
    func unchangedSpendIsNotAnInsight() {
        let bills = Given.category("Bills")
        let transactions = [
            Given.spend(50_000, bills, when: Given.lastMonth(5)),
            Given.spend(50_000, bills, when: Given.thisMonth(5))
        ]

        #expect(top(transactions, [bills]) == nil)
    }

    @Test("A fall reported in the first days of the month is suppressed as a partial-month artefact")
    func earlyFallsAreSuppressed() {
        let bills = Given.category("Bills")
        let transactions = [Given.spend(50_000, bills, when: Given.lastMonth(5))]

        #expect(top(transactions, [bills], at: Given.thisMonth(3)) == nil)
    }

    @Test("A rise in the first days of the month is still reported, because it cannot be an artefact")
    func earlyRisesAreStillReported() {
        let bills = Given.category("Bills")
        let transactions = [
            Given.spend(20_000, bills, when: Given.lastMonth(5)),
            Given.spend(60_000, bills, when: Given.thisMonth(2))
        ]

        let insight = top(transactions, [bills], at: Given.thisMonth(3))

        #expect(insight?.direction == .increase)
        #expect(insight?.deltaCents == 40_000)
    }

    @Test("A brand-new category clears the floors without needing to clear the percentage gate")
    func aBrandNewCategorySkipsThePercentageGate() {
        let shopping = Given.category("Shopping")
        let transactions = [Given.spend(2_600, shopping, when: Given.thisMonth(4))]

        let insight = top(transactions, [shopping])

        #expect(insight?.percentChange == nil)
        #expect(insight?.currentCents == 2_600)
    }

    @Test("Two categories that moved by the same amount are ordered by percentage, then by label")
    func tiesBreakOnPercentageThenLabel() {
        let shopping = Given.category("Shopping")
        let transport = Given.category("Transport")
        let transactions = [
            // Same $200 move, but transport rose from a smaller base.
            Given.spend(80_000, shopping, when: Given.lastMonth(5)),
            Given.spend(100_000, shopping, when: Given.thisMonth(5)),
            Given.spend(30_000, transport, when: Given.lastMonth(6)),
            Given.spend(50_000, transport, when: Given.thisMonth(6))
        ]

        let ranked = CategoryInsightEngine.rankedMovingCategories(
            transactions: transactions, categories: [shopping, transport],
            reference: Given.reference, calendar: SeriesFixtures.utc
        )

        #expect(ranked.map(\.label) == ["Transport", "Shopping"])
    }
}
