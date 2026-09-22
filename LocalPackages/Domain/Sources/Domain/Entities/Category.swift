import Foundation

/// A single-select label for a transaction or product.
///
/// One category per transaction, unlimited tags (§4.8). Multiple categories were
/// rejected because a purchase carrying two would double-count in any by-category
/// total. Categories are archived, never deleted, so historical rows keep their label.
public struct Category: Identifiable, Hashable, Sendable {
    /// Stable identifier, preserved across backup export and import.
    public let id: UUID
    /// Display text, such as "Groceries".
    public var label: String
    /// Which picker this category appears in.
    public var context: CategoryContext
    /// Whether this category was seeded by the app rather than created by the user.
    public var isBuiltIn: Bool
    /// Whether this category is hidden from pickers while remaining filterable.
    public var isArchived: Bool
    /// Manual ordering position within its context.
    public var sortIndex: Int

    /// Creates a category.
    /// - Parameters:
    ///   - id: Stable identifier. Defaults to a fresh UUID.
    ///   - label: Display text.
    ///   - context: Which picker this category appears in.
    ///   - isBuiltIn: Whether the app seeded this category.
    ///   - isArchived: Whether the category is hidden from pickers.
    ///   - sortIndex: Manual ordering position.
    public init(
        id: UUID = UUID(),
        label: String = "",
        context: CategoryContext = .expense,
        isBuiltIn: Bool = false,
        isArchived: Bool = false,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.label = label
        self.context = context
        self.isBuiltIn = isBuiltIn
        self.isArchived = isArchived
        self.sortIndex = sortIndex
    }
}

/// Identifiers for the two system categories that must never appear in a picker (§4.8).
///
/// These are seeded with fixed identifiers so that every picker and filter can
/// exclude them by identity rather than by matching their display text.
public enum SystemCategoryID {
    /// The system category representing a transfer leg.
    public static let transfer = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
    /// The system category representing a balance adjustment.
    public static let balanceAdjustment = UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID()

    /// Every system category identifier, for exclusion from pickers and filters.
    public static let all: Set<UUID> = [transfer, balanceAdjustment]

    /// Reports whether a category identifier belongs to a hidden system category.
    /// - Parameter id: The category identifier to test, if any.
    /// - Returns: `true` when the identifier is a system category.
    public static func isSystem(_ id: UUID?) -> Bool {
        guard let id else { return false }
        return all.contains(id)
    }
}
