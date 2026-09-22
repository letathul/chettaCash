import Foundation

/// Distinguishes a spending/saving account from a credit card.
///
/// A card account's balance is negative when money is owed (§4.1).
public enum AccountKind: String, Codable, Sendable, CaseIterable {
    /// Cash, chequing or savings. Counts toward Available Cash.
    case account
    /// A credit card. Counts toward Net Worth only.
    case card
}

/// The five kinds of ledger entry, which together determine a transaction's sign.
public enum TransactionType: String, Codable, Sendable, CaseIterable {
    /// Money out. Signed `-amountCents`.
    case expense
    /// Money in. Signed `+amountCents`.
    case income
    /// The outflow leg of a transfer. Signed `-amountCents`.
    case transferOut
    /// The inflow leg of a transfer. Signed `+amountCents`.
    case transferIn
    /// A manual balance correction. Signed by `signedOverrideCents`.
    case adjustment
}

/// How often a ``RecurringRule`` generates an occurrence.
public enum RecurringFrequency: String, Codable, Sendable, CaseIterable {
    /// Every seven days.
    case weekly
    /// Every fourteen days.
    case biweekly
    /// The same day each month, clamped to the last day of shorter months.
    case monthly
    /// The same day each year.
    case yearly
}

/// Which picker a ``Category`` belongs to.
public enum CategoryContext: String, Codable, Sendable, CaseIterable {
    /// Shown when logging an expense.
    case expense
    /// Shown when logging income.
    case income
    /// Shown when adding a product to a purchase.
    case product
}

/// How far ahead of a date a reminder notification fires.
public enum ReminderLeadTime: String, Codable, Sendable, CaseIterable {
    /// Defer to `AppSettings.defaultReminderLeadTime`.
    case useDefault
    /// No reminder.
    case off
    /// On the day itself.
    case sameDay
    /// One day beforehand.
    case oneDayBefore
    /// Three days beforehand.
    case threeDaysBefore
    /// One week beforehand.
    case oneWeekBefore
}

/// The dimension a unit measures, used to constrain Compare's unit pickers.
public enum UnitCategory: String, Codable, Sendable, CaseIterable {
    /// Grams, kilograms, pounds, ounces.
    case mass
    /// Millilitres, litres, fluid ounces, gallons.
    case volume
    /// Countable items.
    case quantity
}

/// Tracks a receipt image's progress toward cloud storage.
///
/// A receipt is only evictable from the local cache once ``uploaded`` (§9.5).
public enum ReceiptUploadState: String, Codable, Sendable, CaseIterable {
    /// No receipt attached.
    case none
    /// Stored locally, awaiting upload.
    case pending
    /// Present in cloud storage; safe to evict from the cache.
    case uploaded
    /// Upload failed; must be retried and must not be evicted.
    case failed
}

/// How often a backup archive is written (§9.4).
public enum BackupInterval: String, Codable, Sendable, CaseIterable {
    /// Never back up automatically.
    case off
    /// Write an archive weekly.
    case weekly
    /// Write an archive monthly.
    case monthly
}

/// The payment network a card runs on, as printed on a receipt's tender line (§9.7).
///
/// Recorded on an ``Account`` so a scanned receipt can be matched back to the card it
/// was paid with. Purely an identification aid — it affects no balance and no total.
public enum CardNetwork: String, Codable, Sendable, CaseIterable {
    /// Visa.
    case visa
    /// Mastercard.
    case mastercard
    /// American Express.
    case amex
    /// Discover.
    case discover
    /// Interac, the Canadian debit network.
    case interac
    /// UnionPay.
    case unionpay

    /// The name to show in a picker.
    public var displayName: String {
        switch self {
        case .visa: return "Visa"
        case .mastercard: return "Mastercard"
        case .amex: return "American Express"
        case .discover: return "Discover"
        case .interac: return "Interac"
        case .unionpay: return "UnionPay"
        }
    }
}
