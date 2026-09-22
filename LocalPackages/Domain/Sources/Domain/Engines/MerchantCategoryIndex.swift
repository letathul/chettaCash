import Foundation

/// Looks up how the user has categorised and tagged a merchant before (§9.7).
///
/// The right category for a shop is not a universal fact — it is whatever *this* user
/// decided last time. Someone may file a supermarket under Groceries and someone else
/// under Food & drink, and both are right. So a scan consults history before it asks the
/// language model to classify anything: the answer is personal, free, and deterministic.
public enum MerchantCategoryIndex {

    /// How many times a tag must appear against a merchant before it is suggested.
    ///
    /// Two, so a tag typed once on an unrelated purchase is not offered back as though it
    /// were a habit.
    static let tagThreshold = 2

    /// Reduces a merchant name to the key two spellings of the same shop share.
    ///
    /// Receipts rarely print a name the same way twice: `WHOLE FOODS MKT #10234`,
    /// `Whole Foods Mkt`, and `WHOLE FOODS MKT 10234` are one merchant. Folding to the
    /// slug and dropping a trailing branch number collapses them.
    ///
    /// - Parameter merchant: The merchant name.
    /// - Returns: The comparison key.
    public static func key(for merchant: String) -> String {
        let trimmed = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        // `slug` already folds diacritics and lowercases, which is the same normalisation
        // wanted here — reused rather than written a second time (§9.3).
        let slug = ReceiptNaming.slug(trimmed)
        guard slug != "receipt" else { return "" }

        var parts = slug.split(separator: "-")
        // A trailing all-digit part is a store number, not part of the name. Keep it when
        // it is all there is, so "7-11" does not normalise to nothing.
        if parts.count > 1, parts[parts.count - 1].allSatisfy(\.isNumber) {
            parts.removeLast()
        }
        return parts.joined(separator: "-")
    }

    /// The category this user most often gives this merchant.
    ///
    /// Most-used wins, tie-broken by most recent. Most-recent alone would let a single
    /// mis-tap rewrite a habit built over dozens of purchases.
    ///
    /// - Parameters:
    ///   - merchant: The merchant to look up.
    ///   - transactions: The history to search.
    /// - Returns: The category's identifier, or `nil` when the merchant is new.
    public static func categoryID(for merchant: String, in transactions: [Transaction]) -> UUID? {
        let matches = history(for: merchant, in: transactions)
        guard !matches.isEmpty else { return nil }

        var counts: [UUID: Int] = [:]
        var latest: [UUID: Date] = [:]
        for transaction in matches {
            guard let id = transaction.categoryID, !SystemCategoryID.isSystem(id) else { continue }
            counts[id, default: 0] += 1
            latest[id] = max(latest[id] ?? .distantPast, transaction.date)
        }
        return counts
            .max { first, second in
                if first.value != second.value { return first.value < second.value }
                return (latest[first.key] ?? .distantPast) < (latest[second.key] ?? .distantPast)
            }?
            .key
    }

    /// The tags this user habitually puts on this merchant.
    ///
    /// Offered as suggestions, never applied: tags are unlimited and free-text (§4.8), so
    /// writing them automatically would quietly grow a vocabulary nobody chose.
    ///
    /// - Parameters:
    ///   - merchant: The merchant to look up.
    ///   - transactions: The history to search.
    /// - Returns: The tags, most-used first.
    public static func tags(for merchant: String, in transactions: [Transaction]) -> [String] {
        var counts: [String: Int] = [:]
        var display: [String: String] = [:]
        for transaction in history(for: merchant, in: transactions) {
            // One transaction tagged "weekly" twice is still one use of it.
            for tag in Set(transaction.tags.map { $0.lowercased() }) {
                counts[tag, default: 0] += 1
            }
            for tag in transaction.tags where display[tag.lowercased()] == nil {
                display[tag.lowercased()] = tag
            }
        }
        return counts
            .filter { $0.value >= tagThreshold }
            .sorted { first, second in
                if first.value != second.value { return first.value > second.value }
                return first.key < second.key
            }
            .compactMap { display[$0.key] }
    }

    /// Every past transaction against the same merchant.
    /// - Parameters:
    ///   - merchant: The merchant to look up.
    ///   - transactions: The history to search.
    /// - Returns: The matching transactions.
    private static func history(
        for merchant: String,
        in transactions: [Transaction]
    ) -> [Transaction] {
        let wanted = key(for: merchant)
        guard !wanted.isEmpty else { return [] }
        return transactions.filter { key(for: $0.merchant) == wanted }
    }
}
