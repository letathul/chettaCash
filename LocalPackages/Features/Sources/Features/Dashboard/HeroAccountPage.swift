import SwiftUI
import Domain

/// One page of the Dashboard's hero carousel (§7.1).
///
/// Every string arrives rendered and the sparkline arrives normalised, so this body
/// does no formatting, no lookup and no arithmetic (§8.4).
struct HeroAccountPage: View {
    /// The page to render.
    let page: HeroPageModel
    /// What needs attention today, on the "All accounts" page only.
    ///
    /// The digest describes the whole ledger rather than one account, so repeating it
    /// on every page would misattribute it.
    let digest: TodayDigest?
    /// The display currency.
    let currencyCode: String
    /// Opens the Today sheet.
    let onOpenToday: () -> Void

    /// Whether the sparkline has enough points to be worth drawing.
    private var showsSparkline: Bool { page.series.points.count > 1 }

    /// The view body.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text(page.balanceText)
                .moneyText(.largeTitle.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if showsSparkline { sparkline }
            if let insight = page.insight { insightLine(insight) }
            if let digest, !digest.isQuietDay {
                DigestChips(digest: digest, currencyCode: currencyCode)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Palette.heroGradientStart, Palette.heroGradientEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: .rect(cornerRadius: 24)
        )
        .shadow(color: Palette.cardShadow, radius: 10, x: 0, y: 4)
    }

    /// The account name, its masked digits, and the way into the Today sheet.
    private var header: some View {
        HStack(spacing: 8) {
            Text(page.title)
                .font(Typography.rowPrimary)
                .foregroundStyle(.white)
                .lineLimit(1)
            if let maskedNumber = page.maskedNumber {
                Text("• \(maskedNumber)")
                    .font(Typography.rowSecondary)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: onOpenToday) {
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .iconTapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("What needs you today")
        }
    }

    /// The balance line over the trailing thirty days.
    private var sparkline: some View {
        Sparkline(values: page.series.normalized)
            .stroke(
                .white.opacity(0.9),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
            .frame(height: 40)
            .padding(.vertical, 2)
            .accessibilityHidden(true)
    }

    /// The one-line category insight.
    /// - Parameter insight: What to say.
    /// - Returns: The line.
    private func insightLine(_ insight: HeroInsight) -> some View {
        HStack(spacing: 6) {
            Image(systemName: insight.glyph)
                .font(Typography.errorCaption)
                .accessibilityHidden(true)
            Text(insight.message)
                .font(Typography.rowSecondary)
                .lineLimit(2)
        }
        .foregroundStyle(.white.opacity(0.95))
    }
}
