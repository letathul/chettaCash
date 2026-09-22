import Foundation

/// One row in the Ledger list.
///
/// A transfer occupies a single row when no account filter is active, reading
/// "Chequing → Visa"; with a filter active only the matching leg is shown, as an
/// ordinary row (§4.3).
public enum LedgerItem: Identifiable, Hashable, Sendable {
    /// An ordinary transaction, or one leg of a transfer under an account filter.
    case single(Transaction)
    /// Both legs of a transfer, collapsed into one row.
    case transfer(outLeg: Transaction, inLeg: Transaction)

    /// A stable identity for `ForEach`.
    public var id: UUID {
        switch self {
        case .single(let transaction): return transaction.id
        case .transfer(let outLeg, _): return outLeg.transferGroupID ?? outLeg.id
        }
    }

    /// The date the row sorts and groups by.
    public var date: Date {
        switch self {
        case .single(let transaction): return transaction.date
        case .transfer(let outLeg, _): return outLeg.date
        }
    }

    /// The magnitude shown on the row, in cents.
    public var amountCents: Int {
        switch self {
        case .single(let transaction): return transaction.amountCents
        case .transfer(let outLeg, _): return outLeg.amountCents
        }
    }

    /// The transaction a tap should open — its detail screen, and then its edit form.
    public var editableTransaction: Transaction {
        switch self {
        case .single(let transaction): return transaction
        case .transfer(let outLeg, _): return outLeg
        }
    }
}

/// Builds Ledger rows from filtered transactions (§7.4, §4.3).
public enum LedgerAssembler {

    /// Groups transactions into rows, collapsing transfer pairs when appropriate.
    ///
    /// A transfer collapses into one row only when no account filter is active and
    /// both legs are present. Under an account filter the user asked to see one
    /// account, so only that account's leg is shown.
    ///
    /// - Parameters:
    ///   - transactions: The already-filtered transactions.
    ///   - collapseTransfers: Whether to pair transfer legs into single rows.
    /// - Returns: Rows in reverse chronological order, newest first.
    public static func items(
        from transactions: [Transaction],
        collapseTransfers: Bool
    ) -> [LedgerItem] {
        guard collapseTransfers else {
            return transactions.sorted { $0.date > $1.date }.map(LedgerItem.single)
        }

        var items: [LedgerItem] = []
        var handledGroupIDs: Set<UUID> = []
        let legsByGroup = Dictionary(grouping: transactions.filter { $0.transferGroupID != nil }) {
            $0.transferGroupID ?? UUID()
        }

        for transaction in transactions {
            guard let groupID = transaction.transferGroupID else {
                items.append(.single(transaction))
                continue
            }
            guard !handledGroupIDs.contains(groupID) else { continue }
            handledGroupIDs.insert(groupID)

            let legs = legsByGroup[groupID] ?? []
            if let outLeg = legs.first(where: { $0.type == .transferOut }),
               let inLeg = legs.first(where: { $0.type == .transferIn }) {
                items.append(.transfer(outLeg: outLeg, inLeg: inLeg))
            } else {
                // Only one leg survived the filter — for example a date range that
                // clipped the pair. Show it as an ordinary row rather than dropping it.
                items.append(contentsOf: legs.map(LedgerItem.single))
            }
        }
        return items.sorted { $0.date > $1.date }
    }

    /// Splits rows into the Upcoming section and the posted history (§7.4).
    ///
    /// Unposted rows sit above today's transactions in chronological order — soonest
    /// first — while posted history runs newest first.
    ///
    /// - Parameters:
    ///   - items: The rows to split.
    ///   - asOf: The moment deciding what has posted.
    /// - Returns: The upcoming rows and the posted rows.
    public static func split(
        _ items: [LedgerItem],
        asOf: Date = .now
    ) -> (upcoming: [LedgerItem], posted: [LedgerItem]) {
        let upcoming = items.filter { $0.date > asOf }.sorted { $0.date < $1.date }
        let posted = items.filter { $0.date <= asOf }.sorted { $0.date > $1.date }
        return (upcoming, posted)
    }

    /// Groups posted rows by calendar day, newest day first.
    /// - Parameters:
    ///   - items: The posted rows to group.
    ///   - calendar: The calendar deciding day boundaries.
    /// - Returns: Day starts paired with that day's rows.
    public static func groupedByDay(
        _ items: [LedgerItem],
        calendar: Calendar = .current
    ) -> [(day: Date, items: [LedgerItem])] {
        let groups = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
        return groups
            .map { (day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    /// Counts the transactions the summary banner reports (§4.3, §7.4).
    ///
    /// Transfer legs are excluded because §4.3 removes them from the Ledger summary
    /// banner outright, and adjustments are excluded on the same footing — a
    /// correction is not activity. Both still appear in the list.
    ///
    /// - Parameters:
    ///   - transactions: The already-filtered transactions.
    ///   - asOf: The moment deciding what has posted.
    /// - Returns: How many transactions the banner counts.
    public static func bannerCount(of transactions: [Transaction], asOf: Date = .now) -> Int {
        transactions.filter { TotalsEngine.countsTowardTotals($0, asOf: asOf) }.count
    }
}
