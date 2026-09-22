import SwiftUI
import Domain

/// The close-account flow (§4.7).
///
/// Closing is blocked while the balance is non-zero. Rather than just refusing, the
/// sheet offers to pre-fill the transfer that zeroes the account — moving cash out,
/// or paying the card off.
struct CloseAccountSheet: View {
    /// The account being closed.
    let account: Domain.Account
    /// The screen's view model.
    let model: SettingsViewModel
    /// Called after a successful close, so the Edit sheet can dismiss too.
    let onClosed: () -> Void

    /// Dismisses this sheet.
    @Environment(\.dismiss) private var dismiss
    /// The account chosen to take or supply the money.
    @State private var counterpartID: UUID?
    /// Whether the confirmation alert is showing (§7.11).
    @State private var isConfirming = false

    /// What is stopping the close, if anything.
    private var blocker: CloseBlocker? { AccountLifecycle.blocker(for: account) }

    /// Accounts that can take or supply the money.
    private var counterparts: [Domain.Account] {
        model.selectableAccounts.filter { $0.id != account.id }
    }

    /// The view body.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let blocker {
                        blockedContent(blocker)
                    } else {
                        readyContent
                    }
                }
                .padding(16)
            }
            .background(Palette.appBackground)
            .navigationTitle("Close Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Close \(account.name)?", isPresented: $isConfirming) {
                Button("Cancel", role: .cancel) {}
                Button("Close account", role: .destructive) {
                    Task {
                        await model.close(account)
                        dismiss()
                        onClosed()
                    }
                }
            } message: {
                Text("The account and every transaction on it become read-only. "
                   + "You can reopen it later.")
            }
        }
    }

    /// Shown while the balance is non-zero: an explanation and the zeroing transfer.
    /// - Parameter blocker: What is stopping the close.
    /// - Returns: The blocked content.
    private func blockedContent(_ blocker: CloseBlocker) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            CardContainer {
                VStack(alignment: .leading, spacing: 8) {
                    Text(blockerTitle(blocker))
                        .font(Typography.rowPrimary)
                        .foregroundStyle(Palette.textPrimary)
                    Text(blockerExplanation(blocker))
                        .font(Typography.rowSecondary)
                        .foregroundStyle(Palette.textSecondary)
                }
            }

            if counterparts.isEmpty {
                CardContainer {
                    Text("Add another open account first, so there is somewhere to move the money.")
                        .font(Typography.rowSecondary)
                        .foregroundStyle(Palette.textSecondary)
                }
            } else {
                transferCard(blocker)
            }
        }
    }

    /// The destination picker and the pre-filled transfer button (§4.7).
    /// - Parameter blocker: What is stopping the close.
    /// - Returns: The transfer card.
    private func transferCard(_ blocker: CloseBlocker) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text(isPayingOff(blocker) ? "Pay from" : "Move to").sectionLabel()
                FlowLayout(spacing: 8) {
                    ForEach(counterparts) { candidate in
                        counterpartChip(candidate)
                    }
                }
                Button(action: createTransfer) {
                    Text(transferButtonTitle(blocker))
                        .font(Typography.rowPrimary)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            counterpartID == nil ? Palette.placeholder : Palette.brandPurple,
                            in: .capsule
                        )
                }
                .buttonStyle(.plain)
                .disabled(counterpartID == nil)
            }
        }
    }

    /// Creates the zeroing transfer for the chosen counterpart.
    private func createTransfer() {
        guard let counterpartID else { return }
        Task {
            await model.createZeroingTransfer(for: account, counterpartID: counterpartID)
            dismiss()
        }
    }

    /// Shown once the balance is zero and the account may be closed.
    private var readyContent: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(account.name) is settled at zero and can be closed.")
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
                Text("It disappears from account pickers but stays in the Ledger's "
                   + "account filter, so your history remains browsable.")
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textSecondary)
                Button { isConfirming = true } label: {
                    Text("Close account")
                        .font(Typography.rowPrimary)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Palette.negativeRed, in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// One selectable counterpart chip.
    /// - Parameter candidate: The account the chip selects.
    /// - Returns: The chip view.
    private func counterpartChip(_ candidate: Domain.Account) -> some View {
        let isSelected = counterpartID == candidate.id
        return Button {
            counterpartID = candidate.id
        } label: {
            Text(candidate.name)
                .font(Typography.rowSecondary)
                .foregroundStyle(isSelected ? .white : Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Palette.brandPurple : Palette.segmentTrack, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// Whether the blocker is a card that owes money.
    /// - Parameter blocker: What is stopping the close.
    /// - Returns: `true` when the account must be paid off rather than emptied.
    private func isPayingOff(_ blocker: CloseBlocker) -> Bool {
        if case .owesBalance = blocker { return true }
        return false
    }

    /// The headline for the blocked state.
    /// - Parameter blocker: What is stopping the close.
    /// - Returns: The headline text.
    private func blockerTitle(_ blocker: CloseBlocker) -> String {
        switch blocker {
        case .holdsBalance(let cents):
            return "\(account.name) still holds \(money(cents))."
        case .owesBalance(let cents):
            return "\(account.name) still owes \(money(cents))."
        }
    }

    /// The explanation for the blocked state.
    /// - Parameter blocker: What is stopping the close.
    /// - Returns: The explanatory text.
    private func blockerExplanation(_ blocker: CloseBlocker) -> String {
        switch blocker {
        case .holdsBalance:
            return "Move the remaining money to another account before closing this one."
        case .owesBalance:
            return "Pay the card off from another account before closing it."
        }
    }

    /// The label on the transfer button.
    /// - Parameter blocker: What is stopping the close.
    /// - Returns: The button title.
    private func transferButtonTitle(_ blocker: CloseBlocker) -> String {
        switch blocker {
        case .holdsBalance(let cents): return "Transfer \(money(cents)) out"
        case .owesBalance(let cents): return "Pay \(money(cents))"
        }
    }

    /// Formats an amount using the display currency.
    /// - Parameter cents: The amount in cents.
    /// - Returns: The formatted string.
    private func money(_ cents: Int) -> String {
        CurrencyFormatter.string(fromCents: cents, currencyCode: model.settings.currencyCode)
    }
}
