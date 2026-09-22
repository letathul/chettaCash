import Foundation

/// The Today section for entries that have no account yet (§15.5).
///
/// Split from ``TodayBuilder`` itself to keep each file within the 300-line limit.
extension TodayBuilder {

    /// Entries written with no account, newest first.
    ///
    /// Deliberately **not** filtered by ``BalanceEngine/isPosted(_:asOf:)``, unlike every
    /// other section here. A future-dated parked entry is still missing an account, and
    /// waiting until its date arrives to mention it would hide the one thing the user has to
    /// fix — and hide it for exactly as long as it is easiest to fix.
    ///
    /// Recognised by `accountID == nil` alone. Nothing else in the app produces one: the
    /// transaction form requires an account before it will save, and statement import always
    /// has the card it imported from.
    ///
    /// - Parameter input: The digest inputs.
    /// - Returns: The items, newest first.
    static func unassignedEntries(_ input: TodayInput) -> [UnassignedEntryItem] {
        input.transactions
            .filter { $0.accountID == nil }
            .sorted { $0.date > $1.date }
            .map { UnassignedEntryItem(transaction: $0) }
    }
}
