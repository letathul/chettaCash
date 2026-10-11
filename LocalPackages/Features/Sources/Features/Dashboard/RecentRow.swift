import SwiftUI

/// One row in the Dashboard's Today list (§7.1).
///
/// Takes a prepared ``RecentRowModel``: the amount is already formatted, the date
/// already phrased and the avatar already chosen, so the row does no lookups,
/// formatting or comparisons of its own (§8.4).
struct RecentRow: View {
    /// The row to render.
    let row: RecentRowModel

    /// The view body.
    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(row.subtitle)
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(row.amountText)
                .moneyText(Typography.rowPrimary)
                .foregroundStyle(row.tone.color)
                .lineLimit(1)
        }
        // No background of its own, so the gap before the amount would ignore taps (§8.4).
        .tappableSurface()
    }

    /// The category-tinted circular avatar.
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
}
