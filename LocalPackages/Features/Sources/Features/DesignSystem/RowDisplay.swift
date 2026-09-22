import SwiftUI

/// Presentation choices a row makes, expressed without reference to `Color` (§8.2).
///
/// Row content is built ahead of time by the view models so that a list body does no
/// formatting or lookup work of its own. Those models must stay plain value types, so
/// they name the *role* a colour plays and leave resolving it to the view — which is
/// also what keeps the palette swappable without touching a view model.

/// Which palette entry an amount is drawn in.
enum AmountTone: Hashable {
    /// Money in. Reads green.
    case positive
    /// Money out. Reads as ordinary primary text, not red — an expense is not an error.
    case primary
    /// Neither in nor out, such as a collapsed transfer. Reads muted.
    case secondary
}

/// Which tint a row's avatar takes.
enum RowAvatar: Hashable {
    /// No category to colour by — a transfer, or an uncategorised row.
    case neutral
    /// An income row, which has its own swatch rather than a category's.
    case income
    /// A category, carried as the two values ``CategoryPalette`` needs to pick a swatch.
    case category(label: String, sortIndex: Int)
}

/// Resolves an amount tone against the palette.
extension AmountTone {
    /// The colour this tone resolves to.
    var color: Color {
        switch self {
        case .positive: return Palette.positiveGreen
        case .primary: return Palette.textPrimary
        case .secondary: return Palette.textSecondary
        }
    }
}

/// Resolves an avatar against the category palette.
extension RowAvatar {
    /// The swatch this avatar resolves to.
    var swatch: CategorySwatch {
        switch self {
        case .neutral:
            return CategorySwatch(
                background: Palette.segmentTrack, foreground: Palette.textSecondary
            )
        case .income:
            return CategoryPalette.income
        case .category(let label, let sortIndex):
            return CategoryPalette.swatch(for: label, creationIndex: sortIndex)
        }
    }
}
