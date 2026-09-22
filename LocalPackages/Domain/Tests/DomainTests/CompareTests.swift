import Foundation
import Testing
@testable import Domain

/// Phase 12 acceptance criteria: the conversion factors produce correct per-100 g and
/// per-100 mL figures, and the last comparison cannot be deleted (§7.5).
@Suite("Compare")
struct CompareTests {

    /// How close a computed figure must be to count as correct.
    private let tolerance = 0.000_01

    // MARK: - Conversion factors (§7.5)

    @Test("Mass converts to a per-100 g figure")
    func massPer100Grams() throws {
        // A 500 g pack at $4.00 is $0.80 per 100 g.
        let grams = try #require(UnitPrice.normalizedPrice(
            priceCents: 400, quantity: 500, unit: .grams
        ))
        #expect(abs(grams - 0.8) < tolerance)

        // The same pack expressed in kilograms must agree.
        let kilos = try #require(UnitPrice.normalizedPrice(
            priceCents: 400, quantity: 0.5, unit: .kilograms
        ))
        #expect(abs(kilos - 0.8) < tolerance)
    }

    @Test("Imperial mass units use the specified factors")
    func imperialMass() throws {
        // 1 lb = 453.592 g, so $4.00 per pound is 400/453.592 per gram, times 100.
        let pound = try #require(UnitPrice.normalizedPrice(
            priceCents: 400, quantity: 1, unit: .pounds
        ))
        #expect(abs(pound - (4.0 / 453.592 * 100)) < tolerance)

        // 16 oz weighs the same as 1 lb, so the figures must agree closely.
        let ounces = try #require(UnitPrice.normalizedPrice(
            priceCents: 400, quantity: 16, unit: .ounces
        ))
        #expect(abs(ounces - pound) < 0.001)
    }

    @Test("Volume converts to a per-100 mL figure")
    func volumePer100Millilitres() throws {
        // A 2 L bottle at $3.00 is $0.15 per 100 mL.
        let litres = try #require(UnitPrice.normalizedPrice(
            priceCents: 300, quantity: 2, unit: .litres
        ))
        #expect(abs(litres - 0.15) < tolerance)

        let millilitres = try #require(UnitPrice.normalizedPrice(
            priceCents: 300, quantity: 2_000, unit: .millilitres
        ))
        #expect(abs(millilitres - 0.15) < tolerance)
    }

    @Test("Imperial volume units use the specified factors")
    func imperialVolume() throws {
        let gallon = try #require(UnitPrice.normalizedPrice(
            priceCents: 500, quantity: 1, unit: .gallons
        ))
        #expect(abs(gallon - (5.0 / 3_785.41 * 100)) < tolerance)

        // 128 fl oz makes a gallon, so the figures must agree closely.
        let fluidOunces = try #require(UnitPrice.normalizedPrice(
            priceCents: 500, quantity: 128, unit: .fluidOunces
        ))
        #expect(abs(fluidOunces - gallon) < 0.001)
    }

    @Test("Countable items are quoted per item, not per hundred")
    func quantityPerItem() throws {
        // 12 items at $6.00 is $0.50 each.
        let each = try #require(UnitPrice.normalizedPrice(
            priceCents: 600, quantity: 12, unit: .item
        ))
        #expect(abs(each - 0.5) < tolerance)
    }

    @Test("Every unit belongs to exactly one category")
    func unitsAreCategorised() {
        #expect(UnitPrice.units(in: .mass) == [.grams, .kilograms, .pounds, .ounces])
        #expect(UnitPrice.units(in: .volume) == [.millilitres, .litres, .fluidOunces, .gallons])
        #expect(UnitPrice.units(in: .quantity) == [.item])
        #expect(PackageUnit.allCases.allSatisfy { UnitPrice.category(of: $0) != nil })
    }

    @Test("Figures are labelled by what they are quoted per")
    func quotedPerLabels() {
        #expect(UnitPrice.quotedPerLabel(for: .mass) == "per 100 g")
        #expect(UnitPrice.quotedPerLabel(for: .volume) == "per 100 mL")
        #expect(UnitPrice.quotedPerLabel(for: .quantity) == "per item")
    }

    // MARK: - Silent validation (§7.5)

    /// One invalid combination of inputs.
    private struct InvalidInput {
        /// The price in cents, if any.
        let price: Int?
        /// The quantity, if any.
        let quantity: Double?
        /// The unit, if any.
        let unit: PackageUnit?
    }

    @Test("Invalid input fails silently to no result")
    func invalidInputIsSilent() {
        let cases = [
            InvalidInput(price: nil, quantity: 500, unit: .grams),
            InvalidInput(price: 400, quantity: nil, unit: .grams),
            InvalidInput(price: 400, quantity: 500, unit: nil),
            InvalidInput(price: 400, quantity: 0, unit: .grams),
            InvalidInput(price: 400, quantity: -5, unit: .grams),
            InvalidInput(price: 0, quantity: 500, unit: .grams)
        ]

        for input in cases {
            let figure = UnitPrice.normalizedPrice(
                priceCents: input.price, quantity: input.quantity, unit: input.unit
            )
            #expect(figure == nil)
        }
    }

    @Test("A non-finite quantity does not produce a figure")
    func nonFiniteQuantityIsRejected() {
        #expect(UnitPrice.normalizedPrice(
            priceCents: 400, quantity: .infinity, unit: .grams
        ) == nil)
        #expect(UnitPrice.normalizedPrice(
            priceCents: 400, quantity: .nan, unit: .grams
        ) == nil)
    }

    // MARK: - Outcome (§7.5)

    /// Builds a comparison from two packages.
    /// - Parameters:
    ///   - priceA: Item A's price in cents.
    ///   - quantityA: Item A's quantity.
    ///   - unitA: Item A's unit.
    ///   - priceB: Item B's price in cents.
    ///   - quantityB: Item B's quantity.
    ///   - unitB: Item B's unit.
    /// - Returns: The comparison.
    /// One side of a comparison.
    private struct Side {
        /// The price in cents.
        let price: Int?
        /// The quantity.
        let quantity: Double?
        /// The unit.
        let unit: PackageUnit?
    }

    /// Builds a comparison from two packages.
    /// - Parameters:
    ///   - itemA: The first package.
    ///   - itemB: The second package.
    /// - Returns: The comparison.
    private func comparison(itemA: Side, itemB: Side) -> Comparison {
        Comparison(
            label: "Test",
            unitCategory: itemA.unit.flatMap(UnitPrice.category(of:)),
            itemAPriceCents: itemA.price,
            itemAQuantity: itemA.quantity,
            itemAUnit: itemA.unit?.rawValue,
            itemBPriceCents: itemB.price,
            itemBQuantity: itemB.quantity,
            itemBUnit: itemB.unit?.rawValue
        )
    }

    @Test("The cheaper item wins, across different units in the same category")
    func cheaperItemWins() {
        // 500 g at $4.00 is $0.80 per 100 g; 1 kg at $6.00 is $0.60 per 100 g.
        let result = ComparisonEvaluator.evaluate(comparison(
            itemA: Side(price: 400, quantity: 500, unit: .grams),
            itemB: Side(price: 600, quantity: 1, unit: .kilograms)
        ))

        #expect(result.winner == .itemB)
    }

    @Test("Item A wins when it is the better value")
    func itemACanWin() {
        let result = ComparisonEvaluator.evaluate(comparison(
            itemA: Side(price: 200, quantity: 1, unit: .kilograms),
            itemB: Side(price: 600, quantity: 1, unit: .kilograms)
        ))

        #expect(result.winner == .itemA)
    }

    @Test("Identical value reports a tie rather than a winner")
    func identicalValueIsATie() {
        let result = ComparisonEvaluator.evaluate(comparison(
            itemA: Side(price: 400, quantity: 500, unit: .grams),
            itemB: Side(price: 800, quantity: 1, unit: .kilograms)
        ))

        #expect(result.winner == nil)
        guard case .tie = result else {
            Issue.record("Expected a tie")
            return
        }
    }

    @Test("A difference under the threshold counts as the same")
    func negligibleDifferenceIsATie() {
        // $10.00 per 100 g against the same price for 100.001 g — a difference of
        // about 0.0001, well under the threshold.
        let result = ComparisonEvaluator.evaluate(comparison(
            itemA: Side(price: 1_000, quantity: 100, unit: .grams),
            itemB: Side(price: 1_000, quantity: 100.001, unit: .grams)
        ))

        guard case .tie = result else {
            Issue.record("Expected a tie for a difference below the threshold")
            return
        }
    }

    @Test("An incomplete side yields no result rather than a default winner")
    func incompleteYieldsNoResult() {
        let result = ComparisonEvaluator.evaluate(comparison(
            itemA: Side(price: 400, quantity: 500, unit: .grams),
            itemB: Side(price: nil, quantity: nil, unit: nil)
        ))

        #expect(result == .noResult)
    }

    // MARK: - The last comparison (§7.5)

    @Test("The last remaining comparison cannot be deleted")
    func lastComparisonCannotBeDeleted() {
        let only = Comparison(label: "Only")

        #expect(ComparisonEvaluator.canRemove(id: only.id, from: [only]) == false)
    }

    @Test("A comparison can be deleted while others remain")
    func othersCanBeDeleted() {
        let first = Comparison(label: "First")
        let second = Comparison(label: "Second")

        #expect(ComparisonEvaluator.canRemove(id: first.id, from: [first, second]))
        #expect(ComparisonEvaluator.canRemove(id: second.id, from: [first, second]))
    }

    @Test("An unknown identifier cannot be deleted")
    func unknownIdentifierCannotBeDeleted() {
        let first = Comparison(label: "First")
        let second = Comparison(label: "Second")

        #expect(ComparisonEvaluator.canRemove(id: UUID(), from: [first, second]) == false)
    }

    @Test("Deleting down to one then stopping leaves exactly one")
    func deletingStopsAtOne() {
        var saved = [Comparison(label: "A"), Comparison(label: "B"), Comparison(label: "C")]

        while let candidate = saved.first,
              ComparisonEvaluator.canRemove(id: candidate.id, from: saved) {
            saved.removeAll { $0.id == candidate.id }
        }

        #expect(saved.count == 1)
    }
}
