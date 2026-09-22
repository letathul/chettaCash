import SwiftUI
import Domain

/// One transaction row in the Ledger (§7.4).
///
/// Category-colour avatar, merchant with an optional RECURRING badge, a
/// "Category · Account" subline, and the signed amount. A transfer with no account
/// filter active renders as a single row reading "Chequing → Visa" (§4.3).
///
/// Takes a prepared ``LedgerRowModel`` rather than the view model: every string here is
/// already rendered, so the row does no currency formatting and no account or category
/// lookup of its own, and nothing else on the screen can invalidate it.
struct LedgerRowView: View {
    /// The row to render.
    let row: LedgerRowModel
    /// Whether the row belongs to the visually lighter Upcoming section.
    var isUpcoming = false

    /// The view body.
    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.title)
                        .font(Typography.rowPrimary)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    if row.isRecurring { recurringBadge }
                }
                Text(row.subtitle)
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(row.amountText)
                .moneyText(Typography.rowPrimary)
                .foregroundStyle(row.tone.color)
        }
        .opacity(isUpcoming ? 0.6 : 1)
        // The row has no background of its own, so the Spacer gap between the subtitle
        // and the amount would otherwise ignore taps (§8.4).
        .tappableSurface()
    }

    /// The category-tinted avatar, or a transfer glyph.
    private var avatar: some View {
        let swatch = row.avatar.swatch
        return ZStack {
            Circle().fill(swatch.background)
            Image(systemName: row.glyph)
                .font(.caption.weight(.bold))
                .foregroundStyle(swatch.foreground)
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }

    /// The RECURRING badge (§7.4).
    private var recurringBadge: some View {
        Text("RECURRING")
            .font(.system(size: 9, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(Palette.brandPurple)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Palette.brandPurple.opacity(0.12), in: .capsule)
    }
}
