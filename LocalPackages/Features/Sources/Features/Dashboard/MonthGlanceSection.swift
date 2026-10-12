import SwiftUI
import Domain

/// The month's expense metrics as a grid of tiles (§7.1).
///
/// Nothing here depends on income. The Receipts tile is the documenting side of the app
/// on the front page: how much of what was spent has proof attached.
struct MonthGlanceSection: View {
    /// This month's expense figures.
    let summary: SpendSummary
    /// What leaves in the next week, in cents.
    let dueWithinWeekCents: Int
    /// The display currency.
    let currencyCode: String

    /// The viewer's current text size.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The view body.
    var body: some View {
        // One column at accessibility sizes, where two would truncate every figure (§12).
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 10, alignment: .top),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
        )
        VStack(alignment: .leading, spacing: 8) {
            Text("\(Date.now, format: .dateTime.month(.wide)) at a glance").sectionLabel()
            LazyVGrid(columns: columns, spacing: 10) {
                MetricTile(
                    title: "Transactions",
                    value: "\(summary.transactionCount)",
                    detail: "this month"
                )
                MetricTile(
                    title: "Largest purchase",
                    value: money(summary.largestPurchaseCents),
                    detail: largestDetail
                )
                MetricTile(
                    title: "Subscriptions",
                    value: money(summary.subscriptionMonthlyCents) + "/mo",
                    detail: "\(summary.subscriptionCount) active"
                )
                MetricTile(
                    title: "Due in 7 days",
                    value: money(dueWithinWeekCents),
                    detail: "Statements and charges"
                )
                receiptsTile
                MetricTile(
                    title: "Products logged",
                    value: "\(summary.productCount)",
                    detail: summary.purchaseWithProductsCount == 1
                        ? "from 1 purchase"
                        : "across \(summary.purchaseWithProductsCount) purchases"
                )
            }
        }
    }

    /// The merchant and date behind the largest purchase.
    private var largestDetail: String {
        guard let date = summary.largestPurchaseDate else { return "None yet" }
        let day = date.formatted(.dateTime.day().month(.abbreviated))
        return summary.largestPurchaseMerchant.isEmpty
            ? day
            : "\(summary.largestPurchaseMerchant) · \(day)"
    }

    /// The receipts tile, with a progress bar and the missing count in amber.
    private var receiptsTile: some View {
        let total = summary.receiptsAttached + summary.receiptsMissing
        let fraction = total == 0 ? 0 : Double(summary.receiptsAttached) / Double(total)
        let missing = summary.receiptsMissing
        return MetricTile(
            title: "Receipts",
            value: total == 0 ? "None yet" : "\(summary.receiptsAttached) of \(total)",
            detail: missing == 0 ? "All attached" : "\(missing) missing",
            detailColor: missing == 0 ? Palette.textSecondary : Palette.attentionAmber,
            progress: total == 0 ? nil : fraction
        )
    }

    /// Formats an amount using the display currency.
    /// - Parameter cents: The amount in cents.
    /// - Returns: The formatted string.
    private func money(_ cents: Int) -> String {
        CurrencyFormatter.string(fromCents: cents, currencyCode: currencyCode)
    }
}

/// One tile in the month grid.
struct MetricTile: View {
    /// What the figure measures.
    let title: String
    /// The figure.
    let value: String
    /// The supporting line.
    let detail: String
    /// The supporting line's colour.
    var detailColor: Color = Palette.textSecondary
    /// A 0...1 progress bar under the detail, or `nil` for none.
    var progress: Double?

    /// The view body.
    var body: some View {
        CardContainer(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.rowSecondary.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                Text(value)
                    .moneyText(Typography.headlineNumber)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(detail)
                    .font(Typography.rowSecondary)
                    .foregroundStyle(detailColor)
                    .lineLimit(2)
                if let progress {
                    ProgressView(value: progress)
                        .tint(Palette.brandPurple)
                        .padding(.top, 4)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
