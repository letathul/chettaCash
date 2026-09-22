import Foundation

/// What a reconcile pass wants written (§4.5).
///
/// The engine is pure: it decides what should exist and the caller persists it.
public struct ReconcileOutcome: Equatable, Sendable {
    /// Occurrences to insert, in date order.
    public var newTransactions: [Transaction]
    /// Rules whose cursor or active flag changed.
    public var updatedRules: [RecurringRule]

    /// Whether the pass found nothing to do.
    public var isEmpty: Bool {
        newTransactions.isEmpty && updatedRules.isEmpty
    }

    /// Creates an outcome.
    /// - Parameters:
    ///   - newTransactions: Occurrences to insert.
    ///   - updatedRules: Rules whose state changed.
    public init(newTransactions: [Transaction] = [], updatedRules: [RecurringRule] = []) {
        self.newTransactions = newTransactions
        self.updatedRules = updatedRules
    }
}

/// Lazily generates recurring occurrences (§4.5).
///
/// **At any moment, exactly one unposted occurrence exists per active rule.** When it
/// posts, the next is generated on the following reconcile. Posting itself is
/// implicit via the clock — there is no state flag to flip, and posting is silent.
///
/// The rule's `occurrencesGenerated` is the cursor into its date sequence, not the
/// last occurrence's date. That distinction matters: deleting a single occurrence
/// must not cause the engine to regenerate it on the next pass.
public enum RecurringEngine {

    /// The most occurrences one pass will generate for a single rule.
    ///
    /// A long-dormant weekly rule could otherwise generate years of history in one
    /// go. Hitting the cap is not an error: the pass stops early and the next one
    /// continues from the same cursor.
    public static let catchUpLimit = 500

    /// Brings every active rule up to date.
    ///
    /// Runs on app foreground and after any rule edit. For each active rule it
    /// generates every missed occurrence in date order, then one future occurrence,
    /// and deactivates the rule once its end date or occurrence count is reached.
    ///
    /// - Parameters:
    ///   - rules: Every rule, active and inactive.
    ///   - existingTransactions: Transactions already in the store, used to spot
    ///     rules that already hold an unposted occurrence.
    ///   - now: The moment deciding what has posted.
    ///   - calendar: The calendar to compute occurrence dates in.
    /// - Returns: The occurrences to insert and the rules to update.
    public static func reconcile(
        rules: [RecurringRule],
        existingTransactions: [Transaction],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ReconcileOutcome {
        var outcome = ReconcileOutcome()
        let occurrencesByRule = Dictionary(
            grouping: existingTransactions.filter { $0.recurringRuleID != nil }
        ) { $0.recurringRuleID ?? UUID() }

        for rule in rules where rule.isActive {
            let existing = occurrencesByRule[rule.id] ?? []
            let result = advance(
                rule: rule, existing: existing, now: now, calendar: calendar
            )
            outcome.newTransactions.append(contentsOf: result.newTransactions)
            outcome.updatedRules.append(contentsOf: result.updatedRules)
        }
        outcome.newTransactions.sort { $0.date < $1.date }
        return outcome
    }

    /// Advances one rule to the point where it holds a single unposted occurrence.
    /// - Parameters:
    ///   - rule: The rule to advance.
    ///   - existing: That rule's occurrences already in the store.
    ///   - now: The moment deciding what has posted.
    ///   - calendar: The calendar to compute occurrence dates in.
    /// - Returns: What this rule wants written.
    private static func advance(
        rule: RecurringRule,
        existing: [Transaction],
        now: Date,
        calendar: Calendar
    ) -> ReconcileOutcome {
        // A rule that still holds an unposted occurrence is already up to date.
        guard !existing.contains(where: { $0.date > now }) else { return ReconcileOutcome() }

        var working = rule
        // Self-healing: trust whichever cursor is further along, in case a rule and
        // its occurrences ever disagree.
        var cursor = max(rule.occurrencesGenerated, existing.count)
        var generated: [Transaction] = []

        while generated.count < catchUpLimit {
            if let limit = working.occurrenceLimit, cursor >= limit {
                working.isActive = false
                break
            }
            guard let date = RecurringSchedule.date(
                atIndex: cursor, of: working, calendar: calendar
            ) else {
                working.isActive = false
                break
            }
            if let endDate = working.endDate, date > endDate {
                working.isActive = false
                break
            }

            generated.append(occurrence(of: working, on: date))
            cursor += 1

            // Stop as soon as one unposted occurrence exists.
            if date > now { break }
        }

        working.occurrencesGenerated = cursor
        guard !generated.isEmpty || working.isActive != rule.isActive else {
            return ReconcileOutcome()
        }
        return ReconcileOutcome(newTransactions: generated, updatedRules: [working])
    }

    /// Builds one occurrence from a rule.
    /// - Parameters:
    ///   - rule: The rule being generated from.
    ///   - date: When the occurrence falls.
    /// - Returns: The transaction to insert.
    public static func occurrence(of rule: RecurringRule, on date: Date) -> Transaction {
        Transaction(
            amountCents: rule.amountCents,
            type: rule.type,
            categoryID: rule.categoryID,
            accountID: rule.accountID,
            date: date,
            merchant: rule.name,
            recurringRuleID: rule.id
        )
    }
}
