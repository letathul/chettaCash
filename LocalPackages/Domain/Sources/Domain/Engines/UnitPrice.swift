import Foundation

/// A unit a package can be measured in (§7.5).
///
/// Named `PackageUnit` rather than the specification's `Unit`: Foundation already
/// declares `Unit` (the `Measurement` base class), and since every file imports
/// Foundation the bare name is ambiguous everywhere it appears.
///
/// The **raw values are the specification's, unchanged** — they are what gets
/// persisted in `Comparison.itemAUnit`. Only the case names are spelled out, because
/// one- and two-letter identifiers are rejected by the project's lint rules.
public enum PackageUnit: String, CaseIterable, Identifiable, Sendable {
    /// Grams.
    case grams = "g"
    /// Kilograms.
    case kilograms = "kg"
    /// Pounds.
    case pounds = "lb"
    /// Ounces.
    case ounces = "oz"
    /// Millilitres.
    case millilitres = "mL"
    /// Litres.
    case litres = "L"
    /// Fluid ounces.
    case fluidOunces = "fl oz"
    /// Gallons.
    case gallons = "gal"
    /// A countable item.
    case item

    /// The case's identity, for `ForEach`.
    public var id: String { rawValue }

    /// The label shown on a picker.
    public var label: String { rawValue }
}

/// What a unit measures, and how it converts to its category's base unit.
public struct UnitMeta: Equatable, Sendable {
    /// The dimension this unit measures.
    public let category: UnitCategory
    /// How many base units one of this unit is worth.
    public let toBase: Double

    /// Creates the metadata.
    /// - Parameters:
    ///   - category: The dimension measured.
    ///   - toBase: How many base units one of this unit is worth.
    public init(category: UnitCategory, toBase: Double) {
        self.category = category
        self.toBase = toBase
    }
}

/// Converts package prices to a comparable per-unit figure (§7.5).
///
/// Mass compares per 100 g, volume per 100 mL, and countable items per item. The
/// conversion factors are the specification's, verbatim.
public enum UnitPrice {

    /// How each unit converts to its category's base unit.
    public static let unitMeta: [PackageUnit: UnitMeta] = [
        .grams: UnitMeta(category: .mass, toBase: 1),
        .kilograms: UnitMeta(category: .mass, toBase: 1000),
        .pounds: UnitMeta(category: .mass, toBase: 453.592),
        .ounces: UnitMeta(category: .mass, toBase: 28.3495),
        .millilitres: UnitMeta(category: .volume, toBase: 1),
        .litres: UnitMeta(category: .volume, toBase: 1000),
        .fluidOunces: UnitMeta(category: .volume, toBase: 29.5735),
        .gallons: UnitMeta(category: .volume, toBase: 3785.41),
        .item: UnitMeta(category: .quantity, toBase: 1)
    ]

    /// How many base units each category's figure is quoted per.
    public static let categoryDivisor: [UnitCategory: Double] = [
        .mass: 100, .volume: 100, .quantity: 1
    ]

    /// The units belonging to one category, in declaration order.
    /// - Parameter category: The dimension to list.
    /// - Returns: That category's units.
    public static func units(in category: UnitCategory) -> [PackageUnit] {
        PackageUnit.allCases.filter { unitMeta[$0]?.category == category }
    }

    /// The category a unit measures.
    /// - Parameter unit: The unit to classify.
    /// - Returns: Its category, or `nil` if unknown.
    public static func category(of unit: PackageUnit) -> UnitCategory? {
        unitMeta[unit]?.category
    }

    /// The comparable per-unit price of a package.
    ///
    /// - Parameters:
    ///   - priceCents: The package price in cents.
    ///   - quantity: How much the package holds, which must be positive.
    ///   - unit: What the quantity is measured in.
    /// - Returns: The price per 100 g, per 100 mL or per item, or `nil` when any
    ///   input is missing or invalid. Invalid input fails silently to "no result
    ///   yet" — this screen has no red-outline validation (§7.5).
    public static func normalizedPrice(
        priceCents: Int?,
        quantity: Double?,
        unit: PackageUnit?
    ) -> Double? {
        guard let priceCents, priceCents > 0,
              let quantity, quantity > 0, quantity.isFinite,
              let unit,
              let meta = unitMeta[unit],
              let divisor = categoryDivisor[meta.category] else { return nil }
        let price = Double(priceCents) / 100
        return (price / (quantity * meta.toBase)) * divisor
    }

    /// The label describing what a category's figures are quoted per.
    /// - Parameter category: The dimension being quoted.
    /// - Returns: A suffix such as "per 100 g".
    public static func quotedPerLabel(for category: UnitCategory) -> String {
        switch category {
        case .mass: return "per 100 g"
        case .volume: return "per 100 mL"
        case .quantity: return "per item"
        }
    }
}
