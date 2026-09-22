import Foundation
import Domain

/// The Compare view model's editing actions (§7.5).
///
/// Split from ``CompareViewModel`` to keep each file within the 300-line limit.
extension CompareViewModel {

    /// Applies the typed fields to the selected comparison and saves it.
    ///
    /// Input that does not parse is simply stored as `nil`, which reads back as
    /// "no result yet". This screen has no red-outline validation (§7.5).
    public func commitFields() async {
        guard var working = selected else { return }
        working.itemAPriceCents = MoneyInput.magnitudeCents(from: priceAText)
        working.itemAQuantity = Self.quantity(from: quantityAText)
        working.itemBPriceCents = MoneyInput.magnitudeCents(from: priceBText)
        working.itemBQuantity = Self.quantity(from: quantityBText)
        // Selecting a comparison copies its stored values into the fields, which trips
        // the debounce that watches them. Without this the screen would write every
        // comparison straight back to disk just for being looked at.
        guard working != selected else { return }
        await persist(working)
    }

    /// Sets Item A's unit, which fixes the comparison's category.
    ///
    /// Changing to a different category clears Item B's unit, because Item B's picker
    /// is constrained to Item A's category and its old unit would no longer belong.
    ///
    /// - Parameter unit: The unit chosen.
    public func selectUnitA(_ unit: PackageUnit) async {
        guard var working = selected else { return }
        let category = UnitPrice.category(of: unit)
        working.itemAUnit = unit.rawValue
        working.unitCategory = category
        if let existingB = working.itemBUnit.flatMap(PackageUnit.init(rawValue:)),
           UnitPrice.category(of: existingB) != category {
            working.itemBUnit = nil
        }
        await persist(working)
    }

    /// Sets Item B's unit.
    ///
    /// Refuses a unit outside Item A's category, so the constraint holds even if a
    /// caller offers the wrong list.
    ///
    /// - Parameter unit: The unit chosen.
    public func selectUnitB(_ unit: PackageUnit) async {
        guard var working = selected else { return }
        guard let category = working.unitCategory,
              UnitPrice.category(of: unit) == category else { return }
        working.itemBUnit = unit.rawValue
        await persist(working)
    }

    /// Adds a fresh comparison and selects it.
    public func addComparison() async {
        let fresh = Domain.Comparison(
            label: "Comparison \(comparisons.count + 1)",
            sortIndex: comparisons.count
        )
        do {
            try await repositoryReference.save(fresh)
            await load()
            select(fresh.id)
        } catch {
            errorMessage = "Could not add that comparison."
        }
    }

    /// Removes a comparison, unless it is the last one remaining (§7.5).
    /// - Parameter id: The comparison to remove.
    public func remove(_ id: UUID) async {
        guard canRemove(id) else { return }
        do {
            try await repositoryReference.delete(id: id)
            if selectedID == id { selectedID = nil }
            await load()
        } catch {
            errorMessage = "Could not remove that comparison."
        }
    }

    /// Saves a comparison and updates it in the in-memory list.
    ///
    /// Replaces the one row in place rather than re-reading the whole table. The
    /// repository is the source of truth for what is *stored*, but it has just been told
    /// exactly what changed, so re-fetching only bought a round trip — one that ran on
    /// every keystroke before the fields were debounced.
    ///
    /// - Parameter comparison: The comparison to persist.
    private func persist(_ comparison: Domain.Comparison) async {
        do {
            try await repositoryReference.save(comparison)
            if let index = comparisons.firstIndex(where: { $0.id == comparison.id }) {
                comparisons[index] = comparison
            } else {
                comparisons = try await repositoryReference.comparisons()
            }
            errorMessage = nil
        } catch {
            errorMessage = "Could not save that comparison."
        }
    }

    /// Parses a typed quantity.
    /// - Parameter text: The raw text.
    /// - Returns: The quantity, or `nil` when it does not parse or is not positive.
    static func quantity(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")),
              value > 0, value.isFinite else { return nil }
        return value
    }
}
