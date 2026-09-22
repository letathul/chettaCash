import Foundation
import Testing
@testable import Features
import Domain

/// Group creation, renaming, and the §7.10 starter account, split from
/// ``SettingsViewModelTests`` to keep both files inside the 300-line limit.
@MainActor
@Suite("Settings groups and starter account")
struct SettingsGroupTests {

    /// The pieces under test, wired together.
    private struct Harness {
        /// The account repository fake.
        let accounts: FakeAccountRepository
        /// The settings store fake.
        let settingsStore: FakeSettingsStore
        /// The view model under test.
        let model: SettingsViewModel
    }

    /// Builds a loaded view model with one group.
    /// - Returns: The harness and the seeded group.
    private func makeHarness() async -> (Harness, Domain.AccountGroup) {
        let accounts = FakeAccountRepository()
        let transactions = FakeTransactionRepository(accounts: accounts)
        let settingsStore = FakeSettingsStore()
        let model = SettingsViewModel(
            accountRepository: accounts,
            transactionRepository: transactions,
            settingsStore: settingsStore,
            settings: AppSettings()
        )
        let group = Domain.AccountGroup(name: "Everyday")
        try? await accounts.save(group)
        await model.load()
        return (Harness(accounts: accounts, settingsStore: settingsStore, model: model), group)
    }

    /// Adds an account through the shared form, as the add sheet does.
    /// - Parameters:
    ///   - model: The view model.
    ///   - name: The account name.
    ///   - balance: The typed opening balance.
    ///   - group: The owning group.
    /// - Returns: The saved account, if the form validated.
    @discardableResult
    private func addAccount(
        to model: SettingsViewModel,
        name: String,
        balance: String,
        group: Domain.AccountGroup
    ) async -> Domain.Account? {
        let form = AccountFormState(groupID: group.id)
        form.name = name
        form.openingBalanceText = balance
        guard let account = form.commit(sortIndex: model.nextSortIndex(inGroup: group.id)) else {
            return nil
        }
        await model.save(account)
        return model.accounts.first { $0.id == account.id }
    }

    @Test("A blank opening balance saves as zero rather than blocking")
    func blankOpeningBalanceIsZero() {
        let form = AccountFormState(groupID: UUID())
        form.name = "Wallet"
        form.openingBalanceText = ""

        let account = form.commit(sortIndex: 0)

        #expect(account?.openingBalanceCents == 0)
        #expect(form.openingBalanceError == nil)
    }

    @Test("A typo in the opening balance still blocks Save")
    func unparseableOpeningBalanceBlocks() {
        let form = AccountFormState(groupID: UUID())
        form.name = "Wallet"
        form.openingBalanceText = "abc"

        #expect(form.commit(sortIndex: 0) == nil)
        #expect(form.openingBalanceError == "Enter an amount like 0.00.")
    }

    @Test("Creating a group returns it, so the add-account sheet can be scoped to it")
    func addGroupReturnsTheGroup() async {
        let (harness, _) = await makeHarness()

        let created = await harness.model.addGroup(named: "HDFC")

        #expect(created?.name == "HDFC")
        let ids = harness.model.groups.map(\.id)
        #expect(ids.contains(created?.id ?? UUID()))
    }

    @Test("A group can be renamed without disturbing its accounts")
    func renamesGroup() async {
        let (harness, group) = await makeHarness()
        await addAccount(to: harness.model, name: "Chequing", balance: "50.00", group: group)

        await harness.model.rename(group, to: "Everyday spending")

        #expect(harness.model.groups.map(\.name) == ["Everyday spending"])
        #expect(harness.model.groups.first?.id == group.id)
        #expect(harness.model.accounts(in: group).map(\.name) == ["Chequing"])
    }

    @Test("Closing the last open account leaves a Cash account behind")
    func closingLastAccountLeavesStarter() async {
        let (harness, group) = await makeHarness()
        let account = await addAccount(
            to: harness.model, name: "Chequing", balance: "0.00", group: group
        )
        guard let account else {
            Issue.record("the account should have saved")
            return
        }

        await harness.model.close(account)

        #expect(harness.model.selectableAccounts.map(\.name) == ["Cash"])
        #expect(harness.model.settings.showsStarterAccountNote)
    }
}
