import Foundation
import Testing
@testable import Features
import Domain

/// The feature-flag menu and the gate it drives (§7.6).
@MainActor
@Suite("Feature flags")
struct FeatureFlagTests {

    /// Builds a Settings model over a recording settings store.
    /// - Parameters:
    ///   - settings: The preferences the model shares.
    ///   - withCategories: Whether to wire the repository statement import needs.
    ///   - showsFeatureFlags: Whether this build may offer the menu.
    /// - Returns: The model and its store.
    private func makeModel(
        settings: AppSettings = AppSettings(),
        withCategories: Bool = true,
        showsFeatureFlags: Bool = false
    ) -> (model: SettingsViewModel, store: FakeSettingsStore) {
        let accounts = FakeAccountRepository()
        let store = FakeSettingsStore()
        let model = SettingsViewModel(
            accountRepository: accounts,
            transactionRepository: FakeTransactionRepository(accounts: accounts),
            settingsStore: store,
            settings: settings,
            categoryRepository: withCategories ? FakeCategoryRepository() : nil,
            showsFeatureFlags: showsFeatureFlags
        )
        return (model, store)
    }

    @Test("Every flag starts off")
    func flagsDefaultToOff() {
        let settings = AppSettings()
        for flag in FeatureFlag.allCases {
            #expect(settings.isEnabled(flag) == false)
        }
    }

    @Test("The statement scanner is hidden until its flag is switched on")
    func theScannerIsOffByDefault() {
        // The repositories are wired, so only the flag can be keeping the card away.
        #expect(makeModel().model.canImportStatements == false)
    }

    @Test("The flag alone does not surface a card that cannot work")
    func theFlagDoesNotReplaceTheDependencyCheck() {
        let settings = AppSettings()
        settings.setFeature(.statementScanner, enabled: true)
        let flagged = makeModel(settings: settings, withCategories: false)
        #expect(flagged.model.canImportStatements == false)
    }

    @Test("The card appears once the flag and the repositories agree")
    func bothHalvesTogetherShowTheCard() {
        let settings = AppSettings()
        settings.setFeature(.statementScanner, enabled: true)
        #expect(makeModel(settings: settings).model.canImportStatements)
    }

    @Test("Flipping a flag persists it immediately")
    func switchingAFlagSaves() {
        let (model, store) = makeModel()
        model.setFeature(.statementScanner, enabled: true)
        #expect(model.isEnabled(.statementScanner))
        #expect(store.saveCount == 1)

        model.setFeature(.statementScanner, enabled: false)
        #expect(model.isEnabled(.statementScanner) == false)
        #expect(store.saveCount == 2)
    }

    @Test("The menu is hidden unless the app says this build may show it")
    func theMenuIsGatedOnTheBuild() {
        #expect(makeModel().model.showsFeatureFlags == false)
        #expect(makeModel(showsFeatureFlags: true).model.showsFeatureFlags)
    }

    @Test("The menu offers every flag, in a stable order")
    func theMenuListsEveryFlag() {
        let flags = makeModel().model.featureFlags
        #expect(Set(flags) == Set(FeatureFlag.allCases))
        #expect(flags == FeatureFlag.menuOrder)
        #expect(flags == flags.sorted { $0.title < $1.title })
    }
}
