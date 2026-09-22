import SwiftUI
import Domain

/// The "Correct balance" flow (§4.4).
///
/// A single action that first asks which correction the user means, because the two
/// paths have very different consequences: an adjustment is a dated correction that
/// leaves history intact, while editing the opening balance recomputes the account's
/// entire history.
struct CorrectBalanceSheet: View {
    /// The account being corrected.
    let account: Domain.Account
    /// The screen's view model.
    let model: SettingsViewModel

    /// Dismisses the sheet.
    @Environment(\.dismiss) private var dismiss
    /// Which path the user chose, or `nil` while still choosing.
    @State private var choice: BalanceCorrection?
    /// The balance the user says is correct, as an unsigned magnitude.
    @State private var targetText = ""
    /// Which side of zero that balance falls on.
    @State private var direction: BalanceEntry.Direction = .positive
    /// When the correction takes effect.
    @State private var date: Date = .now
    /// Whether Save has been attempted, which reveals validation (§7.11).
    @State private var hasAttemptedSave = false
    /// Whether the amount field holds the keyboard.
    @FocusState private var focusedField: CorrectBalanceField?

    /// The target balance in signed cents, or `nil` when the text does not parse.
    private var targetCents: Int? {
        MoneyInput.magnitudeCents(from: targetText).map {
            BalanceEntry.signedCents(magnitude: $0, direction: direction)
        }
    }

    /// The target field's error, or `nil` when valid.
    private var targetError: String? {
        guard hasAttemptedSave, targetCents == nil else { return nil }
        return "Enter the correct balance to continue."
    }

    /// The view body.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    currentBalanceCard
                    if let choice {
                        correctionForm(choice)
                    } else {
                        chooser
                    }
                }
                .padding(16)
            }
            .background(Palette.appBackground)
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneToolbar($focusedField)
            .navigationTitle("Correct Balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if choice != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                    }
                }
            }
        }
    }

    /// Shows what the app currently believes the balance to be.
    private var currentBalanceCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 4) {
                Text("Current balance").sectionLabel()
                Text(money(account.cachedBalanceCents)).moneyText()
                    .foregroundStyle(Palette.textPrimary)
            }
        }
    }

    /// The two-path chooser (§4.4).
    private var chooser: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What happened?").sectionLabel()
            ForEach(BalanceCorrection.allCases) { option in
                Button {
                    choice = option
                    let seed = option == .openingBalance
                        ? account.openingBalanceCents
                        : account.cachedBalanceCents
                    targetText = MoneyInput.magnitudeText(fromCents: seed)
                    direction = BalanceEntry.direction(ofCents: seed)
                    if option == .openingBalance {
                        date = account.openingBalanceDate
                    }
                    // The field only exists once a path is chosen, so focus waits for it.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        focusedField = .amount
                    }
                } label: {
                    CardContainer {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(option.title)
                                .font(Typography.rowPrimary)
                                .foregroundStyle(Palette.textPrimary)
                            Text(option.explanation)
                                .font(Typography.rowSecondary)
                                .foregroundStyle(Palette.textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The form for the chosen correction.
    /// - Parameter choice: Which correction is being made.
    /// - Returns: The form view.
    private func correctionForm(_ choice: BalanceCorrection) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text(choice.title)
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
                BalanceDirectionField(
                    label: choice == .adjustment ? "Correct balance is" : "Opening balance",
                    error: targetError,
                    kind: account.kind,
                    text: $targetText,
                    direction: $direction,
                    focus: $focusedField,
                    field: CorrectBalanceField.amount
                )
                DatePicker(
                    choice == .adjustment ? "Correction date" : "Opening balance as of",
                    selection: $date,
                    displayedComponents: .date
                )
                .font(Typography.rowSecondary)
                .foregroundStyle(Palette.textSecondary)
                Text(choice == .adjustment
                     ? "Records a dated adjustment for the difference. Your history is unchanged."
                     : "Recomputes this account's entire history from the new starting figure.")
                    .font(Typography.errorCaption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    /// Validates and applies the chosen correction.
    private func save() {
        hasAttemptedSave = true
        guard let choice, let targetCents else { return }
        Task {
            switch choice {
            case .adjustment:
                await model.recordAdjustment(for: account, targetCents: targetCents, date: date)
            case .openingBalance:
                var updated = account
                updated.openingBalanceCents = targetCents
                updated.openingBalanceDate = date
                await model.save(updated)
            }
            dismiss()
        }
    }

    /// Formats an amount using the display currency.
    /// - Parameter cents: The amount in cents.
    /// - Returns: The formatted string.
    private func money(_ cents: Int) -> String {
        CurrencyFormatter.string(fromCents: cents, currencyCode: model.settings.currencyCode)
    }
}

/// Which field of the Correct Balance sheet holds the keyboard (§7.11).
enum CorrectBalanceField: Hashable {
    /// The corrected balance.
    case amount
}
