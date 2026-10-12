import SwiftUI
import Domain

/// One six-month trend chart with its current value and delta badge (§7.1).
///
/// Colour is never the only signal: the delta badge pairs its tint with an arrow and
/// a signed figure, and the bars carry an accessibility label per month (§12).
struct TrendChartCard: View {
    /// The chart's title.
    let title: String
    /// The monthly values.
    let series: TrendSeries
    /// Which metric this is, deciding what "good" looks like.
    let metric: DeltaMetric
    /// The display currency.
    let currencyCode: String

    /// The viewer's current text size.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The view body.
    var body: some View {
        CardContainer(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).sectionLabel()
                Text(money(series.currentCents))
                    .moneyText(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                DeltaBadge(
                    deltaCents: series.deltaCents, metric: metric, currencyCode: currencyCode
                )
                // The bars are decoration at accessibility sizes: the figure and the
                // delta above already say everything they encode (§12).
                if !dynamicTypeSize.isAccessibilitySize {
                    bars
                }
            }
        }
    }

    /// The six monthly bars.
    private var bars: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(series.points) { point in
                bar(for: point)
            }
        }
        .frame(height: 44)
    }

    /// One bar, scaled against the series peak.
    /// - Parameter point: The month to draw.
    /// - Returns: The bar view.
    private func bar(for point: TrendPoint) -> some View {
        let peak = max(series.peakCents, 1)
        let fraction = min(1, Double(abs(point.cents)) / Double(peak))
        let isLatest = point.id == series.points.last?.id
        return RoundedRectangle(cornerRadius: 3)
            .fill(isLatest ? Palette.brandPurple : Palette.brandPurple.opacity(0.28))
            .frame(maxWidth: .infinity)
            .frame(height: max(3, 44 * fraction))
            .accessibilityLabel(
                point.monthStart.formatted(.dateTime.month(.wide))
                + ": " + money(point.cents)
            )
    }

    /// Formats an amount using the display currency.
    /// - Parameter cents: The amount in cents.
    /// - Returns: The formatted string.
    private func money(_ cents: Int) -> String {
        CurrencyFormatter.string(fromCents: cents, currencyCode: currencyCode)
    }
}

/// The Spending section: six months of spend, then where this month's went (§7.1).
///
/// The cards stack rather than sit side by side, which is also what the §12 text-size
/// case needs.
struct TrendsSection: View {
    /// Six months of spend.
    let spend: TrendSeries
    /// The month's category split, largest first.
    let slices: [CategorySliceModel]
    /// The display currency.
    let currencyCode: String

    /// The view body.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Spending").sectionLabel()
            TrendChartCard(
                title: "Last 6 months", series: spend, metric: .spend, currencyCode: currencyCode
            )
            if !slices.isEmpty {
                CategorySplitCard(slices: slices, currencyCode: currencyCode)
            }
        }
    }
}

/// The month's spending split by category: one proportional bar and a legend (§7.1).
///
/// Each category keeps the colour it has everywhere else in the app, and the legend
/// carries the name and amount, so colour is never the only signal (§12).
struct CategorySplitCard: View {
    /// The slices, largest first, with "Other" last.
    let slices: [CategorySliceModel]
    /// The display currency.
    let currencyCode: String

    /// The view body.
    var body: some View {
        let total = max(slices.reduce(0) { $0 + $1.cents }, 1)
        CardContainer(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("By category").sectionLabel()
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(slices) { slice in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color(for: slice))
                                .frame(width: max(4, proxy.size.width * CGFloat(slice.cents) / CGFloat(total)))
                        }
                    }
                }
                .frame(height: 10)
                .accessibilityHidden(true)
                VStack(spacing: 8) {
                    ForEach(slices) { slice in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color(for: slice))
                                .frame(width: 10, height: 10)
                                .accessibilityHidden(true)
                            Text(slice.label)
                                .font(Typography.rowSecondary)
                                .foregroundStyle(Palette.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(CurrencyFormatter.string(
                                fromCents: slice.cents, currencyCode: currencyCode
                            ))
                            .moneyText(Typography.rowSecondary.weight(.semibold))
                            .foregroundStyle(Palette.textPrimary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    /// The colour a slice is drawn in.
    /// - Parameter slice: The slice.
    /// - Returns: The category's swatch colour, or muted grey for "Other".
    private func color(for slice: CategorySliceModel) -> Color {
        slice.isOther
            ? Palette.textSecondary
            : CategoryPalette.swatch(for: slice.label, creationIndex: slice.sortIndex).foreground
    }
}
