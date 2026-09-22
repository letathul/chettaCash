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

/// The two side-by-side trend charts (§7.1).
///
/// They stack at accessibility text sizes rather than squeezing, which is the §12
/// case the specification singles out as most likely to break.
struct TrendsSection: View {
    /// Six months of spend.
    let spend: TrendSeries
    /// Six months of net worth.
    let netWorth: TrendSeries
    /// The display currency.
    let currencyCode: String

    /// The viewer's current text size.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The view body.
    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))

        VStack(alignment: .leading, spacing: 10) {
            Text("Trends").sectionLabel()
            layout {
                TrendChartCard(
                    title: "Spend", series: spend, metric: .spend, currencyCode: currencyCode
                )
                TrendChartCard(
                    title: "Net worth", series: netWorth, metric: .netWorth,
                    currencyCode: currencyCode
                )
            }
        }
    }
}
