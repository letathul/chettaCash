import Foundation
import Domain

/// The account close, reopen and balance-correction flows (§4.7, §4.4).
///
/// Split from ``SettingsViewModel`` so that file stays under the 300-line limit.
@MainActor
extension SettingsViewModel {

    /// Closes an account once its balance is zero.
    ///
    /// Callers must check ``AccountLifecycle/blocker(for:)`` first and offer the
    /// zeroing transfer; this refuses rather than closing a non-zero account.
    ///
    /// - Parameter account: The account to close.
    public func close(_ account: Domain.Account) async {
        guard AccountLifecycle.blocker(for: account) == nil else { return }
        await perform("Could not close that account.") {
            try await self.accountRepository.save(AccountLifecycle.closed(account))
        }
        // Closing the last open account would otherwise leave nowhere to record
        // anything. The coordinator no-ops while any open account remains (§7.10).
        guard errorMessage == nil, selectableAccounts.isEmpty else { return }
        let created = await StarterAccountCoordinator(
            accounts: accountRepository, settings: settings, settingsStore: settingsStore
        ).ensureUsableAccount()
        if created { await load() }
    }

    /// Reopens a closed account, restoring editability.
    /// - Parameter account: The account to reopen.
    public func reopen(_ account: Domain.Account) async {
        await perform("Could not reopen that account.") {
            try await self.accountRepository.save(AccountLifecycle.reopened(account))
        }
    }

    /// Creates the transfer that zeroes an account so it can be closed (§4.7).
    /// - Parameters:
    ///   - account: The account being zeroed.
    ///   - counterpartID: The other account taking or supplying the money.
    public func createZeroingTransfer(
        for account: Domain.Account,
        counterpartID: UUID
    ) async {
        await perform("Could not create that transfer.") {
            let legs = try AccountLifecycle.zeroingTransfer(
                for: account, counterpartID: counterpartID
            )
            try await self.transactionRepository.saveTransfer(outLeg: legs.out, inLeg: legs.in)
        }
    }

    /// Records a dated balance correction (§4.4).
    ///
    /// The adjustment affects balances and Net Worth but never spend or income
    /// totals — a correction is not spending.
    ///
    /// - Parameters:
    ///   - account: The account being corrected.
    ///   - targetCents: The balance the user says is correct.
    ///   - date: When the correction takes effect.
    public func recordAdjustment(
        for account: Domain.Account,
        targetCents: Int,
        date: Date
    ) async {
        let difference = targetCents - account.cachedBalanceCents
        guard difference != 0 else { return }
        await perform("Could not record that adjustment.") {
            let correction = AdjustmentFactory.make(
                accountID: account.id,
                signedCents: difference,
                date: date,
                memo: "Balance correction"
            )
            try await self.transactionRepository.save(correction)
        }
    }

}
