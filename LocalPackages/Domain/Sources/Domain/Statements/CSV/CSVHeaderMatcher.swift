import Foundation

/// Works out which column is which from the header row alone (§9.7).
///
/// The deterministic counterpart to the on-device model's reading of the same header, and
/// what actually makes CSV import safe: it runs everywhere — Simulator, older device, model
/// declined — and it needs no network, no prompt and no user input.
///
/// Headers are compared on the slug ``MerchantCategoryIndex/key(for:)`` produces, so
/// `"Transaction Date"`, `"TRANSACTION DATE"` and `"Transaction  Date"` are one string.
/// Reused rather than written again for the reason §9.3 gives: two normalisers drift.
public enum CSVHeaderMatcher {

    /// A field's aliases, best first.
    ///
    /// Order is the tie-break: the earlier alias wins when a header could serve two fields,
    /// which is why `date` sits *last* among the transaction-date aliases — a file printing
    /// both `Transaction Date` and `Date` means the specific one.
    struct Aliases {
        /// Exact slugs, in preference order.
        let exact: [String]
        /// Substrings accepted when nothing matched exactly.
        let contains: [String]

        /// Creates an alias set.
        /// - Parameters:
        ///   - exact: Exact slugs, in preference order.
        ///   - contains: Substrings accepted as a weaker match.
        init(_ exact: [String], contains: [String] = []) {
            self.exact = exact
            self.contains = contains
        }
    }

    /// Aliases for the day the purchase was made.
    static let transactionDate = Aliases(
        ["transaction-date", "trans-date", "purchase-date", "activity-date", "date"],
        contains: ["transaction-date", "trans-date"]
    )
    /// Aliases for the day the bank posted it.
    static let postingDate = Aliases(
        ["posting-date", "post-date", "posted-date", "posted", "value-date", "settlement-date"],
        contains: ["posting-date", "post-date", "posted"]
    )
    /// Aliases for the merchant descriptor.
    static let descriptor = Aliases(
        [
            "description", "merchant", "payee", "name", "details", "narrative",
            "transaction-description", "merchant-name", "particulars", "memo", "reference"
        ],
        contains: ["description", "merchant", "payee", "narrative", "details"]
    )
    /// Aliases for a single signed amount column.
    static let amount = Aliases(
        ["amount", "transaction-amount", "amount-usd", "value", "sum"],
        contains: ["amount"]
    )
    /// Aliases for money leaving the account.
    static let debit = Aliases(
        ["debit", "debits", "withdrawal", "withdrawals", "money-out", "charges", "debit-amount",
         "paid-out"],
        contains: ["debit", "withdrawal", "money-out", "paid-out"]
    )
    /// Aliases for money coming in.
    static let credit = Aliases(
        ["credit", "credits", "deposit", "deposits", "money-in", "payments", "credit-amount",
         "paid-in"],
        contains: ["credit", "deposit", "money-in", "paid-in"]
    )

    /// Aliases for a column naming each row's direction in words.
    static let directionIndicator = Aliases(
        ["type", "dr-cr", "drcr", "cr-dr", "debit-credit", "transaction-type", "direction",
         "indicator", "dr-or-cr"],
        contains: ["dr-cr", "drcr", "transaction-type"]
    )

    /// Reads a header row into a column map.
    ///
    /// Fields are claimed in order of how distinctive their vocabulary is, and a claimed
    /// header is removed from the pool before the next field looks. Without that, a file
    /// printing `Transaction Date` and `Posting Date` would hand the same column to both —
    /// `posting-date` contains no transaction-date alias, but `Date` alone matches either.
    ///
    /// - Parameter headers: The header row, exactly as the file printed it.
    /// - Returns: What could be worked out. Check ``CSVStatementColumns/isUsable``.
    public static func columns(for headers: [String]) -> CSVStatementColumns {
        var pool = headers.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var map = CSVStatementColumns()

        map.postingDate = claim(postingDate, from: &pool)
        map.transactionDate = claim(transactionDate, from: &pool)
        map.descriptor = claim(descriptor, from: &pool) ?? ""

        // Claimed before the debit and credit columns, so a file printing "Type" alongside
        // one signed "Amount" does not have its indicator mistaken for a money column.
        map.directionIndicator = claim(directionIndicator, from: &pool)

        let debitColumn = claim(debit, from: &pool)
        let creditColumn = claim(credit, from: &pool)
        // A split pair beats a single column: when a file carries both, the pair is the
        // one that needs no sign convention guessed.
        if let debitColumn, let creditColumn {
            map.amount = .debitCredit(debit: debitColumn, credit: creditColumn)
        } else {
            map.amount = .single(claim(amount, from: &pool) ?? debitColumn ?? creditColumn ?? "")
        }
        return map
    }

    /// Takes the best header for a field out of the pool.
    /// - Parameters:
    ///   - aliases: The field's aliases.
    ///   - pool: The headers still unclaimed. The winner is removed.
    /// - Returns: The header as the file printed it, or `nil` when nothing matched.
    static func claim(_ aliases: Aliases, from pool: inout [String]) -> String? {
        guard let index = bestIndex(aliases, in: pool) else { return nil }
        return pool.remove(at: index)
    }

    /// The index of the header that best fits a field.
    /// - Parameters:
    ///   - aliases: The field's aliases.
    ///   - pool: The headers to search.
    /// - Returns: The index, or `nil` when nothing matched.
    static func bestIndex(_ aliases: Aliases, in pool: [String]) -> Int? {
        let keys = pool.map { MerchantCategoryIndex.key(for: $0) }
        for alias in aliases.exact {
            if let index = keys.firstIndex(of: alias) { return index }
        }
        for fragment in aliases.contains {
            if let index = keys.firstIndex(where: { $0.contains(fragment) }) { return index }
        }
        return nil
    }
}
