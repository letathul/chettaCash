import Foundation
import Testing
@testable import Features
import Domain

/// Phase 4 acceptance criteria: an account can be created, edited, reordered and
/// closed, with closing blocked at a non-zero balance (§7.6, §7.9, §4.7).
@MainActor
@Suite("Settings and accounts")
struct SettingsViewModelTests {

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

    /// Adds an account through the shared form, as the UI does.
    /// - Parameters:
    ///   - model: The view model.
    ///   - name: The account name.
    ///   - balance: The typed opening balance.
    ///   - kind: Spending account or card.
    ///   - group: The owning group.
    /// - Returns: The saved account, if the form validated.
    @discardableResult
    private func addAccount(
        to model: SettingsViewModel,
        name: String,
        balance: String,
        kind: AccountKind = .account,
        group: Domain.AccountGroup
    ) async -> Domain.Account? {
        let form = AccountFormState(groupID: group.id)
        form.name = name
        form.kind = kind
        form.openingBalanceText = balance
        guard let account = form.commit(sortIndex: model.nextSortIndex(inGroup: group.id)) else {
            return nil
        }
        await model.save(account)
        return model.accounts.first { $0.id == account.id }
    }

    @Test("An account can be created")
    func createsAccount() async {
        let (harness, group) = await makeHarness()

        let saved = await addAccount(
            to: harness.model, name: "TD Chequing", balance: "1,000.00", group: group
        )

        #expect(saved?.name == "TD Chequing")
        #expect(saved?.openingBalanceCents == 100_000)
        #expect(saved?.cachedBalanceCents == 100_000)
        #expect(harness.model.netWorthCents == 100_000)
    }

    @Test("A card's opening balance is stored as money owed, whichever sign is typed")
    func normalizesCardOpeningBalance() async {
        let (harness, group) = await makeHarness()

        let saved = await addAccount(
            to: harness.model, name: "TD Visa", balance: "200.00", kind: .card, group: group
        )

        #expect(saved?.openingBalanceCents == -20_000)
        #expect(harness.model.netWorthCents == -20_000)
    }

    @Test("Save does nothing while a required field is missing")
    func validationBlocksSave() async {
        let (harness, group) = await makeHarness()
        let form = AccountFormState(groupID: group.id)
        form.openingBalanceText = "10.00"

        let committed = form.commit(sortIndex: 0)

        #expect(committed == nil)
        #expect(form.nameError == "Account name is required.")
        #expect(harness.model.accounts.isEmpty)
    }

    @Test("Validation stays hidden until Save is attempted")
    func validationIsHiddenBeforeSave() {
        let form = AccountFormState()
        #expect(form.nameError == nil)
        #expect(form.groupError == nil)
        #expect(form.openingBalanceError == nil)
    }

    @Test("An account without a group is refused, as a backstop behind the scoped sheet")
    func groupIsRequired() {
        let form = AccountFormState()
        form.name = "Orphan"
        form.openingBalanceText = "1.00"

        #expect(form.commit(sortIndex: 0) == nil)
        #expect(form.groupError == "Choose a group to continue.")
    }

    @Test("An account can be edited without changing its identity")
    func editsAccount() async {
        let (harness, group) = await makeHarness()
        guard let original = await addAccount(
            to: harness.model, name: "Chequing", balance: "50.00", group: group
        ) else { return }

        let form = AccountFormState(editing: original)
        form.name = "TD Chequing"
        form.openingBalanceText = "75.00"
        guard let edited = form.commit(sortIndex: original.sortIndex) else { return }
        await harness.model.save(edited)

        #expect(harness.model.accounts.count == 1)
        #expect(harness.model.accounts.first?.id == original.id)
        #expect(harness.model.accounts.first?.name == "TD Chequing")
        #expect(harness.model.accounts.first?.cachedBalanceCents == 7_500)
    }

    @Test("Accounts reorder within their group, and arrows disable at the boundaries")
    func reordersWithinGroup() async {
        let (harness, group) = await makeHarness()
        await addAccount(to: harness.model, name: "First", balance: "1.00", group: group)
        await addAccount(to: harness.model, name: "Second", balance: "2.00", group: group)
        await addAccount(to: harness.model, name: "Third", balance: "3.00", group: group)
        let model = harness.model
        #expect(model.accounts(in: group).map(\.name) == ["First", "Second", "Third"])

        guard let first = model.accounts(in: group).first else { return }
        #expect(model.canMove(first, by: -1) == false)
        #expect(model.canMove(first, by: 1))

        await model.move(first, by: 1)
        #expect(model.accounts(in: group).map(\.name) == ["Second", "First", "Third"])

        guard let last = model.accounts(in: group).last else { return }
        #expect(model.canMove(last, by: 1) == false)
    }

    @Test("Closing is blocked while the balance is non-zero")
    func closingBlockedAtNonZeroBalance() async {
        let (harness, group) = await makeHarness()
        guard let account = await addAccount(
            to: harness.model, name: "Chequing", balance: "120.00", group: group
        ) else { return }

        #expect(AccountLifecycle.blocker(for: account) == .holdsBalance(cents: 12_000))
        await harness.model.close(account)

        #expect(harness.model.accounts.first?.isClosed == false)
    }

    @Test("The offered transfer zeroes the account, which then closes")
    func zeroingTransferEnablesClose() async {
        let (harness, group) = await makeHarness()
        guard let closing = await addAccount(
            to: harness.model, name: "Old Savings", balance: "300.00", group: group
        ) else { return }
        guard let destination = await addAccount(
            to: harness.model, name: "Chequing", balance: "0.00", group: group
        ) else { return }
        let model = harness.model

        await model.createZeroingTransfer(for: closing, counterpartID: destination.id)

        let zeroed = model.accounts.first { $0.id == closing.id }
        #expect(zeroed?.cachedBalanceCents == 0)
        #expect(model.accounts.first { $0.id == destination.id }?.cachedBalanceCents == 30_000)

        if let zeroed {
            await model.close(zeroed)
        }
        #expect(model.accounts.first { $0.id == closing.id }?.isClosed == true)
        #expect(model.accounts.first { $0.id == closing.id }?.closedDate != nil)
    }

    @Test("A closed account leaves the pickers but stays in the list")
    func closedAccountLeavesPickers() async {
        let (harness, group) = await makeHarness()
        guard let account = await addAccount(
            to: harness.model, name: "Old", balance: "0.00", group: group
        ) else { return }
        // A second account keeps one open, so the §7.10 starter account stays out of
        // this: what is under test is the closed account, not the fallback.
        await addAccount(to: harness.model, name: "Everyday", balance: "0.00", group: group)
        let model = harness.model

        await model.close(account)

        #expect(model.accounts.count == 2)
        #expect(model.selectableAccounts.map(\.name) == ["Everyday"])
        #expect(model.netWorthCents == 0)
    }

    @Test("Reopening restores editability")
    func reopenRestoresAccount() async {
        let (harness, group) = await makeHarness()
        guard let account = await addAccount(
            to: harness.model, name: "Old", balance: "0.00", group: group
        ) else { return }
        let model = harness.model
        await model.close(account)

        guard let closed = model.accounts.first else { return }
        await model.reopen(closed)

        #expect(model.accounts.first?.isClosed == false)
        #expect(model.accounts.first?.closedDate == nil)
        #expect(model.selectableAccounts.count == 1)
    }

    @Test("An adjustment moves the balance to the stated figure")
    func adjustmentCorrectsBalance() async {
        let (harness, group) = await makeHarness()
        guard let account = await addAccount(
            to: harness.model, name: "Chequing", balance: "100.00", group: group
        ) else { return }

        await harness.model.recordAdjustment(
            for: account, targetCents: 9_250, date: .now.addingTimeInterval(-60)
        )

        #expect(harness.model.accounts.first?.cachedBalanceCents == 9_250)
    }

    @Test("Group subtotals cover only that group's open accounts")
    func groupSubtotals() async {
        let (harness, group) = await makeHarness()
        let other = Domain.AccountGroup(name: "Savings", sortIndex: 1)
        await harness.model.addGroup(named: other.name)
        await addAccount(to: harness.model, name: "A", balance: "10.00", group: group)
        await addAccount(to: harness.model, name: "B", balance: "25.00", group: group)

        #expect(harness.model.subtotalCents(for: group) == 3_500)
        #expect(harness.model.netWorthCents == 3_500)
    }

    @Test("A failed load surfaces a retryable banner rather than empty content")
    func loadFailureShowsBanner() async {
        let (harness, _) = await makeHarness()
        harness.accounts.failure = URLError(.notConnectedToInternet)

        await harness.model.load()

        #expect(harness.model.errorMessage == "Could not load your accounts.")
    }

    @Test("Changing a preference persists it")
    func preferencesPersist() async {
        let (harness, _) = await makeHarness()

        harness.model.settings.currencyCode = "GBP"
        harness.model.persistSettings()

        #expect(harness.settingsStore.saveCount == 1)
    }
}
