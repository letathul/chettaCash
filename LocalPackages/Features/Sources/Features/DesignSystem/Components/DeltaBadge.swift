import SwiftUI
import Domain

/// Which metric a delta describes, which decides what "good" looks like (§7.1).
enum DeltaMetric {
    /// Spending. An increase is the unwelcome direction, so it reads red.
    case spend
    /// Net worth. An increase is the welcome direction, so it reads green.
    case netWorth
    /// Income. An increase is the welcome direction, so it reads green.
    case income
}

/// A month-over-month change badge (§7.1, §12).
///
/// Colour is never the only signal: every badge pairs its tint with an arrow and a
/// signed figure, so the direction survives for a viewer who cannot distinguish the
/// two colours.
struct DeltaBadge: View {
    /// The change in cents, signed.
    let deltaCents: Int
    /// The metric being described.
    let metric: DeltaMetric
    /// The currency code used to render the figure.
    let currencyCode: String

    /// Whether the value rose.
    private var isIncrease: Bool { deltaCents > 0 }

    /// Whether this change is the welcome direction for its metric.
    private var isFavourable: Bool {
        switch metric {
        case .spend: return deltaCents <= 0
        case .netWorth, .income: return deltaCents >= 0
        }
    }

    /// The badge's tint.
    private var tint: Color {
        isFavourable ? Palette.positiveGreen : Palette.negativeRed
    }

    /// The arrow glyph for the direction of change.
    private var symbol: String {
        if deltaCents == 0 { return "minus" }
        return isIncrease ? "arrow.up.right" : "arrow.down.right"
    }

    /// The signed, formatted amount.
    private var formatted: String {
        let magnitude = CurrencyFormatter.string(
            fromCents: abs(deltaCents), currencyCode: currencyCode
        )
        if deltaCents == 0 { return magnitude }
        return (isIncrease ? "+" : "−") + magnitude
    }

    /// The view body.
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
            Text(formatted)
                .font(Typography.errorCaption.weight(.semibold).monospacedDigit())
        }
        // A signed figure that wraps mid-number reads as a different number, so the
        // badge stays on one line and sizes to its content instead of the container.
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    /// A spoken description that does not rely on the arrow or the tint.
    private var accessibilityDescription: String {
        let magnitude = CurrencyFormatter.string(
            fromCents: abs(deltaCents), currencyCode: currencyCode
        )
        guard deltaCents != 0 else { return "No change" }
        return "\(isIncrease ? "Up" : "Down") \(magnitude) versus last month"
    }
}
