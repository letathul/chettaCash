import Foundation
import Domain

/// The SF Symbol drawn inside a category avatar (§8.2).
///
/// The Domain layer carries no icon, emoji or symbol on ``Domain/Category`` — and
/// `CategoryNaming.validated(_:)` actively *refuses* emoji in a label rather than
/// stripping them — so a glyph cannot be read off the data and has to be derived
/// here, exactly as ``CategoryPalette`` derives a colour.
///
/// Keyed by the same lowercased labels as ``CategoryPalette``, so the six seeded
/// categories get a designated symbol and anything a user creates falls back to a
/// neutral one rather than to a symbol that means something else.
enum CategoryGlyph {

    /// Symbols for the seeded categories, keyed by their lowercased label.
    private static let byLabel: [String: String] = [
        "groceries": "cart.fill",
        "food & drink": "cup.and.saucer.fill",
        "transport": "car.fill",
        "shopping": "bag.fill",
        "bills": "doc.text.fill",
        "other": "square.grid.2x2.fill",
        "entertainment": "play.circle.fill",
        "subscription": "arrow.triangle.2.circlepath"
    ]

    /// The symbol shown for a user-created category with no designated one.
    private static let fallback = "tag.fill"

    /// The symbol drawn for a transaction's row.
    ///
    /// Income, transfers and adjustments describe a *direction* rather than a
    /// category, so they keep the arrows the Ledger already uses.
    ///
    /// - Parameters:
    ///   - categoryLabel: The category's display text, or `nil` when uncategorised.
    ///   - type: The transaction's type.
    ///   - isTransfer: Whether the transaction is part of a transfer.
    /// - Returns: An SF Symbol name.
    static func name(
        categoryLabel: String?,
        type: Domain.TransactionType,
        isTransfer: Bool
    ) -> String {
        if isTransfer { return "arrow.left.arrow.right" }
        switch type {
        case .income: return "arrow.down.left"
        case .adjustment: return "slider.horizontal.3"
        case .transferIn, .transferOut: return "arrow.left.arrow.right"
        case .expense:
            guard let categoryLabel else { return fallback }
            return byLabel[categoryLabel.lowercased()] ?? fallback
        }
    }
}
