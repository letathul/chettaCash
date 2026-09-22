import Foundation

/// A saved unit-price comparison between two items (§7.5).
///
/// Item B's unit picker is constrained to Item A's ``unitCategory``, which is set
/// the moment Item A's unit is chosen.
public struct Comparison: Identifiable, Hashable, Sendable {
    /// Stable identifier, preserved across backup export and import.
    public let id: UUID
    /// Display label shown on the history chip.
    public var label: String
    /// The dimension both items are measured in, once Item A's unit is chosen.
    public var unitCategory: UnitCategory?
    /// Item A's price in cents.
    public var itemAPriceCents: Int?
    /// Item A's quantity, which must be positive to produce a result.
    public var itemAQuantity: Double?
    /// Item A's unit, as a ``Unit`` raw value.
    public var itemAUnit: String?
    /// Item B's price in cents.
    public var itemBPriceCents: Int?
    /// Item B's quantity, which must be positive to produce a result.
    public var itemBQuantity: Double?
    /// Item B's unit, as a ``Unit`` raw value.
    public var itemBUnit: String?
    /// Manual ordering position in the history strip.
    public var sortIndex: Int

    /// Creates a comparison.
    /// - Parameters:
    ///   - id: Stable identifier. Defaults to a fresh UUID.
    ///   - label: Display label for the history chip.
    ///   - unitCategory: The dimension both items are measured in.
    ///   - itemAPriceCents: Item A's price in cents.
    ///   - itemAQuantity: Item A's quantity.
    ///   - itemAUnit: Item A's unit raw value.
    ///   - itemBPriceCents: Item B's price in cents.
    ///   - itemBQuantity: Item B's quantity.
    ///   - itemBUnit: Item B's unit raw value.
    ///   - sortIndex: Manual ordering position.
    public init(
        id: UUID = UUID(),
        label: String = "",
        unitCategory: UnitCategory? = nil,
        itemAPriceCents: Int? = nil,
        itemAQuantity: Double? = nil,
        itemAUnit: String? = nil,
        itemBPriceCents: Int? = nil,
        itemBQuantity: Double? = nil,
        itemBUnit: String? = nil,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.label = label
        self.unitCategory = unitCategory
        self.itemAPriceCents = itemAPriceCents
        self.itemAQuantity = itemAQuantity
        self.itemAUnit = itemAUnit
        self.itemBPriceCents = itemBPriceCents
        self.itemBQuantity = itemBQuantity
        self.itemBUnit = itemBUnit
        self.sortIndex = sortIndex
    }
}
