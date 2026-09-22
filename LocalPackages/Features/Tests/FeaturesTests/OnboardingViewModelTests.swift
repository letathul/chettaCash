import Foundation
import Testing
@testable import Features
import Domain

/// Phase 10 acceptance criteria: the flow runs once, both skip paths land correctly,
/// and several accounts can be added in one pass (§7.10).
@MainActor
@Suite("Onboarding")
struct OnboardingViewModelTests {

    /// The pieces under test, wired together.
    private struct Harness {
        /// The account repository fake.
        let accounts: FakeAccountRepository
        /// The notification authorizer fake.
        let notifications: FakeNotificationAuthorizer
        /// The settings store fake.
        let settingsStore: FakeSettingsStore
        /// The shared preferences object.
        let settings: AppSettings
        /// The view model under test.
        let model: OnboardingViewModel
    }

    /// Builds a loaded view model with one group already present.
    /// - Parameter withGroup: Whether to seed a group.
    /// - Returns: The harness and the seeded group, if any.
    private func makeHarness(withGroup: Bool = true) async -> (Harness, Domain.AccountGroup?) {
        let accounts = FakeAccountRepository()
        let notifications = FakeNotificationAuthorizer()
        let settingsStore = FakeSettingsStore()
        let settings = AppSettings()
        var group: Domain.AccountGroup?
        if withGroup {
            let seeded = Domain.AccountGroup(name: "Everyday")
            try? await accounts.save(seeded)
            group = seeded
        }
        let model = OnboardingViewModel(
            accountRepository: accounts,
            notifications: notifications,
            settingsStore: settingsStore,
            settings: settings
        )
        await model.load()
        return (
            Harness(
                accounts: accounts, notifications: notifications,
                settingsStore: settingsStore, settings: settings, model: model
            ),
            group
        )
    }

    /// Adds an account through the shared form, as the step does.
    /// - Parameters:
    ///   - harness: The harness under test.
    ///   - name: The account name.
    ///   - balance: The typed opening balance.
    ///   - kind: Spending account or card.
    ///   - group: The owning group.
    /// - Returns: Whether it saved.
    @discardableResult
    private func addAccount(
        _ harness: Harness,
        name: String,
        balance: String,
        kind: AccountKind = .account,
        group: Domain.AccountGroup?
    ) async -> Bool {
        let form = AccountFormState(groupID: group?.id)
        form.name = name
        form.kind = kind
        form.openingBalanceText = balance
        guard let account = form.commit(
            sortIndex: harness.model.nextSortIndex(inGroup: group?.id)
        ) else { return false }
        return await harness.model.add(account)
    }

    // MARK: - Step order and completion

    @Test("The flow starts at Welcome and advances one step at a time")
    func stepOrder() async {
        let (harness, _) = await makeHarness()

        #expect(harness.model.step == .welcome)
        harness.model.advance()
        #expect(harness.model.step == .accounts)
        harness.model.advance()
        #expect(harness.model.step == .notifications)
        harness.model.advance()
        #expect(harness.model.step == .notifications, "there is no fourth step")
    }

    @Test("Finishing marks onboarding done and persists it, so it runs once")
    func finishPersistsFlag() async {
        let (harness, _) = await makeHarness()
        #expect(harness.settings.hasCompletedOnboarding == false)

        harness.model.finish()

        #expect(harness.settings.hasCompletedOnboarding)
        #expect(harness.settingsStore.saveCount == 1)
    }

    // MARK: - Several accounts in one pass (§7.10)

    @Test("Continue stays disabled until an account exists, and says why")
    func continueDisabledUntilAccountAdded() async {
        let (harness, group) = await makeHarness()

        #expect(harness.model.hasAnyAccount == false)
        #expect(harness.model.continueTitle == "Add an account to continue")

        await addAccount(harness, name: "Chequing", balance: "100.00", group: group)

        #expect(harness.model.hasAnyAccount)
        #expect(harness.model.continueTitle == "Continue")
    }

    @Test("Several accounts can be added in one pass, in order")
    func severalAccountsInOnePass() async {
        let (harness, group) = await makeHarness()

        await addAccount(harness, name: "Chequing", balance: "1000.00", group: group)
        await addAccount(harness, name: "Savings", balance: "5000.00", group: group)
        await addAccount(harness, name: "Visa", balance: "200.00", kind: .card, group: group)

        #expect(harness.model.addedAccounts.map(\.name) == ["Chequing", "Savings", "Visa"])
        let stored = try? await harness.accounts.accounts(includeClosed: true)
        #expect(stored?.count == 3)
    }

    @Test("Each added account keeps its derived balance for the just-added list")
    func addedAccountsCarryBalances() async {
        let (harness, group) = await makeHarness()

        await addAccount(harness, name: "Chequing", balance: "1,250.00", group: group)

        #expect(harness.model.addedAccounts.first?.cachedBalanceCents == 125_000)
    }

    @Test("A card added during onboarding is stored as money owed")
    func cardOpeningBalanceIsNormalized() async {
        let (harness, group) = await makeHarness()

        await addAccount(harness, name: "Visa", balance: "200.00", kind: .card, group: group)

        #expect(harness.model.addedAccounts.first?.openingBalanceCents == -20_000)
    }

    @Test("Validation refuses an incomplete account without adding it")
    func validationRefusesIncompleteAccount() async {
        let (harness, group) = await makeHarness()
        let form = AccountFormState(groupID: group?.id)
        form.openingBalanceText = "10.00"
        // It is the missing *name* that blocks this, not the balance: a balance now
        // defaults to 0.00 and a blank one is valid.
        form.name = ""

        #expect(form.commit(sortIndex: 0) == nil)
        #expect(harness.model.addedAccounts.isEmpty)
    }

    @Test("A group can be created from the group page, and is returned to scope the sheet")
    func groupCanBeCreatedInline() async {
        let (harness, _) = await makeHarness(withGroup: false)
        #expect(harness.model.groups.isEmpty)

        let created = await harness.model.addGroup(named: "Everyday")

        #expect(created?.name == "Everyday")
        #expect(harness.model.groups.map(\.name) == ["Everyday"])
    }

    // MARK: - Skip paths (§7.10)

    @Test("Skipping accounts still leaves a usable Cash account, not an empty app")
    func skipAccountsLeavesStarter() async {
        let (harness, _) = await makeHarness()
        harness.model.advance()

        // "Skip for now" moves on without adding anything.
        harness.model.advance()
        await harness.model.ensureStarterAccount()
        harness.model.finish()

        #expect(harness.model.addedAccounts.isEmpty, "the user added nothing themselves")
        #expect(harness.settings.hasCompletedOnboarding)
        let stored = try? await harness.accounts.accounts(includeClosed: true)
        #expect(stored?.map(\.name) == ["Cash"])
        #expect(harness.settings.showsStarterAccountNote, "and the Dashboard says so")
    }

    @Test("A user who added their own account is not given a starter as well")
    func starterIsSkippedWhenAccountsExist() async {
        let (harness, group) = await makeHarness()
        await addAccount(harness, name: "Chequing", balance: "100.00", group: group)

        await harness.model.ensureStarterAccount()

        let stored = try? await harness.accounts.accounts(includeClosed: true)
        #expect(stored?.map(\.name) == ["Chequing"])
        #expect(harness.settings.showsStarterAccountNote == false)
    }

    @Test("Maybe later finishes without ever prompting")
    func maybeLaterNeverPrompts() async {
        let (harness, _) = await makeHarness()

        harness.model.finish()

        #expect(harness.notifications.requestCount == 0)
        #expect(harness.model.notificationsAuthorized == false)
        #expect(harness.settings.hasCompletedOnboarding)
    }

    // MARK: - Notifications (§7.10 step 3)

    @Test("Enabling notifications triggers the real prompt once")
    func enablingRequestsPermission() async {
        let (harness, _) = await makeHarness()

        await harness.model.requestNotifications()

        #expect(harness.notifications.requestCount == 1)
        #expect(harness.model.notificationsAuthorized)
    }

    @Test("A refused prompt ends in the same state as never asking")
    func refusedPromptMatchesSkip() async {
        let (harness, _) = await makeHarness()
        harness.notifications.grants = false

        await harness.model.requestNotifications()
        harness.model.finish()

        #expect(harness.model.notificationsAuthorized == false)
        #expect(harness.settings.hasCompletedOnboarding)
    }

    @Test("An already-granted permission is reflected without re-prompting")
    func existingPermissionIsReflected() async {
        let accounts = FakeAccountRepository()
        let notifications = FakeNotificationAuthorizer()
        notifications.status = .authorized
        let model = OnboardingViewModel(
            accountRepository: accounts,
            notifications: notifications,
            settingsStore: FakeSettingsStore(),
            settings: AppSettings()
        )

        await model.load()

        #expect(model.notificationsAuthorized)
        #expect(notifications.requestCount == 0)
    }
}
