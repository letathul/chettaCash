import Foundation

/// What a quick entry may not exceed (§15.8).
///
/// A Shortcut's parameters arrive from wherever its author pointed them — a parsed
/// notification, a clipboard, a field typed at run time — and nobody is watching when it
/// runs. The in-app form has a person reading it back; this path has a sentence spoken
/// after the fact.
public enum QuickEntryLimits {

    /// The largest single entry a Shortcut may record, in cents.
    ///
    /// A million. ``MoneyInput`` already refuses anything `Int` cannot hold, which leaves
    /// roughly ninety quadrillion as the only ceiling — so `1e14` typed by accident is a
    /// perfectly valid ten-trillion-pound expense that flattens every chart axis and total
    /// in the app until it is found. A figure above this is a slip, not a purchase.
    public static let maximumCents = 100_000_000

    /// The longest merchant name kept.
    ///
    /// Generous, because a bank descriptor can be long and unlovely and is still the truth.
    /// This is a guard against a whole parsed message arriving in the field, not a style rule.
    public static let maximumMerchantLength = 120

    /// The most receipt pages one entry may carry.
    ///
    /// A till receipt runs to a few photographs. Beyond this it is a Shortcut pointed at a
    /// camera roll, and a background intent has neither the memory nor the time.
    public static let maximumReceiptPages = 8

    /// The most receipt bytes one entry may carry, across all its pages.
    public static let maximumReceiptBytes = 32 * 1_024 * 1_024
}

/// Why a quick entry could not be recorded (§15.8).
public enum QuickEntryProblem: Error, Equatable, Sendable {
    /// The amount was larger than ``QuickEntryLimits/maximumCents``.
    case amountTooLarge
    /// No merchant was given, or only whitespace.
    ///
    /// Refused rather than stored empty. An empty merchant also normalises to an empty
    /// ``MerchantCategoryIndex`` key, so the pin the entry asked for silently does nothing —
    /// the entry would be wrong in two ways and say so in neither.
    case missingMerchant
    /// The merchant name was longer than ``QuickEntryLimits/maximumMerchantLength``.
    case merchantTooLong
    /// The receipt ran past ``QuickEntryLimits/maximumReceiptPages`` or
    /// ``QuickEntryLimits/maximumReceiptBytes``.
    case receiptTooLarge
}
