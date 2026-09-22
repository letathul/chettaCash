import Foundation

/// How far an edit or delete reaches through a recurring series (§4.5).
public enum SeriesScope: String, CaseIterable, Identifiable, Sendable {
    /// Detaches one occurrence, leaving the rule untouched.
    case thisOccurrence
    /// Ends the current rule here and starts a new one with the new values.
    case thisAndFuture
    /// Applies retroactively, rewriting already-posted history.
    case allIncludingPast

    /// The case's identity, for `ForEach`.
    public var id: String { rawValue }

    /// Whether choosing this scope rewrites history and so needs an explicit warning.
    ///
    /// The warning must name the consequence concretely rather than asking a generic
    /// "are you sure" (§4.5).
    public var rewritesHistory: Bool { self == .allIncludingPast }
}

/// The writes an edit or delete implies.
public struct SeriesPlan: Equatable, Sendable {
    /// Transactions to insert or update.
    public var updatedTransactions: [Transaction]
    /// Transactions to remove.
    public var deletedTransactionIDs: [UUID]
    /// Rules to insert or update.
    public var updatedRules: [RecurringRule]
    /// Rules to remove entirely.
    public var deletedRuleIDs: [UUID]

    /// Creates a plan.
    /// - Parameters:
    ///   - updatedTransactions: Transactions to insert or update.
    ///   - deletedTransactionIDs: Transactions to remove.
    ///   - updatedRules: Rules to insert or update.
    ///   - deletedRuleIDs: Rules to remove.
    public init(
        updatedTransactions: [Transaction] = [],
        deletedTransactionIDs: [UUID] = [],
        updatedRules: [RecurringRule] = [],
        deletedRuleIDs: [UUID] = []
    ) {
        self.updatedTransactions = updatedTransactions
        self.deletedTransactionIDs = deletedTransactionIDs
        self.updatedRules = updatedRules
        self.deletedRuleIDs = deletedRuleIDs
    }
}

/// A rule together with the occurrences it has generated.
public struct RecurringSeries: Sendable {
    /// The rule.
    public let rule: RecurringRule
    /// Its occurrences, oldest first.
    public let occurrences: [Transaction]

    /// Creates a series.
    /// - Parameters:
    ///   - rule: The rule.
    ///   - occurrences: Its occurrences.
    public init(rule: RecurringRule, occurrences: [Transaction]) {
        self.rule = rule
        self.occurrences = occurrences
    }
}

/// Plans scoped edits and deletes across a recurring series (§4.5).
public enum SeriesPlanner {

    /// Plans an edit at the chosen scope.
    ///
    /// - Parameters:
    ///   - series: The rule and its occurrences.
    ///   - target: The occurrence the user opened.
    ///   - scope: How far the edit reaches.
    ///   - edited: The target carrying the user's new values.
    ///   - calendar: The calendar used when ending the old rule.
    /// - Returns: The writes to apply.
    public static func planEdit(
        series: RecurringSeries,
        target: Transaction,
        scope: SeriesScope,
        edited: Transaction,
        calendar: Calendar = .current
    ) -> SeriesPlan {
        switch scope {
        case .thisOccurrence:
            // Detached from the series; the rule keeps generating its own values.
            var override = edited
            override.isSeriesOverride = true
            return SeriesPlan(updatedTransactions: [override])
        case .thisAndFuture:
            return splitSeries(series, target: target, edited: edited, calendar: calendar)
        case .allIncludingPast:
            return rewriteSeries(series, edited: edited)
        }
    }

    /// Ends the current rule at the target and starts a new one with the new values.
    /// - Parameters:
    ///   - series: The rule and its occurrences.
    ///   - target: The occurrence the split happens at.
    ///   - edited: The target carrying the user's new values.
    ///   - calendar: The calendar used when ending the old rule.
    /// - Returns: The writes to apply.
    private static func splitSeries(
        _ series: RecurringSeries,
        target: Transaction,
        edited: Transaction,
        calendar: Calendar
    ) -> SeriesPlan {
        let priorCount = countBefore(target.date, in: series.occurrences)
        var successor = RecurringRule(
            name: edited.merchant,
            amountCents: edited.amountCents,
            type: edited.type,
            categoryID: edited.categoryID,
            accountID: edited.accountID,
            frequency: series.rule.frequency,
            startDate: edited.date,
            endDate: series.rule.endDate,
            occurrenceLimit: series.rule.occurrenceLimit.map { max(0, $0 - priorCount) },
            isActive: true,
            productID: series.rule.productID
        )
        var ended = series.rule
        ended.endDate = calendar.date(byAdding: .second, value: -1, to: target.date)
        ended.occurrencesGenerated = priorCount
        ended.isActive = false

        let moved = series.occurrences
            .filter { $0.date >= target.date }
            .map { applyEditedValues(edited, to: $0, ruleID: successor.id) }
        successor.occurrencesGenerated = moved.count
        return SeriesPlan(updatedTransactions: moved, updatedRules: [ended, successor])
    }

    /// Applies new values to every occurrence, including already-posted ones.
    /// - Parameters:
    ///   - series: The rule and its occurrences.
    ///   - edited: The occurrence carrying the new values.
    /// - Returns: The writes to apply.
    private static func rewriteSeries(
        _ series: RecurringSeries,
        edited: Transaction
    ) -> SeriesPlan {
        var updatedRule = series.rule
        updatedRule.name = edited.merchant
        updatedRule.amountCents = edited.amountCents
        updatedRule.type = edited.type
        updatedRule.categoryID = edited.categoryID
        updatedRule.accountID = edited.accountID
        let rewritten = series.occurrences.map {
            applyEditedValues(edited, to: $0, ruleID: series.rule.id)
        }
        return SeriesPlan(updatedTransactions: rewritten, updatedRules: [updatedRule])
    }

    /// Plans a delete at the chosen scope.
    ///
    /// - Parameters:
    ///   - series: The rule and its occurrences.
    ///   - target: The occurrence the user opened.
    ///   - scope: How far the delete reaches.
    ///   - calendar: The calendar used when ending the rule.
    /// - Returns: The writes to apply.
    public static func planDelete(
        series: RecurringSeries,
        target: Transaction,
        scope: SeriesScope,
        calendar: Calendar = .current
    ) -> SeriesPlan {
        let rule = series.rule
        let occurrences = series.occurrences
        switch scope {
        case .thisOccurrence:
            // The rule's cursor has already advanced past this date, so the engine
            // will not regenerate it on the next pass.
            return SeriesPlan(deletedTransactionIDs: [target.id])

        case .thisAndFuture:
            var ended = rule
            ended.endDate = calendar.date(byAdding: .second, value: -1, to: target.date)
            ended.occurrencesGenerated = countBefore(target.date, in: occurrences)
            ended.isActive = false
            let removed = occurrences.filter { $0.date >= target.date }.map(\.id)
            return SeriesPlan(deletedTransactionIDs: removed, updatedRules: [ended])

        case .allIncludingPast:
            return SeriesPlan(
                deletedTransactionIDs: occurrences.map(\.id),
                deletedRuleIDs: [rule.id]
            )
        }
    }

    /// Copies the user's edited values onto one occurrence, keeping its own date.
    /// - Parameters:
    ///   - edited: The occurrence carrying the new values.
    ///   - occurrence: The occurrence being rewritten.
    ///   - ruleID: The rule the occurrence should now belong to.
    /// - Returns: The rewritten occurrence.
    private static func applyEditedValues(
        _ edited: Transaction,
        to occurrence: Transaction,
        ruleID: UUID
    ) -> Transaction {
        var updated = occurrence
        updated.amountCents = edited.amountCents
        updated.type = edited.type
        updated.categoryID = edited.categoryID
        updated.accountID = edited.accountID
        updated.merchant = edited.merchant
        updated.memo = edited.memo
        updated.recurringRuleID = ruleID
        return updated
    }

    /// Counts the occurrences falling before a date.
    /// - Parameters:
    ///   - date: The boundary.
    ///   - occurrences: The occurrences to count.
    /// - Returns: How many fall strictly before the boundary.
    private static func countBefore(_ date: Date, in occurrences: [Transaction]) -> Int {
        occurrences.filter { $0.date < date }.count
    }
}
