import Foundation
import Testing
import Domain
@testable import Data

/// How preferences survive a relaunch, feature flags in particular (§5.1, §7.6).
///
/// Every test writes to its own suite-named `UserDefaults` and removes it afterwards, so
/// nothing leaks into `.standard` or into the next test.
@MainActor
@Suite("App settings store")
struct AppSettingsStoreTests {

    /// Runs a body against a throwaway defaults domain.
    /// - Parameter body: What to run, given a store over the domain.
    private func withStore(_ body: (UserDefaultsAppSettingsStore) -> Void) {
        let name = "AppSettingsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            Issue.record("Could not open a throwaway defaults domain.")
            return
        }
        defer { defaults.removePersistentDomain(forName: name) }
        body(UserDefaultsAppSettingsStore(defaults: defaults))
    }

    @Test("A switched-on feature flag survives a relaunch")
    func flagsRoundTrip() {
        withStore { store in
            let saved = AppSettings()
            saved.setFeature(.statementScanner, enabled: true)
            store.save(saved)

            let loaded = AppSettings()
            store.load(into: loaded)

            #expect(loaded.enabledFeatureFlags == saved.enabledFeatureFlags)
            #expect(loaded.isEnabled(.statementScanner))
        }
    }

    @Test("Switching a flag back off is stored, not just forgotten")
    func switchingOffRoundTrips() {
        withStore { store in
            let saved = AppSettings()
            saved.setFeature(.statementScanner, enabled: true)
            store.save(saved)
            saved.setFeature(.statementScanner, enabled: false)
            store.save(saved)

            let loaded = AppSettings()
            store.load(into: loaded)

            #expect(loaded.isEnabled(.statementScanner) == false)
        }
    }

    @Test("A store that has never been written leaves the defaults alone")
    func anUnwrittenKeyKeepsTheDefaults() {
        withStore { store in
            let loaded = AppSettings()
            store.load(into: loaded)

            let expected = Set(FeatureFlag.allCases.filter(\.isEnabledByDefault))
            #expect(loaded.enabledFeatureFlags == expected)
        }
    }

    @Test("A flag a later build no longer knows about is dropped on load")
    func unknownFlagsAreDropped() {
        let name = "AppSettingsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            Issue.record("Could not open a throwaway defaults domain.")
            return
        }
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(
            ["statementScanner", "aFlagThatWasRetired"],
            forKey: "settings.enabledFeatureFlags"
        )

        let loaded = AppSettings()
        UserDefaultsAppSettingsStore(defaults: defaults).load(into: loaded)

        #expect(loaded.enabledFeatureFlags == [.statementScanner])
    }
}
