import Foundation

/// The key two records of the same purchase share, used to recognise a statement row
/// the ledger already holds (§4.2).
///
/// **The key is the tuple, not a digest of it.** A composite string collides only when the
/// card, the day, the signed amount *and* the normalised merchant all agree — which is the
/// definition of the same purchase. Digesting would trade that exactness for nothing:
/// merchant, amount and date are already stored in plaintext in the same row.
///
/// **`Hasher` is deliberately not used.** Swift seeds it per process, so the same
/// transaction would fingerprint differently on the next launch and every import would
/// re-add everything.
public enum TransactionFingerprint {

    /// Separates the components. No component can contain it: ``MerchantCategoryIndex/key(for:)``
    /// emits only `[a-z0-9-]`, and a UUID, an ISO day and a signed integer are likewise free of it.
    public static let separator = "|"

    /// The format's version, so a later change to the shape is detectable rather than silent.
    public static let version = "v1"

    /// The fingerprint of a stored transaction.
    /// - Parameters:
    ///   - transaction: The transaction to fingerprint.
    ///   - calendar: The calendar deciding which day the date falls on.
    /// - Returns: The canonical key.
    public static func key(for transaction: Transaction, calendar: Calendar = .current) -> String {
        key(
            accountID: transaction.accountID,
            date: transaction.date,
            signedCents: BalanceEngine.signedAmountCents(for: transaction),
            merchant: transaction.merchant,
            calendar: calendar
        )
    }

    /// The fingerprint of a purchase that is not a transaction yet.
    ///
    /// Signed cents rather than the transaction's type: a $50 refund must not collide with
    /// a $50 charge, and a statement credit of $50 *should* match a card payment of $50 the
    /// user already recorded — which the sign gives free and a type comparison would not.
    ///
    /// - Parameters:
    ///   - accountID: The account the entry belongs to.
    ///   - date: When it occurred.
    ///   - signedCents: The signed amount, from ``BalanceEngine/signedAmountCents(for:)``.
    ///   - merchant: The merchant name, in any spelling.
    ///   - calendar: The calendar deciding which day the date falls on.
    /// - Returns: The canonical key.
    public static func key(
        accountID: UUID?,
        date: Date,
        signedCents: Int,
        merchant: String,
        calendar: Calendar = .current
    ) -> String {
        [
            version,
            accountID?.uuidString ?? "none",
            day(date, calendar: calendar),
            String(signedCents),
            MerchantCategoryIndex.key(for: merchant)
        ].joined(separator: separator)
    }

    /// The key without the merchant — what a fuzzy candidate shares with its match.
    ///
    /// Two rows with the same value here but different merchant keys are the case this
    /// whole feature exists for: the user's own wording against the bank's descriptor.
    ///
    /// - Parameters:
    ///   - accountID: The account the entry belongs to.
    ///   - date: When it occurred.
    ///   - signedCents: The signed amount.
    ///   - calendar: The calendar deciding which day the date falls on.
    /// - Returns: The card-day-amount key.
    public static func dayAmountKey(
        accountID: UUID?,
        date: Date,
        signedCents: Int,
        calendar: Calendar = .current
    ) -> String {
        [
            version,
            accountID?.uuidString ?? "none",
            day(date, calendar: calendar),
            String(signedCents)
        ].joined(separator: separator)
    }

    /// The key without the merchant *or* the day — the bucket a fuzzy search scans.
    ///
    /// Posting lag means the day is exactly what two readings of one purchase disagree
    /// about, so it cannot be part of the key that groups candidates together. The day is
    /// then compared inside the bucket, against a tolerance.
    ///
    /// - Parameters:
    ///   - accountID: The account the entry belongs to.
    ///   - signedCents: The signed amount.
    /// - Returns: The card-amount key.
    public static func amountKey(accountID: UUID?, signedCents: Int) -> String {
        [
            version,
            accountID?.uuidString ?? "none",
            String(signedCents)
        ].joined(separator: separator)
    }

    /// The date as `yyyy-MM-dd`.
    ///
    /// Read positionally off the date components rather than through `DateFormatter`, which
    /// is locale-dependent, calendar-dependent, and expensive to build. A Japanese locale
    /// would otherwise fingerprint the same day as a different string.
    ///
    /// - Parameters:
    ///   - date: The date to render.
    ///   - calendar: The calendar deciding which day it falls on.
    /// - Returns: The ISO day.
    static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        let dayOfMonth = parts.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
    }
}

/// Fingerprint access on a transaction.
extension Transaction {

    /// The import fingerprint, computed fresh.
    ///
    /// Computed rather than stored so it can never drift out of step with an edited
    /// merchant, amount or date — for a dedup key, a stale value means a duplicate slips
    /// through. ``TransactionRecord`` keeps a denormalised copy purely so the store can be
    /// queried by it, exactly as `Account.cachedBalanceCents` caches a derived balance.
    public var transactionHash: String { TransactionFingerprint.key(for: self) }

    /// The fingerprint under a specific calendar.
    /// - Parameter calendar: The calendar deciding which day the date falls on.
    /// - Returns: The canonical key.
    public func transactionHash(calendar: Calendar) -> String {
        TransactionFingerprint.key(for: self, calendar: calendar)
    }
}
