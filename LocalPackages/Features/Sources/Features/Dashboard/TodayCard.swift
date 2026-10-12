import SwiftUI
import Domain

/// The Dashboard's hero card: what has been spent this month (§7.1).
///
/// It answers "how am I doing" from expenses alone, so it reads correctly whether or not
/// the user ever logs income. What needs attention lives in ``NeedsYouSection`` below it.
struct TodayCard: View {
    /// This month's expense figures.
    let summary: SpendSummary
    /// Spent today, in cents.
    let spentTodayCents: Int
    /// The display currency.
    let currencyCode: String

    /// The view body.
    var body: some View {
        HeroCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Spent in \(Date.now, format: .dateTime.month(.wide))")
                    .font(Typography.rowSecondary)
                    .opacity(0.9)

                Text(money(summary.monthSpendCents)).moneyText()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                badges

                SpendPaceChart(
                    current: summary.cumulativeThisMonth,
                    previous: summary.cumulativePreviousMonth
                )
                .frame(height: 56)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double tap to see what needs you")
    }

    /// The "today" chip and the like-for-like comparison.
    private var badges: some View {
        FlowLayout(spacing: 8) {
            if spentTodayCents > 0 {
                Text("\(money(spentTodayCents)) today")
                    .font(Typography.errorCaption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.2), in: .capsule)
            }
            if summary.previousMonthToDateCents > 0 {
                comparison
            }
        }
    }

    /// "Up 8% vs this point last month". White on the hero in both directions, with an
    /// arrow carrying the direction, because red does not read on the purple (§12).
    private var comparison: some View {
        let delta = summary.deltaAgainstPreviousCents
        let percent = abs(delta) * 100 / summary.previousMonthToDateCents
        let direction = delta > 0 ? "Up" : (delta < 0 ? "Down" : "Level")
        let symbol = delta > 0 ? "arrow.up.right" : (delta < 0 ? "arrow.down.right" : "minus")
        let text = delta == 0
            ? "Level with this point last month"
            : "\(direction) \(percent)% vs this point last month"
        return HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(Typography.errorCaption.weight(.bold))
                .accessibilityHidden(true)
            Text(text)
                .font(Typography.rowSecondary)
        }
        .opacity(0.95)
    }

    /// Formats an amount using the display currency.
    /// - Parameter cents: The amount in cents.
    /// - Returns: The formatted string.
    private func money(_ cents: Int) -> String {
        CurrencyFormatter.string(fromCents: cents, currencyCode: currencyCode)
    }
}

/// This month's running spend drawn against last month's (§7.1).
///
/// Last month is dashed and fainter; this month is solid and ends in a dot at today.
/// Both share one scale so the gap between them is the real gap.
struct SpendPaceChart: View {
    /// Running spend at the end of each day this month.
    let current: [Int]
    /// Running spend at the end of each day of last month.
    let previous: [Int]

    /// The view body.
    var body: some View {
        let dayCount = max(previous.count, current.count, 2)
        let peak = max(current.max() ?? 0, previous.max() ?? 0, 1)
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    line(previous, dayCount: dayCount, peak: peak, size: size)
                        .stroke(
                            .white.opacity(0.55),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4])
                        )
                    line(current, dayCount: dayCount, peak: peak, size: size)
                        .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    if let last = current.last {
                        Circle()
                            .fill(.white)
                            .frame(width: 8, height: 8)
                            .position(point(
                                index: current.count - 1, value: last,
                                dayCount: dayCount, peak: peak, size: size
                            ))
                    }
                }
            }
            HStack {
                Text("1st")
                Spacer()
                Text("- - last month")
                Spacer()
                Text("end")
            }
            .font(Typography.errorCaption)
            .opacity(0.75)
        }
        .accessibilityHidden(true)
    }

    /// Builds one series' path.
    /// - Parameters:
    ///   - values: The running totals, day one first.
    ///   - dayCount: How many days the horizontal axis spans.
    ///   - peak: The value at the top of the chart.
    ///   - size: The drawing area.
    /// - Returns: The path.
    private func line(_ values: [Int], dayCount: Int, peak: Int, size: CGSize) -> Path {
        var path = Path()
        for (index, value) in values.enumerated() {
            let position = point(
                index: index, value: value, dayCount: dayCount, peak: peak, size: size
            )
            if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
        }
        return path
    }

    /// Places one day's value in the drawing area.
    /// - Parameters:
    ///   - index: The zero-based day.
    ///   - value: The running total that day.
    ///   - dayCount: How many days the horizontal axis spans.
    ///   - peak: The value at the top of the chart.
    ///   - size: The drawing area.
    /// - Returns: The point.
    private func point(
        index: Int, value: Int, dayCount: Int, peak: Int, size: CGSize
    ) -> CGPoint {
        let inset: CGFloat = 4
        let x = inset + (size.width - 2 * inset) * CGFloat(index) / CGFloat(dayCount - 1)
        let y = size.height - inset - (size.height - 2 * inset) * CGFloat(value) / CGFloat(peak)
        return CGPoint(x: x, y: y)
    }
}
