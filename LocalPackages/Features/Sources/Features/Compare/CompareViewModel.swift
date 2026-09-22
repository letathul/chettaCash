import Foundation
import Observation
import Domain

/// Drives the Compare screen (§7.5).
///
/// Note what this deliberately does **not** do: there is no bridge from a comparison
/// to a transaction, and a saved comparison cannot be renamed. Both were explicitly
/// declined (§13.1).
@MainActor
@Observable
public final class CompareViewModel {
    /// Reads and writes saved comparisons.
    ///
    /// Internal rather than private so the editing extension, which lives in another
    /// file to stay within the line limit, can reach it.
    let repositoryReference: any ComparisonRepository

    /// User preferences, for the display currency.
    public let settings: AppSettings

    /// Every saved comparison, in sort order.
    public internal(set) var comparisons: [Domain.Comparison] = []
    /// Which comparison is being edited.
    public internal(set) var selectedID: UUID?
    /// Whether the first load is still running.
    public private(set) var isLoading = true
    /// A load or save failure to surface above the content (§7.0).
    public internal(set) var errorMessage: String?

    /// Item A's typed price.
    public var priceAText = ""
    /// Item A's typed quantity.
    public var quantityAText = ""
    /// Item B's typed price.
    public var priceBText = ""
    /// Item B's typed quantity.
    public var quantityBText = ""

    /// Creates the view model.
    /// - Parameters:
    ///   - repository: Reads and writes saved comparisons.
    ///   - settings: The shared preferences object.
    public init(repository: any ComparisonRepository, settings: AppSettings) {
        self.repositoryReference = repository
        self.settings = settings
    }

    // MARK: - Derived state

    /// The comparison currently being edited.
    public var selected: Domain.Comparison? {
        guard let selectedID else { return comparisons.first }
        return comparisons.first { $0.id == selectedID } ?? comparisons.first
    }

    /// The live outcome of the selected comparison.
    public var outcome: ComparisonOutcome {
        guard let selected else { return .noResult }
        return ComparisonEvaluator.evaluate(selected)
    }

    /// Item A's chosen unit, if any.
    public var unitA: PackageUnit? {
        selected?.itemAUnit.flatMap(PackageUnit.init(rawValue:))
    }

    /// Item B's chosen unit, if any.
    public var unitB: PackageUnit? {
        selected?.itemBUnit.flatMap(PackageUnit.init(rawValue:))
    }

    /// The category Item B's picker is constrained to, once Item A has a unit (§7.5).
    public var constrainedCategory: UnitCategory? {
        unitA.flatMap(UnitPrice.category(of:))
    }

    /// Whether a comparison may be removed — never the last one (§7.5).
    /// - Parameter id: The comparison being removed.
    /// - Returns: `true` when removal is allowed.
    public func canRemove(_ id: UUID) -> Bool {
        ComparisonEvaluator.canRemove(id: id, from: comparisons)
    }

    /// The short status shown under a history chip.
    /// - Parameter comparison: The comparison to describe.
    /// - Returns: The status text.
    public func statusLabel(for comparison: Domain.Comparison) -> String {
        switch ComparisonEvaluator.evaluate(comparison) {
        case .noResult: return "Incomplete"
        case .tie: return "Same price"
        case .cheaper(let side, _, _): return side == .itemA ? "A is cheaper" : "B is cheaper"
        }
    }

    // MARK: - Loading

    /// Loads saved comparisons, creating a first one if none exist.
    public func load() async {
        do {
            comparisons = try await repositoryReference.comparisons()
            if comparisons.isEmpty {
                try await repositoryReference.save(Domain.Comparison(label: "Comparison 1"))
                comparisons = try await repositoryReference.comparisons()
            }
            if selectedID == nil || !comparisons.contains(where: { $0.id == selectedID }) {
                selectedID = comparisons.first?.id
            }
            syncFields()
            errorMessage = nil
        } catch {
            errorMessage = "Could not load your comparisons."
        }
        isLoading = false
    }

    /// Selects a comparison and loads its values into the fields.
    /// - Parameter id: The comparison to select.
    public func select(_ id: UUID) {
        selectedID = id
        syncFields()
    }

    /// Copies the selected comparison's stored values into the editable fields.
    private func syncFields() {
        guard let selected else { return }
        priceAText = selected.itemAPriceCents.map(MoneyInput.magnitudeText(fromCents:)) ?? ""
        quantityAText = selected.itemAQuantity.map(Self.quantityText(from:)) ?? ""
        priceBText = selected.itemBPriceCents.map(MoneyInput.magnitudeText(fromCents:)) ?? ""
        quantityBText = selected.itemBQuantity.map(Self.quantityText(from:)) ?? ""
    }

    /// Renders a quantity without a trailing ".0".
    /// - Parameter value: The quantity.
    /// - Returns: The display text.
    private static func quantityText(from value: Double) -> String {
        value == value.rounded() && abs(value) < 1e9
            ? String(Int(value))
            : String(value)
    }
}
