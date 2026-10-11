import Foundation
import Testing
@testable import Domain

/// The hero card's one-line category insight (§7.1).
@Suite("Category spend insight")
struct CategoryInsightEngineTests {

    private typealias Given = InsightFixtures

    /// Runs the engine against the suite's fixed reference moment.
    /// - Parameters:
    ///   - transactions: The transactions to consider.
    ///   - categories: The categories in play.
    /// - Returns: The top insight, if any.
    private func top(
        _ transactions: [Transaction], _ categories: [Domain.Category]
    ) -> CategorySpendInsight? {
        CategoryInsightEngine.topMovingCategory(
            transactions: transactions, categories: categories,
            reference: Given.reference, calendar: SeriesFixtures.utc
        )
    }

    @Test("The insight names the category whose spend moved the most in cents")
    func biggestDollarMoveWins() {
        let food = Given.category("Food & drink")
        let transport = Given.category("Transport")
        let transactions = [
            Given.spend(10_000, food, when: Given.lastMonth(5)),
            Given.spend(25_000, food, when: Given.thisMonth(5)),
            Given.spend(8_000, transport, when: Given.lastMonth(6)),
            Given.spend(12_000, transport, when: Given.thisMonth(6))
        ]

        let insight = top(transactions, [food, transport])

        #expect(insight?.label == "Food & drink")
        #expect(insight?.direction == .increase)
        #expect(insight?.deltaCents == 15_000)
        #expect(insight?.percentChange == 150)
    }

    @Test("A category with a larger percentage but a smaller dollar move loses to the bigger dollar move")
    func centsOutrankPercentage() {
        let bills = Given.category("Bills")
        let shopping = Given.category("Shopping")
        let transactions = [
            // Quadruples, but only by $75.
            Given.spend(2_500, shopping, when: Given.lastMonth(5)),
            Given.spend(10_000, shopping, when: Given.thisMonth(5)),
            // Rises by half, but by $200.
            Given.spend(40_000, bills, when: Given.lastMonth(6)),
            Given.spend(60_000, bills, when: Given.thisMonth(6))
        ]

        let insight = top(transactions, [bills, shopping])

        #expect(insight?.label == "Bills")
        #expect(insight?.deltaCents == 20_000)
    }

    @Test("A category with no spend last month reports the magnitude and no percentage")
    func noPriorMonthReportsNoPercentage() {
        let shopping = Given.category("Shopping")
        let transactions = [Given.spend(6_200, shopping, when: Given.thisMonth(4))]

        let insight = top(transactions, [shopping])

        #expect(insight?.percentChange == nil)
        #expect(insight?.priorCents == 0)
        #expect(insight?.deltaCents == 6_200)
        #expect(insight?.direction == .increase)
    }

    @Test("A category that stopped spending entirely reports a fall of one hundred percent")
    func stoppedSpendingReportsAFullFall() {
        let shopping = Given.category("Shopping")
        let transactions = [Given.spend(12_000, shopping, when: Given.lastMonth(4))]

        let insight = top(transactions, [shopping])

        #expect(insight?.direction == .decrease)
        #expect(insight?.percentChange == 100)
        #expect(insight?.currentCents == 0)
    }

    @Test("System categories never produce an insight")
    func systemCategoriesAreExcluded() {
        let transfer = Domain.Category(
            id: SystemCategoryID.transfer, label: "Transfer", context: .expense
        )
        let transactions = [
            Transaction(
                amountCents: 50_000, type: .expense,
                categoryID: SystemCategoryID.transfer, date: Given.thisMonth(4)
            )
        ]

        #expect(top(transactions, [transfer]) == nil)
    }

    @Test("Transfer legs never reach a category total")
    func transferLegsAreExcluded() {
        let food = Given.category("Food & drink")
        let group = UUID()
        let transactions = [
            Transaction(
                amountCents: 40_000, type: .transferOut, categoryID: food.id,
                date: Given.thisMonth(4), transferGroupID: group
            ),
            Transaction(
                amountCents: 40_000, type: .expense, categoryID: food.id,
                date: Given.thisMonth(5), transferGroupID: group
            )
        ]

        #expect(top(transactions, [food]) == nil)
    }

    @Test("Adjustments never reach a category total")
    func adjustmentsAreExcluded() {
        let food = Given.category("Food & drink")
        let transactions = [
            Transaction(
                amountCents: 0, type: .adjustment, signedOverrideCents: -40_000,
                categoryID: food.id, date: Given.thisMonth(4)
            )
        ]

        #expect(top(transactions, [food]) == nil)
    }

    @Test("An unposted expense dated later this month does not inflate this month's figure")
    func unpostedSpendIsInert() {
        let food = Given.category("Food & drink")
        let transactions = [
            Given.spend(10_000, food, when: Given.lastMonth(5)),
            Given.spend(90_000, food, when: Given.thisMonth(29))
        ]

        let insight = top(transactions, [food])

        #expect(insight?.direction == .decrease)
        #expect(insight?.currentCents == 0)
    }

    @Test("Income never reaches a spend insight")
    func incomeIsExcluded() {
        let salary = Given.category("Bills")
        let transactions = [
            Transaction(
                amountCents: 400_000, type: .income,
                categoryID: salary.id, date: Given.thisMonth(4)
            )
        ]

        #expect(top(transactions, [salary]) == nil)
    }

    @Test("Uncategorised spending is left to the Today card rather than becoming an insight")
    func uncategorisedIsExcluded() {
        let food = Given.category("Food & drink")
        let transactions = [
            Transaction(amountCents: 90_000, type: .expense, date: Given.thisMonth(4))
        ]

        #expect(top(transactions, [food]) == nil)
    }

    @Test("An expense whose category no longer resolves to a label is dropped")
    func orphanedCategoryIsDropped() {
        let food = Given.category("Food & drink")
        let transactions = [
            Transaction(
                amountCents: 90_000, type: .expense, categoryID: UUID(), date: Given.thisMonth(4)
            )
        ]

        #expect(top(transactions, [food]) == nil)
    }

    @Test("An archived category still produces an insight, because the spend was real")
    func archivedCategoriesStillCount() {
        let retired = Given.category("Entertainment", isArchived: true)
        let transactions = [
            Given.spend(10_000, retired, when: Given.lastMonth(5)),
            Given.spend(30_000, retired, when: Given.thisMonth(5))
        ]

        #expect(top(transactions, [retired])?.label == "Entertainment")
    }

    @Test("With no transactions at all there is no insight")
    func nothingToReport() {
        #expect(top([], [Given.category("Food & drink")]) == nil)
    }

    @Test("The ranking returns every qualifying category, not just the winner")
    func rankingReturnsEveryQualifier() {
        let food = Given.category("Food & drink")
        let transport = Given.category("Transport")
        let transactions = [
            Given.spend(10_000, food, when: Given.lastMonth(5)),
            Given.spend(25_000, food, when: Given.thisMonth(5)),
            Given.spend(8_000, transport, when: Given.lastMonth(6)),
            Given.spend(12_000, transport, when: Given.thisMonth(6))
        ]

        let ranked = CategoryInsightEngine.rankedMovingCategories(
            transactions: transactions, categories: [food, transport],
            reference: Given.reference, calendar: SeriesFixtures.utc
        )
        let descending = ranked.map { abs($0.deltaCents) }
            == ranked.map { abs($0.deltaCents) }.sorted(by: >)

        #expect(ranked.count == 2)
        #expect(descending)
    }
}
