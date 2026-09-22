import SwiftUI
import Domain

/// One product card in the search screen's product results (§7.3, §7.12).
///
/// Icon tinted amber for a trial and green for a warranty, then name, where it came
/// from, a status line, and an optional billing subline for products that bill on a
/// schedule.
///
/// No price: the money belongs to the purchase, and several products can share one, so
/// a figure here would be the whole purchase repeated on every row.
///
/// Takes a prepared ``ProductCardModel`` rather than the view model: every string is
/// already rendered, so the card does no lookups, no date arithmetic and no currency
/// formatting of its own.
struct ProductCard: View {
    /// The card to render.
    let card: ProductCardModel

    /// The view body.
    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name)
                        .font(Typography.rowPrimary)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Text(card.purchaseLine)
                        .font(Typography.rowSecondary)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                    Text(card.statusLine)
                        .font(Typography.rowSecondary)
                        .foregroundStyle(card.isUrgent ? Palette.attentionAmber : Palette.textSecondary)
                        .lineLimit(1)
                    if let billing = card.billingLine {
                        Text(billing)
                            .font(Typography.errorCaption)
                            .foregroundStyle(Palette.brandPurple)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if card.hasReceipt {
                    Image(systemName: "paperclip")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityLabel("Its purchase has a receipt")
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
            }
        }
    }

    /// The tinted icon: amber for a trial, green for a warranty.
    private var icon: some View {
        let tint = card.accent.tint
        return ZStack {
            Circle().fill(tint.opacity(0.15))
            Image(systemName: card.accent.glyph)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }
}

/// Resolves a product accent against the palette.
extension ProductAccent {
    /// The colour this accent resolves to.
    var tint: Color {
        switch self {
        case .trial: return Palette.attentionAmber
        case .warranty: return Palette.positiveGreen
        case .plain: return Palette.brandPurple
        }
    }
}
