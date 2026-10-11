import Foundation

/// Which way a category's spend moved against the prior month.
public enum CategoryTrendDirection: String, Sendable, Equatable, CaseIterable {
    /// Spend rose.
    case increase
    /// Spend fell.
    case decrease
}

/// One category's month-over-month spend move (§7.1).
///
/// Carries no rendered sentence on purpose: formatting money needs
/// `AppSettings.currencyCode`, which this module does not know about. The Features
/// layer phrases it.
public struct CategorySpendInsight: Identifiable, Equatable, Sendable {
    /// The category that moved.
    public let categoryID: UUID
    /// That category's display label, resolved when the insight was built.
    public let label: String
    /// This month's spend so far, in cents, as a positive magnitude.
    public let currentCents: Int
    /// Last month's full spend, in cents, as a positive magnitude.
    public let priorCents: Int
    /// Which way it moved.
    public let direction: CategoryTrendDirection
    /// The move as an unsigned, rounded percentage of last month.
    ///
    /// `nil` when last month was zero — a percentage against nothing is not a figure.
    /// The Features layer then shows the currency magnitude alone, exactly as the
    /// whole-account insights already do.
    public let percentChange: Int?

    /// The signed change in cents. Positive when spend rose.
    public var deltaCents: Int { currentCents - priorCents }

    /// The insight's identity, which is the category's.
    public var id: UUID { categoryID }

    /// Creates an insight.
    /// - Parameters:
    ///   - categoryID: The category that moved.
    ///   - label: Its display label.
    ///   - currentCents: This month's spend.
    ///   - priorCents: Last month's spend.
    ///   - direction: Which way it moved.
    ///   - percentChange: The unsigned percentage, or `nil` against a zero prior month.
    public init(
        categoryID: UUID,
        label: String,
        currentCents: Int,
        priorCents: Int,
        direction: CategoryTrendDirection,
        percentChange: Int?
    ) {
        self.categoryID = categoryID
        self.label = label
        self.currentCents = currentCents
        self.priorCents = priorCents
        self.direction = direction
        self.percentChange = percentChange
    }
}

/// Picks the one category worth saying something about this month (§7.1).
///
/// Eligibility is delegated to ``TotalsEngine/countsTowardTotals(_:asOf:)`` rather
/// than re-implemented, so unposted entries, both transfer legs and adjustments are
/// excluded on exactly the same terms as every other total in the app. Month
/// boundaries come from ``LedgerPeriod``, which already handles varying month
/// lengths and the year boundary.
public enum CategoryInsightEngine {

    /// The smallest monthly spend a category must reach, in either month, to qualify.
    ///
    /// A real monthly category lands somewhere between $100 and $600, so $25 sits
    /// below anything genuine while excluding incidentals — a $6 habit rising to $8
    /// never becomes a candidate, however large its percentage.
    public static let minimumSpendCents = 2_500

    /// The smallest month-over-month move worth a sentence: roughly one coffee run.
    public static let minimumDeltaCents = 1_000

    /// The smallest percentage move worth a sentence, when a prior month exists.
    public static let minimumPercentChange = 10

    /// How many days of the current month must have elapsed before a *fall* is believable.
    ///
    /// On the 3rd of the month every category is "down 90%" against a full prior
    /// month, which is an artefact of the partial window rather than a change in
    /// behaviour. A *rise* cannot be an artefact — spending more in three days than
    /// in all of last month is real — so rises are never suppressed.
    public static let minimumElapsedDaysForFall = 7

    /// The most noteworthy category move this month.
    /// - Parameters:
    ///   - transactions: Every transaction.
    ///   - categories: Every category, for resolving labels.
    ///   - reference: The date deciding which month is "this" month.
    ///   - calendar: The calendar deciding month boundaries.
    /// - Returns: The insight, or `nil` when nothing clears the thresholds.
    public static func topMovingCategory(
        transactions: [Transaction],
        categories: [Category],
        reference: Date = .now,
        calendar: Calendar = .current
    ) -> CategorySpendInsight? {
        rankedMovingCategories(
            transactions: transactions, categories: categories,
            reference: reference, calendar: calendar
        ).first
    }

    /// Every qualifying category move, most noteworthy first.
    ///
    /// Ranked by the size of the move in **cents**, not by percentage: cents is what
    /// a person actually feels, and ranking by percentage always surfaces whichever
    /// small category happened to double. Ties fall back to the percentage and then
    /// to the label, so the order is deterministic.
    ///
    /// - Parameters:
    ///   - transactions: Every transaction.
    ///   - categories: Every category, for resolving labels.
    ///   - reference: The date deciding which month is "this" month.
    ///   - calendar: The calendar deciding month boundaries.
    /// - Returns: The qualifying insights, most noteworthy first.
    public static func rankedMovingCategories(
        transactions: [Transaction],
        categories: [Category],
        reference: Date = .now,
        calendar: Calendar = .current
    ) -> [CategorySpendInsight] {
        guard let current = LedgerPeriod.thisMonth
            .dateRange(containing: reference, calendar: calendar),
            let prior = LedgerPeriod.lastMonth
                .dateRange(containing: reference, calendar: calendar)
        else { return [] }

        var labelsByID: [UUID: String] = [:]
        for category in categories where !SystemCategoryID.isSystem(category.id) {
            labelsByID[category.id] = category.label
        }
        let window = MonthWindow(current: current, prior: prior, reference: reference)
        let totals = totals(
            transactions: transactions, labelsByID: labelsByID, window: window
        )
        let elapsedDays = window.elapsedDays(calendar: calendar)

        return labelsByID.keys
            .compactMap { id -> CategorySpendInsight? in
                guard let label = labelsByID[id] else { return nil }
                return insight(
                    from: Candidate(
                        categoryID: id, label: label,
                        currentCents: totals.current[id] ?? 0,
                        priorCents: totals.prior[id] ?? 0
                    ),
                    elapsedDays: elapsedDays
                )
            }
            .sorted(by: isMoreNoteworthy)
    }

    /// The two calendar months an insight compares, and the moment it reads them at.
    private struct MonthWindow {
        /// This month's range.
        let current: ClosedRange<Date>
        /// Last month's range.
        let prior: ClosedRange<Date>
        /// The moment posting is evaluated against.
        let reference: Date

        /// How many days of the current month have elapsed.
        /// - Parameter calendar: The calendar to count in.
        /// - Returns: The elapsed whole days.
        func elapsedDays(calendar: Calendar) -> Int {
            calendar.dateComponents([.day], from: current.lowerBound, to: reference).day ?? 0
        }
    }

    /// One category's spend in both months, before the thresholds are applied.
    private struct Candidate {
        /// The category.
        let categoryID: UUID
        /// Its display label.
        let label: String
        /// This month's spend, in cents.
        let currentCents: Int
        /// Last month's spend, in cents.
        let priorCents: Int
    }

    /// Sums each category's spend across both months in a single pass.
    /// - Parameters:
    ///   - transactions: Every transaction.
    ///   - labelsByID: The categories eligible for an insight.
    ///   - window: The months to compare.
    /// - Returns: Per-category totals for each month, in cents.
    private static func totals(
        transactions: [Transaction],
        labelsByID: [UUID: String],
        window: MonthWindow
    ) -> (current: [UUID: Int], prior: [UUID: Int]) {
        var thisMonth: [UUID: Int] = [:]
        var lastMonth: [UUID: Int] = [:]
        for transaction in transactions {
            guard transaction.type == .expense,
                  transaction.transferGroupID == nil,
                  TotalsEngine.countsTowardTotals(transaction, asOf: window.reference),
                  let categoryID = transaction.categoryID,
                  labelsByID[categoryID] != nil else { continue }
            if window.current.contains(transaction.date) {
                thisMonth[categoryID, default: 0] += transaction.amountCents
            } else if window.prior.contains(transaction.date) {
                lastMonth[categoryID, default: 0] += transaction.amountCents
            }
        }
        return (thisMonth, lastMonth)
    }

    /// Builds one insight, applying every threshold.
    /// - Parameters:
    ///   - candidate: The category and its two monthly totals.
    ///   - elapsedDays: How many days of this month have passed.
    /// - Returns: The insight, or `nil` when it does not clear the thresholds.
    private static func insight(
        from candidate: Candidate,
        elapsedDays: Int
    ) -> CategorySpendInsight? {
        let delta = candidate.currentCents - candidate.priorCents
        guard delta != 0,
              max(candidate.currentCents, candidate.priorCents) >= minimumSpendCents,
              abs(delta) >= minimumDeltaCents else { return nil }
        let direction: CategoryTrendDirection = delta > 0 ? .increase : .decrease
        guard direction == .increase || elapsedDays >= minimumElapsedDaysForFall else { return nil }

        var percent: Int?
        if candidate.priorCents > 0 {
            // A transient ratio only: money in this type stays `Int` cents. The same
            // arithmetic the whole-account insight uses, so the two can never round apart.
            let rounded = Int(
                (Double(abs(delta)) / Double(candidate.priorCents) * 100).rounded()
            )
            guard rounded >= minimumPercentChange else { return nil }
            percent = rounded
        }
        return CategorySpendInsight(
            categoryID: candidate.categoryID, label: candidate.label,
            currentCents: candidate.currentCents, priorCents: candidate.priorCents,
            direction: direction, percentChange: percent
        )
    }

    /// Orders two insights, most noteworthy first.
    ///
    /// A category with no prior month sorts as maximally proportional, since its
    /// percentage is undefined rather than small.
    ///
    /// - Parameters:
    ///   - lhs: The first insight.
    ///   - rhs: The second insight.
    /// - Returns: `true` when `lhs` should come first.
    private static func isMoreNoteworthy(
        _ lhs: CategorySpendInsight, _ rhs: CategorySpendInsight
    ) -> Bool {
        if abs(lhs.deltaCents) != abs(rhs.deltaCents) {
            return abs(lhs.deltaCents) > abs(rhs.deltaCents)
        }
        let leftPercent = lhs.percentChange ?? Int.max
        let rightPercent = rhs.percentChange ?? Int.max
        if leftPercent != rightPercent { return leftPercent > rightPercent }
        return lhs.label < rhs.label
    }
}
