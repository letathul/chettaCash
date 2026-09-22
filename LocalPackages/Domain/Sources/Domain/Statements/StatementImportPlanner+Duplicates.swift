import Foundation

/// One ledger entry and whether an incoming row has already claimed it.
///
/// Declared beside the index rather than inside it: nesting it within
/// ``StatementImportPlanner/ExistingIndex`` would put a type three levels deep.
private struct ClaimableEntry {
    /// The entry already in the ledger.
    let transaction: Transaction
    /// Whether a row has already matched it.
    var isClaimed = false
}

/// Duplicate lookup for ``StatementImportPlanner``.
///
/// Split from the planner to keep each file within the 300-line limit.
extension StatementImportPlanner {

    /// An existing transaction paired with why it looks like the incoming row.
    struct FuzzyMatch {
        /// The entry already in the ledger.
        let transaction: Transaction
        /// Why the two were paired.
        let reason: DuplicateReason
    }

    /// The ledger's current contents, indexed for constant-time duplicate lookup.
    ///
    /// Indexed rather than scanned: a statement has up to a few hundred rows and a card can
    /// have thousands of transactions, and comparing every row against every transaction is
    /// the one place this feature could become quadratic.
    ///
    /// **Matches are consumed.** Each existing entry answers at most one incoming row, and
    /// that single rule is what makes the import occurrence-counted rather than
    /// existence-checked: a statement listing one charge against one recorded entry adds
    /// nothing, but a statement listing it *twice* against that same entry still writes the
    /// second — because the statement is evidence of two purchases and the ledger holds one.
    /// It also caps what an import can write at the statement's own row count, since a row
    /// yields at most one addition.
    struct ExistingIndex {

        /// Ledger entries bucketed by card and signed amount.
        ///
        /// The day is deliberately *not* in the key: posting lag is exactly what two
        /// readings of one purchase disagree about, so it is compared within the bucket
        /// against ``StatementImportContext/dayTolerance`` instead.
        private var byAmount: [String: [ClaimableEntry]]

        /// Builds the index.
        /// - Parameter context: What the app already holds.
        init(context: StatementImportContext) {
            var grouped: [String: [ClaimableEntry]] = [:]
            for transaction in context.existing {
                let key = TransactionFingerprint.amountKey(
                    accountID: transaction.accountID,
                    signedCents: BalanceEngine.signedAmountCents(for: transaction)
                )
                grouped[key, default: []].append(ClaimableEntry(transaction: transaction))
            }
            self.byAmount = grouped
        }

        /// Claims the ledger entry that records this very purchase.
        ///
        /// Same card, same signed amount, same merchant once both names are normalised, and
        /// within the tolerance. That is not an ambiguity to put to the user — it is the
        /// same purchase — so it is claimed silently and the row is dropped.
        ///
        /// - Parameters:
        ///   - candidate: The transaction the import would write.
        ///   - context: What the app already holds.
        /// - Returns: The entry claimed, or `nil` when nothing recorded matches.
        mutating func claimSameMerchant(
            _ candidate: Transaction,
            in context: StatementImportContext
        ) -> Transaction? {
            let wanted = MerchantCategoryIndex.key(for: candidate.merchant)
            return claim(candidate, in: context) { existing in
                MerchantCategoryIndex.key(for: existing.merchant) == wanted
            }?.transaction
        }

        /// Claims the ledger entry that may be this purchase under another name.
        ///
        /// Same card and amount within the tolerance, but the wording differs — the user's
        /// own phrasing against the bank's descriptor. That *is* an ambiguity, so it becomes
        /// a conflict rather than a silent drop.
        ///
        /// - Parameters:
        ///   - candidate: The transaction the import would write.
        ///   - context: What the app already holds.
        /// - Returns: The match, or `nil` when nothing resembles it.
        mutating func claimDifferentMerchant(
            _ candidate: Transaction,
            in context: StatementImportContext
        ) -> FuzzyMatch? {
            let wanted = MerchantCategoryIndex.key(for: candidate.merchant)
            return claim(candidate, in: context) { existing in
                MerchantCategoryIndex.key(for: existing.merchant) != wanted
            }
        }

        /// Claims the nearest unclaimed entry in the candidate's bucket that passes a test.
        ///
        /// Searched outward from the candidate's own day, so a same-day match always beats
        /// an adjacent-day one — the nearer reading is the likelier one.
        ///
        /// - Parameters:
        ///   - candidate: The transaction the import would write.
        ///   - context: What the app already holds.
        ///   - isEligible: What makes an entry a match.
        /// - Returns: The match, or `nil` when nothing qualifies.
        private mutating func claim(
            _ candidate: Transaction,
            in context: StatementImportContext,
            where isEligible: (Transaction) -> Bool
        ) -> FuzzyMatch? {
            let key = TransactionFingerprint.amountKey(
                accountID: candidate.accountID,
                signedCents: BalanceEngine.signedAmountCents(for: candidate)
            )
            guard var entries = byAmount[key] else { return nil }

            for offset in offsets(within: context.dayTolerance) {
                guard let date = context.calendar.date(
                    byAdding: .day, value: offset, to: candidate.date
                ) else { continue }
                let wantedDay = TransactionFingerprint.day(date, calendar: context.calendar)

                guard let index = entries.firstIndex(where: { entry in
                    !entry.isClaimed
                        && TransactionFingerprint.day(
                            entry.transaction.date, calendar: context.calendar
                        ) == wantedDay
                        && isEligible(entry.transaction)
                }) else { continue }

                entries[index].isClaimed = true
                byAmount[key] = entries
                return FuzzyMatch(
                    transaction: entries[index].transaction, reason: reason(forOffset: offset)
                )
            }
            return nil
        }

        /// Why two entries that many days apart were paired.
        /// - Parameter offset: How many days apart they are, of either sign.
        /// - Returns: The reason.
        private func reason(forOffset offset: Int) -> DuplicateReason {
            switch abs(offset) {
            case 0: return .sameDaySameAmount
            case 1: return .adjacentDaySameAmount
            default: return .nearbyDaySameAmount
            }
        }

        /// Day offsets to search, nearest first: `0, -1, +1, -2, +2` and so on.
        /// - Parameter tolerance: How many days either side to reach.
        /// - Returns: The offsets in search order.
        private func offsets(within tolerance: Int) -> [Int] {
            guard tolerance > 0 else { return [0] }
            return [0] + (1...tolerance).flatMap { [-$0, $0] }
        }
    }
}
