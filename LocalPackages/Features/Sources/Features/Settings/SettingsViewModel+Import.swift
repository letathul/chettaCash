import Foundation
import Domain

/// Statement import, hung off the Settings screen (§4.2).
///
/// Split from ``SettingsViewModel`` to keep each file within the 300-line limit.
extension SettingsViewModel {

    /// Whether the Import statement card can be shown.
    ///
    /// Two conditions, both required. The repository check mirrors ``canMapMerchants``:
    /// the card appears only when the app wired what it needs, so the test previews that
    /// omit them show no card. The flag check is the newer half — statement import is
    /// still under development, so it is off until someone turns it on in the
    /// feature-flag menu. A flag on its own can never surface a card that cannot work.
    ///
    /// Gating here gates the whole feature: ``StatementImportCard`` owns the document
    /// picker, the review screen and the summary sheet, so all three go with the card.
    public var canImportStatements: Bool {
        statementImport != nil && settings.isEnabled(.statementScanner)
    }

    /// How many rows from the last import are still waiting to be reviewed.
    public var pendingReviewCount: Int { pendingImport?.reviewDrafts.count ?? 0 }

    /// The import screen's state, created once and kept.
    ///
    /// **Kept rather than rebuilt per presentation.** The unapproved review lives on this
    /// model, so constructing a fresh one each time the screen opened would lose exactly the
    /// state the "Finish reviewing" row exists to preserve — and, because nothing is written
    /// until the user approves, losing it would lose the whole import.
    ///
    /// - Returns: The model, or `nil` when the app did not wire statement import.
    public func makeStatementImportModel() -> StatementImportViewModel? {
        if let pendingImport { return pendingImport }
        guard let statementImport else { return nil }
        let model = StatementImportViewModel(coordinator: statementImport, settings: settings)
        pendingImport = model
        return model
    }
}
