import Foundation
import Domain

/// The one-line insight printed at the foot of a hero page (§7.1).
struct HeroInsight: Equatable {
    /// The rendered sentence, e.g. "Food & drink is up 32% ($148.20) this month".
    let message: String
    /// Whether the change is the welcome direction. Spending less is welcome.
    let isFavourable: Bool
    /// The SF Symbol shown beside it. Colour is never the only signal (§12).
    let glyph: String
}

/// One page of the Dashboard's hero carousel (§7.1).
///
/// Every string is rendered by the view model, and the sparkline arrives already
/// normalised, so a page's `body` does no formatting, no lookup and no arithmetic.
struct HeroPageModel: Identifiable, Equatable {
    /// The page's identity, which is its series'.
    let id: UUID
    /// The account this page describes, or `nil` for the "All accounts" page.
    ///
    /// This is exactly the value ``AppSettings/focusedAccountID`` takes, so swiping
    /// the carousel is the focus picker.
    let accountID: UUID?
    /// The account's name, or "All accounts".
    let title: String
    /// The masked card digits, when the account carries them.
    let maskedNumber: String?
    /// What the headline figure is, e.g. "Available cash".
    let balanceLabel: String
    /// The headline figure, currency-formatted.
    let balanceText: String
    /// Whether that figure is negative, so the view can mark it without re-parsing.
    let isNegative: Bool
    /// The daily balances behind the sparkline.
    let series: BalanceSeries
    /// The category insight, when one clears the engine's thresholds.
    let insight: HeroInsight?
}
