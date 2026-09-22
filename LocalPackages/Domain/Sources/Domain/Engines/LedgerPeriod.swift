import Foundation

/// The Ledger's period filter (§7.4).
public enum LedgerPeriod: String, CaseIterable, Identifiable, Sendable {
    /// The calendar month containing today.
    case thisMonth
    /// The calendar month before this one.
    case lastMonth
    /// Every transaction ever recorded.
    case allTime

    /// The case's identity, for `ForEach`.
    public var id: String { rawValue }

    /// Computes the period's boundaries from real calendar-month dates.
    ///
    /// Boundaries are derived from the calendar rather than by subtracting fixed
    /// day counts, so months of different lengths and the year boundary are handled.
    ///
    /// - Parameters:
    ///   - reference: The date deciding which month is "this" month.
    ///   - calendar: The calendar to compute in.
    /// - Returns: The inclusive range, or `nil` for ``allTime``, which has no bounds.
    public func dateRange(
        containing reference: Date = .now,
        calendar: Calendar = .current
    ) -> ClosedRange<Date>? {
        switch self {
        case .allTime:
            return nil
        case .thisMonth:
            return Self.monthRange(containing: reference, calendar: calendar)
        case .lastMonth:
            guard let previous = calendar.date(byAdding: .month, value: -1, to: reference) else {
                return nil
            }
            return Self.monthRange(containing: previous, calendar: calendar)
        }
    }

    /// Builds the inclusive range covering one calendar month.
    /// - Parameters:
    ///   - date: Any date inside the month.
    ///   - calendar: The calendar to compute in.
    /// - Returns: From the first instant of the month to the last instant of its final day.
    private static func monthRange(containing date: Date, calendar: Calendar) -> ClosedRange<Date>? {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return nil }
        // `dateInterval` ends at the first instant of the next month, which would let
        // a transaction dated exactly at midnight fall into two periods.
        let lastInstant = interval.end.addingTimeInterval(-0.001)
        guard interval.start <= lastInstant else { return nil }
        return interval.start...lastInstant
    }
}

/// The Ledger's combined filter state, and the global search's (§7.4, §7.12).
///
/// Period, account and category combine with AND. Any combination may legitimately
/// yield zero rows, which is a different state from having no transactions at all.
///
/// ``search``, ``tags`` and ``receiptsOnly`` default to inert, so the Ledger's own filter
/// bar — which sets only the first three — behaves exactly as it did before search
/// existed. The search screen sets all six.
public struct LedgerFilter: Equatable, Sendable {
    /// The selected period.
    public var period: LedgerPeriod
    /// The selected account, or `nil` for all accounts.
    public var accountID: UUID?
    /// The selected category, or `nil` for all categories.
    public var categoryID: UUID?
    /// The live search term, matched against merchant, memo, location and tags.
    public var search: String
    /// Tags a transaction must carry **all** of, or empty for no tag restriction.
    public var tags: Set<String>
    /// Whether to show only transactions carrying a receipt image.
    public var receiptsOnly: Bool

    /// Whether any account filter is active, which decides how transfers render (§4.3).
    public var isAccountFiltered: Bool { accountID != nil }

    /// Creates a filter.
    /// - Parameters:
    ///   - period: The selected period.
    ///   - accountID: The selected account, or `nil` for all.
    ///   - categoryID: The selected category, or `nil` for all.
    ///   - search: The search term.
    ///   - tags: Tags a transaction must carry all of.
    ///   - receiptsOnly: Whether to require a receipt.
    public init(
        period: LedgerPeriod = .thisMonth,
        accountID: UUID? = nil,
        categoryID: UUID? = nil,
        search: String = "",
        tags: Set<String> = [],
        receiptsOnly: Bool = false
    ) {
        self.period = period
        self.accountID = accountID
        self.categoryID = categoryID
        self.search = search
        self.tags = tags
        self.receiptsOnly = receiptsOnly
    }

    /// Whether any criterion is narrowing the list.
    ///
    /// Lets a view tell "you have nothing yet" apart from "nothing matched" (§7.0).
    /// Compared against a filter carrying this one's period, because a period is always
    /// set and so is never by itself evidence that the user narrowed anything.
    public var isNarrowing: Bool {
        self != LedgerFilter(period: period)
    }

    /// Applies every criterion at once.
    ///
    /// Search is a live, case-insensitive substring match on the merchant, the memo, the
    /// location or any one tag. Tags are ANDed: selecting two shows transactions carrying
    /// both.
    ///
    /// - Parameters:
    ///   - transactions: The transactions to filter.
    ///   - reference: The date deciding which month is "this" month.
    ///   - calendar: The calendar to compute period boundaries in.
    /// - Returns: The matching transactions, posted and unposted alike.
    public func apply(
        to transactions: [Transaction],
        reference: Date = .now,
        calendar: Calendar = .current
    ) -> [Transaction] {
        let range = period.dateRange(containing: reference, calendar: calendar)
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return transactions.filter { transaction in
            if let range, !range.contains(transaction.date) { return false }
            if let accountID, transaction.accountID != accountID { return false }
            if let categoryID, transaction.categoryID != categoryID { return false }
            if receiptsOnly, transaction.receiptFileID == nil { return false }
            if !tags.isEmpty, !tags.isSubset(of: Set(transaction.tags)) { return false }
            guard !term.isEmpty else { return true }
            return Self.matches(transaction, term: term)
        }
    }

    /// Whether a transaction's text carries the search term.
    /// - Parameters:
    ///   - transaction: The transaction to test.
    ///   - term: The already-trimmed search term.
    /// - Returns: `true` when the merchant, memo, location or any tag contains it.
    private static func matches(_ transaction: Transaction, term: String) -> Bool {
        if transaction.merchant.range(of: term, options: .caseInsensitive) != nil {
            return true
        }
        if transaction.memo?.range(of: term, options: .caseInsensitive) != nil {
            return true
        }
        if transaction.location?.range(of: term, options: .caseInsensitive) != nil {
            return true
        }
        return transaction.tags.contains { $0.range(of: term, options: .caseInsensitive) != nil }
    }
}
