import Foundation

/// Matches a scanned receipt's card details to one of the user's accounts (§9.7).
///
/// **Ambiguity always returns `nil`.** Choosing the wrong account puts real money
/// against the wrong balance, and a silently wrong pre-fill is worse than an empty one —
/// the user reads an unfilled field, but skims a filled one. So a match is reported only
/// when exactly one account can be meant, and every other case leaves the picker alone.
public enum AccountMatcher {

    /// Finds the one account a receipt's payment line identifies.
    ///
    /// Closed accounts are never matched: they are kept for history (§4.7), not for new
    /// entries.
    ///
    /// - Parameters:
    ///   - tender: What the receipt's payment line said.
    ///   - accounts: The accounts to match against.
    /// - Returns: The account's identifier, or `nil` when nothing matches unambiguously.
    public static func match(_ tender: ReceiptTender, in accounts: [Account]) -> UUID? {
        sole(candidates(tender, in: accounts))
    }

    /// Every open account a tender could mean, before the sole-candidate rule is applied.
    ///
    /// Exposed so a caller that must distinguish *no such card* from *more than one card*
    /// — statement import, which may auto-create the first but never the second — can reuse
    /// these rules rather than restate them. ``match(_:in:)`` remains the way to get an
    /// answer; this is the way to see why there wasn't one.
    ///
    /// - Parameters:
    ///   - tender: What the payment line said.
    ///   - accounts: The accounts to match against.
    /// - Returns: The candidates, which may be empty or hold several.
    public static func candidates(_ tender: ReceiptTender, in accounts: [Account]) -> [Account] {
        guard !tender.isEmpty else { return [] }
        let open = accounts.filter { !$0.isClosed }

        if let last4 = tender.last4 {
            let byDigits = open.filter { $0.last4 == last4 }

            // Both known: the strongest signal the receipt can give.
            if let network = tender.network {
                let exact = byDigits.filter { $0.cardNetwork == network }
                if exact.count == 1 { return exact }
            }
            // Digits were printed but match no account the user has recorded. That is a
            // card they have not set up, so falling through to the network would pick a
            // *different* card of theirs — which is exactly the wrong-balance mistake.
            return byDigits
        }

        guard let network = tender.network else { return [] }
        return open.filter { $0.cardNetwork == network }
    }

    /// The single account in a candidate list, or `nil` when there is not exactly one.
    /// - Parameter accounts: The candidates.
    /// - Returns: The sole candidate's identifier.
    static func sole(_ accounts: [Account]) -> UUID? {
        accounts.count == 1 ? accounts.first?.id : nil
    }
}
