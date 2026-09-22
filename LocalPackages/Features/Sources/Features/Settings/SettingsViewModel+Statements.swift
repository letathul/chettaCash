import Foundation
import Domain

/// The Settings view model's card-statement actions (§4.6).
///
/// Split from ``SettingsViewModel`` to keep each file within the 300-line limit.
extension SettingsViewModel {

    /// Generates missing statements and allocates payments for one card.
    ///
    /// Takes the account directly rather than reading the loaded list, so a screen
    /// that opens straight onto a card does not depend on the list having loaded.
    ///
    /// - Parameter account: The card to reconcile.
    public func reconcileStatements(for account: Domain.Account) async {
        guard let coordinator = statements, account.kind == .card, !account.isClosed else {
            return
        }
        do {
            try await coordinator.reconcile(account: account)
        } catch {
            errorMessage = "Could not update your card statements."
        }
    }

    /// Generates missing statements and allocates payments for every open card.
    public func reconcileStatements() async {
        for account in accounts where account.kind == .card && !account.isClosed {
            await reconcileStatements(for: account)
        }
    }

    /// Loads display-ready statement summaries for one card.
    /// - Parameter account: The card to summarise.
    /// - Returns: Its statements, newest first.
    public func statementSummaries(for account: Domain.Account) async -> [StatementSummary] {
        guard let coordinator = statements else { return [] }
        do {
            return try await coordinator.summaries(for: account)
        } catch {
            errorMessage = "Could not load that card's statements."
            return []
        }
    }

    /// Records or dismisses the interest-and-fees prompt (§4.6).
    /// - Parameters:
    ///   - statement: The statement being resolved.
    ///   - cents: The amount charged, or `nil` to dismiss.
    public func resolveInterestPrompt(
        for statement: Domain.CardStatement,
        cents: Int?
    ) async {
        guard let coordinator = statements else { return }
        do {
            try await coordinator.resolveInterestPrompt(
                for: statement, cents: cents, billsCategoryID: billsCategoryID
            )
            await load()
        } catch {
            errorMessage = "Could not record that charge."
        }
    }

    /// Overrides a statement balance when the real statement differs (§4.6).
    /// - Parameters:
    ///   - statement: The statement to override.
    ///   - cents: The real figure, or `nil` to fall back to the computed one.
    public func overrideStatementBalance(
        _ statement: Domain.CardStatement,
        cents: Int?
    ) async {
        guard let coordinator = statements else { return }
        do {
            try await coordinator.setOverride(on: statement, cents: cents)
            await load()
        } catch {
            errorMessage = "Could not save that statement balance."
        }
    }
}
