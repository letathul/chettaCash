import Foundation
import Testing
@testable import Features
import Domain

/// Phase 12 acceptance criteria end to end: conversions produce correct per-unit
/// figures, and the last remaining comparison cannot be deleted (§7.5).
@MainActor
@Suite("Compare screen")
struct CompareViewModelTests {

    /// Builds a loaded view model.
    /// - Returns: The repository fake and the view model.
    private func makeModel() async -> (FakeComparisonRepository, CompareViewModel) {
        let repository = FakeComparisonRepository()
        let model = CompareViewModel(repository: repository, settings: AppSettings())
        await model.load()
        return (repository, model)
    }

    @Test("A first comparison is created so the screen is never empty")
    func firstComparisonIsSeeded() async {
        let (repository, model) = await makeModel()

        #expect(model.comparisons.count == 1)
        #expect(repository.comparisonsByID.count == 1)
        #expect(model.selected != nil)
    }

    @Test("Entering both items produces a winner")
    func winnerIsReported() async {
        let (_, model) = await makeModel()

        await model.selectUnitA(.grams)
        model.priceAText = "4.00"
        model.quantityAText = "500"
        await model.commitFields()
        await model.selectUnitB(.kilograms)
        model.priceBText = "6.00"
        model.quantityBText = "1"
        await model.commitFields()

        #expect(model.outcome.winner == .itemB, "$0.60 per 100 g beats $0.80")
    }

    @Test("Incomplete input yields no result rather than a default winner")
    func incompleteYieldsNoResult() async {
        let (_, model) = await makeModel()

        await model.selectUnitA(.grams)
        model.priceAText = "4.00"
        model.quantityAText = "500"
        await model.commitFields()

        #expect(model.outcome == .noResult)
    }

    @Test("Unparseable input fails silently rather than showing an error")
    func invalidInputIsSilent() async {
        let (_, model) = await makeModel()

        await model.selectUnitA(.grams)
        model.priceAText = "abc"
        model.quantityAText = "zero"
        await model.commitFields()

        #expect(model.outcome == .noResult)
        #expect(model.errorMessage == nil, "this screen has no validation errors")
        #expect(model.selected?.itemAPriceCents == nil)
    }

    @Test("Item A's unit fixes the category Item B is constrained to")
    func itemAFixesTheCategory() async {
        let (_, model) = await makeModel()

        await model.selectUnitA(.litres)

        #expect(model.constrainedCategory == .volume)
        #expect(model.selected?.unitCategory == .volume)
    }

    @Test("Item B refuses a unit outside Item A's category")
    func itemBIsConstrained() async {
        let (_, model) = await makeModel()
        await model.selectUnitA(.grams)

        await model.selectUnitB(.litres)

        #expect(model.unitB == nil, "a volume unit cannot join a mass comparison")

        await model.selectUnitB(.kilograms)
        #expect(model.unitB == .kilograms)
    }

    @Test("Changing Item A to another category clears Item B's stale unit")
    func changingCategoryClearsItemB() async {
        let (_, model) = await makeModel()
        await model.selectUnitA(.grams)
        await model.selectUnitB(.kilograms)
        #expect(model.unitB == .kilograms)

        await model.selectUnitA(.litres)

        #expect(model.unitB == nil)
        #expect(model.constrainedCategory == .volume)
    }

    // MARK: - The last comparison (§7.5)

    @Test("The last remaining comparison cannot be removed")
    func lastComparisonCannotBeRemoved() async throws {
        let (repository, model) = await makeModel()
        let only = try #require(model.selected)

        #expect(model.canRemove(only.id) == false)
        await model.remove(only.id)

        #expect(model.comparisons.count == 1)
        #expect(repository.comparisonsByID.count == 1, "the guard holds at the model, not just the UI")
    }

    @Test("Removing works while others remain, and stops at one")
    func removalStopsAtOne() async {
        let (_, model) = await makeModel()
        await model.addComparison()
        await model.addComparison()
        #expect(model.comparisons.count == 3)

        for comparison in model.comparisons {
            await model.remove(comparison.id)
        }

        #expect(model.comparisons.count == 1)
    }

    @Test("Adding a comparison selects it")
    func addingSelectsTheNewOne() async throws {
        let (_, model) = await makeModel()
        let first = try #require(model.selected)

        await model.addComparison()

        #expect(model.comparisons.count == 2)
        #expect(model.selected?.id != first.id)
    }

    @Test("Removing the selected comparison falls back to another")
    func removingSelectedFallsBack() async throws {
        let (_, model) = await makeModel()
        await model.addComparison()
        let selected = try #require(model.selected)

        await model.remove(selected.id)

        #expect(model.comparisons.count == 1)
        #expect(model.selected != nil)
        #expect(model.selected?.id != selected.id)
    }

    @Test("Switching comparisons loads that one's values into the fields")
    func switchingLoadsFields() async throws {
        let (_, model) = await makeModel()
        await model.selectUnitA(.grams)
        model.priceAText = "4.00"
        model.quantityAText = "500"
        await model.commitFields()
        let first = try #require(model.selected)

        await model.addComparison()
        #expect(model.priceAText.isEmpty, "a fresh comparison starts blank")

        model.select(first.id)
        #expect(model.priceAText == "4.00")
        #expect(model.quantityAText == "500")
    }

    @Test("The history chip status describes each comparison")
    func statusLabels() async throws {
        let (_, model) = await makeModel()
        let incomplete = try #require(model.selected)
        #expect(model.statusLabel(for: incomplete) == "Incomplete")

        await model.selectUnitA(.grams)
        model.priceAText = "2.00"
        model.quantityAText = "100"
        await model.commitFields()
        await model.selectUnitB(.grams)
        model.priceBText = "4.00"
        model.quantityBText = "100"
        await model.commitFields()

        let compared = try #require(model.selected)
        #expect(model.statusLabel(for: compared) == "A is cheaper")
    }
}
