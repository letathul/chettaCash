import SwiftUI

/// One row in the Dashboard's Recent list.
///
/// Takes a prepared ``RecentRowModel``: the amount is already formatted and the account
/// and category names already resolved, so the row does no lookups of its own.
struct RecentRow: View {
    /// The row to render.
    let row: RecentRowModel

    /// The view body.
    var body: some View {
        HStack(spacing: 10) {
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
                .moneyText(Typography.rowSecondary)
                .foregroundStyle(row.tone.color)
        }
        // No background of its own, so the gap before the amount would ignore taps (§8.4).
        .tappableSurface()
    }
}
