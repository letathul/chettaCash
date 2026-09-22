import Foundation

/// A pinned merchant, so a shop always files under the category the user chose (§4.8).
///
/// ``MerchantCategoryIndex`` already infers a merchant's usual category from history,
/// but inference is a vote: a shop bought from twice under the wrong label wins until
/// it is outvoted. A pin is an instruction instead — it is what the user said, it
/// applies from the first purchase, and it is the only thing the Shortcut consults
/// before falling back to whatever category the Shortcut itself supplied.
///
/// Keyed by ``MerchantCategoryIndex/key(for:)`` rather than by the raw name, so
/// `WHOLE FOODS MKT #10234` and `Whole Foods Mkt` resolve to one pin.
public struct MerchantCategoryRule: Identifiable, Hashable, Sendable {
    /// Stable identifier, preserved across backup export and import.
    public let id: UUID
    /// The normalised merchant key this pin matches on.
    public var merchantKey: String
    /// The merchant name as the user typed it, for display in Settings.
    ///
    /// Stored separately because ``merchantKey`` is lowercased and hyphenated, which
    /// reads badly in a list the user is meant to manage.
    public var displayName: String
    /// The category this merchant always files under.
    public var categoryID: UUID
    /// When the pin was last written, so the newest wins if two ever collide.
    public var updatedAt: Date

    /// Creates a pin.
    /// - Parameters:
    ///   - id: Stable identifier. Defaults to a fresh UUID.
    ///   - merchantKey: The normalised merchant key.
    ///   - displayName: The merchant name as typed.
    ///   - categoryID: The category to file this merchant under.
    ///   - updatedAt: When the pin was written.
    public init(
        id: UUID = UUID(),
        merchantKey: String = "",
        displayName: String = "",
        categoryID: UUID,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.merchantKey = merchantKey
        self.displayName = displayName
        self.categoryID = categoryID
        self.updatedAt = updatedAt
    }

    /// Creates a pin from a merchant name, normalising the key.
    /// - Parameters:
    ///   - merchant: The merchant name as typed.
    ///   - categoryID: The category to file it under.
    ///   - updatedAt: When the pin was written.
    /// - Returns: The pin, or `nil` when the name normalises to nothing.
    public static func make(
        merchant: String,
        categoryID: UUID,
        updatedAt: Date = .now
    ) -> MerchantCategoryRule? {
        let key = MerchantCategoryIndex.key(for: merchant)
        guard !key.isEmpty else { return nil }
        return MerchantCategoryRule(
            merchantKey: key,
            displayName: merchant.trimmingCharacters(in: .whitespacesAndNewlines),
            categoryID: categoryID,
            updatedAt: updatedAt
        )
    }
}
