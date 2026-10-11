import SwiftUI
import Domain

/// The Today digest's status chips, as shown on the hero card (§7.2).
///
/// Each chip appears only when it has something to report, and nothing is ever shown
/// empty. Extracted from the retired Today card so the hero carousel keeps the one
/// route to what needs attention today — above all the past-due warning.
struct DigestChips: View {
    /// What needs attention today.
    let digest: TodayDigest
    /// The display currency.
    let currencyCode: String

    /// The view body.
    var body: some View {
        FlowLayout(spacing: 8) {
            if !digest.missedPayments.isEmpty {
                missedChip
            }
            if digest.spentTodayCents > 0 {
                chip("\(money(digest.spentTodayCents)) spent today")
            }
            if !digest.dueSoon.isEmpty {
                chip("\(digest.dueSoon.count) due soon")
            }
            if !digest.upcomingCharges.isEmpty {
                chip("\(digest.upcomingCharges.count) charging soon")
            }
            if !digest.endingSoon.isEmpty {
                chip("\(digest.endingSoon.count) ending soon")
            }
        }
    }

    /// The missed-payment chip (§4.6).
    ///
    /// Unlike the others it inverts — red on white rather than white on translucent —
    /// because a chip that reads like every other chip is not a warning. The icon
    /// carries the same meaning, so colour is never the only signal (§12).
    private var missedChip: some View {
        let total = digest.missedPayments.reduce(0) { $0 + $1.outstandingCents }
        return HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Typography.errorCaption)
            Text("\(money(total)) past due")
                .font(Typography.errorCaption.weight(.bold))
        }
        .foregroundStyle(Palette.negativeRedOnHero)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.white, in: .capsule)
        .accessibilityLabel("\(money(total)) past due on a card statement")
    }

    /// One status chip.
    /// - Parameter text: What the chip reports.
    /// - Returns: The chip view.
    private func chip(_ text: String) -> some View {
        Text(text)
            .font(Typography.errorCaption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.2), in: .capsule)
    }

    /// Formats an amount using the display currency.
    /// - Parameter cents: The amount in cents.
    /// - Returns: The formatted string.
    private func money(_ cents: Int) -> String {
        CurrencyFormatter.string(fromCents: cents, currencyCode: currencyCode)
    }
}
