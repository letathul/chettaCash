import Foundation
import Domain

/// The Ledger view model's recurring-series actions (§4.5).
///
/// Split from ``LedgerViewModel`` to keep each file within the 300-line limit.
extension LedgerViewModel {
    /// Brings every active rule up to date, then reloads (§4.5).
    ///
    /// Runs on app foreground and after any rule edit. Posting is silent: the
    /// occurrences simply appear and balances update.
    public func reconcileRecurring() async {
        do {
            let generated = try await recurring.reconcile()
            if generated > 0 { await load() }
        } catch {
            errorMessage = "Could not update your recurring transactions."
        }
    }

    /// The rule a row belongs to, if it came from a series and is not detached.
    /// - Parameter transaction: The row's transaction.
    /// - Returns: The rule, or `nil` for a one-off or an overridden occurrence.
    public func seriesRule(for transaction: Domain.Transaction) -> Domain.RecurringRule? {
        guard let ruleID = transaction.recurringRuleID, !transaction.isSeriesOverride else {
            return nil
        }
        return recurringRules.first { $0.id == ruleID }
    }

    /// Applies a scoped edit to a series (§4.5).
    /// - Parameters:
    ///   - form: The form carrying the user's new values.
    ///   - rule: The rule the target belongs to.
    ///   - target: The occurrence the user opened.
    ///   - scope: How far the edit reaches.
    /// - Returns: `true` when the form validated and the edit was applied.
    @discardableResult
    public func applySeriesEdit(
        _ form: TransactionFormState,
        rule: Domain.RecurringRule,
        target: Domain.Transaction,
        scope: SeriesScope
    ) async -> Bool {
        guard form.attemptSave(), let edited = form.commitSingle() else { return false }
        do {
            try await recurring.applyEdit(
                rule: rule, target: target, scope: scope, edited: edited
            )
            await load()
            return true
        } catch {
            errorMessage = "Could not update that series."
            return false
        }
    }

    /// Applies a scoped delete to a series (§4.5).
    /// - Parameters:
    ///   - rule: The rule the target belongs to.
    ///   - target: The occurrence the user opened.
    ///   - scope: How far the delete reaches.
    public func applySeriesDelete(
        rule: Domain.RecurringRule,
        target: Domain.Transaction,
        scope: SeriesScope
    ) async {
        do {
            try await recurring.applyDelete(rule: rule, target: target, scope: scope)
            await load()
        } catch {
            errorMessage = "Could not delete that series."
        }
    }
}
