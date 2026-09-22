import Foundation
import Testing
@testable import Features
import Domain

/// The safety net that keeps at least one usable account in the app (§7.10).
@MainActor
@Suite("Starter account coordinator")
struct StarterAccountCoordinatorTests {

    /// The pieces under test, wired together.
    private struct Harness {
        /// The account repository fake.
        let accounts: FakeAccountRepository
        /// The settings store fake.
        let settingsStore: FakeSettingsStore
        /// The shared preferences object.
        let settings: AppSettings
        /// The coordinator under test.
        let coordinator: StarterAccountCoordinator
    }

    /// Builds a coordinator over empty fakes.
    /// - Returns: The harness.
    private func makeHarness() -> Harness {
        let accounts = FakeAccountRepository()
        let settingsStore = FakeSettingsStore()
        let settings = AppSettings()
        return Harness(
            accounts: accounts,
            settingsStore: settingsStore,
            settings: settings,
            coordinator: StarterAccountCoordinator(
                accounts: accounts, settings: settings, settingsStore: settingsStore
            )
        )
    }

    @Test("An empty app gains one Cash account and is told about it")
    func createsStarterAndSetsNote() async {
        let harness = makeHarness()

        let created = await harness.coordinator.ensureUsableAccount()

        #expect(created)
        let stored = try? await harness.accounts.accounts(includeClosed: true)
        #expect(stored?.map(\.name) == ["Cash"])
        #expect(harness.settings.showsStarterAccountNote)
        #expect(harness.settingsStore.saveCount == 1)
    }

    @Test("Running twice creates the account once, so foregrounding is safe")
    func isIdempotentAcrossCalls() async {
        let harness = makeHarness()

        await harness.coordinator.ensureUsableAccount()
        let secondRun = await harness.coordinator.ensureUsableAccount()

        #expect(secondRun == false)
        let stored = try? await harness.accounts.accounts(includeClosed: true)
        #expect(stored?.count == 1)
        let groups = try? await harness.accounts.groups()
        #expect(groups?.count == 1, "no second Cash group is minted")
        #expect(harness.settingsStore.saveCount == 1)
    }

    @Test("A user who has their own account is left alone, note included")
    func noOpWhenAnOpenAccountExists() async {
        let harness = makeHarness()
        try? await harness.accounts.save(Domain.Account(name: "Chequing"))

        let created = await harness.coordinator.ensureUsableAccount()

        #expect(created == false)
        let stored = try? await harness.accounts.accounts(includeClosed: true)
        #expect(stored?.map(\.name) == ["Chequing"])
        #expect(harness.settings.showsStarterAccountNote == false)
        #expect(harness.settingsStore.saveCount == 0)
    }

    @Test("Closing the last account leaves a fresh Cash account behind")
    func createsStarterWhenEveryAccountIsClosed() async {
        let harness = makeHarness()
        try? await harness.accounts.save(
            AccountLifecycle.closed(Domain.Account(name: "Old Chequing"))
        )

        let created = await harness.coordinator.ensureUsableAccount()

        #expect(created)
        let open = try? await harness.accounts.accounts(includeClosed: false)
        #expect(open?.map(\.name) == ["Cash"])
    }

    @Test("A failing repository is survived quietly, since this never blocks a flow")
    func survivesRepositoryFailure() async {
        let harness = makeHarness()
        harness.accounts.failure = URLError(.badServerResponse)

        let created = await harness.coordinator.ensureUsableAccount()

        #expect(created == false)
        #expect(harness.settings.showsStarterAccountNote == false)
    }
}
