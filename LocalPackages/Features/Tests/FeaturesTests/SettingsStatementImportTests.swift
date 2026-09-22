import Foundation
import Testing
@testable import Features
import Domain

/// The Settings screen's side of statement import (§7.6).
@MainActor
@Suite("Settings statement import")
struct SettingsStatementImportTests {

    /// Builds a Settings model, optionally without the repositories import needs.
    ///
    /// The scanner flag is on by default here so the suite keeps testing the dependency
    /// half of the gate; ``FeatureFlagTests`` covers the flag half.
    ///
    /// - Parameters:
    ///   - withCategories: Whether to wire the category repository.
    ///   - flagEnabled: Whether the statement-scanner flag is switched on.
    /// - Returns: The model.
    private func makeModel(
        withCategories: Bool = true,
        flagEnabled: Bool = true
    ) -> SettingsViewModel {
        let accounts = FakeAccountRepository()
        let settings = AppSettings()
        settings.setFeature(.statementScanner, enabled: flagEnabled)
        return SettingsViewModel(
            accountRepository: accounts,
            transactionRepository: FakeTransactionRepository(accounts: accounts),
            settingsStore: FakeSettingsStore(),
            settings: settings,
            categoryRepository: withCategories ? FakeCategoryRepository() : nil
        )
    }

    @Test("The import card appears only when the app wires what it needs")
    func cardIsGatedOnItsDependencies() {
        // Mirrors `canMapMerchants`: the previews used by tests omit the repositories, and
        // must show no card rather than a card that cannot work.
        #expect(makeModel().canImportStatements)
        #expect(makeModel(withCategories: false).canImportStatements == false)
    }

    @Test("Without the repositories no import model is built")
    func noModelWithoutDependencies() {
        #expect(makeModel(withCategories: false).makeStatementImportModel() == nil)
    }

    @Test("Reopening the import returns the same model, so an unapproved review survives")
    func theImportModelIsKept() {
        // The whole basis of the "Resolve Duplicates" button: the unresolved conflicts
        // live on this model, so rebuilding it per presentation would discard exactly the
        // state the button exists to preserve.
        let model = makeModel()

        let first = model.makeStatementImportModel()
        let second = model.makeStatementImportModel()

        #expect(first != nil)
        #expect(first === second)
        #expect(model.pendingImport === first)
    }

    @Test("With no import run there is nothing pending")
    func nothingPendingBeforeAnImport() {
        let model = makeModel()

        #expect(model.pendingReviewCount == 0)
        #expect(model.pendingImport?.hasPendingReview != true)
    }
}
