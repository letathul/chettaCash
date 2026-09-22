import SwiftUI
import Domain

/// The interest-and-fees prompt shown once when a statement closes (§4.6).
///
/// Asked once per statement. Dismissing resolves it and it never asks again. No APR
/// is stored and no interest is calculated: whatever the real statement charged is
/// typed in here.
struct InterestPromptCard: View {
    /// The card's name, used in the question.
    let accountName: String
    /// The statement being asked about.
    let statement: Domain.CardStatement
    /// The display currency.
    let currencyCode: String
    /// Records the amount, or dismisses when passed `nil`.
    let onResolve: (Domain.CardStatement, Int?) -> Void

    /// The typed amount, as an unsigned magnitude.
    @State private var amountText = ""
    /// Whether the amount field holds the keyboard.
    @FocusState private var isAmountFocused: Bool

    /// The parsed amount, if it is positive.
    ///
    /// Interest and fees are always a charge, so there is no direction to choose here —
    /// the figure is a magnitude and the sign is decided by what it becomes (§4.1).
    private var cents: Int? {
        guard let parsed = MoneyInput.magnitudeCents(from: amountText), parsed > 0 else {
            return nil
        }
        return parsed
    }

    /// The view body.
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("Did \(accountName) charge interest or fees this period?")
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
                Text(
                    "Closed "
                    + statement.closingDate.formatted(.dateTime.day().month(.wide))
                    + ". Enter what your real statement shows."
                )
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textSecondary)
                TextField("0.00", text: $amountText)
                    .font(Typography.rowPrimary)
                    .keyboardType(.decimalPad)
                    .focused($isAmountFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Palette.surface, in: .rect(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Palette.borderSubtle, lineWidth: 1)
                    }
                HStack {
                    Button("No charges") { onResolve(statement, nil) }
                        .font(Typography.rowPrimary)
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Button("Record") { onResolve(statement, cents) }
                        .font(Typography.rowPrimary.weight(.semibold))
                        .foregroundStyle(cents == nil ? Palette.placeholder : Palette.brandPurple)
                        .disabled(cents == nil)
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Palette.attentionAmber, lineWidth: 1.5)
        }
    }
}

/// Lets the user replace a computed statement balance with the real figure (§4.6).
struct StatementOverrideSheet: View {
    /// The statement being overridden.
    let statement: Domain.CardStatement
    /// The display currency.
    let currencyCode: String
    /// Saves the override, or clears it when passed `nil`.
    let onSave: (Int?) -> Void

    /// Dismisses the sheet.
    @Environment(\.dismiss) private var dismiss
    /// The typed figure, as an unsigned magnitude.
    @State private var amountText: String
    /// Whether the amount field holds the keyboard.
    @FocusState private var isAmountFocused: Bool

    /// Creates the sheet.
    /// - Parameters:
    ///   - statement: The statement being overridden.
    ///   - currencyCode: The display currency.
    ///   - onSave: Saves the override.
    init(statement: Domain.CardStatement, currencyCode: String, onSave: @escaping (Int?) -> Void) {
        self.statement = statement
        self.currencyCode = currencyCode
        self.onSave = onSave
        _amountText = State(initialValue: MoneyInput.magnitudeText(
            fromCents: statement.effectiveBalanceCents
        ))
    }

    /// The view body.
    var body: some View {
        NavigationStack {
            ScrollView {
                CardContainer {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Computed from your transactions: "
                           + CurrencyFormatter.string(
                                fromCents: statement.computedBalanceCents,
                                currencyCode: currencyCode
                             ))
                            .font(Typography.rowSecondary)
                            .foregroundStyle(Palette.textSecondary)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Statement balance").sectionLabel()
                            TextField("0.00", text: $amountText)
                                .font(Typography.rowPrimary)
                                .keyboardType(.decimalPad)
                                .focused($isAmountFocused)
                        }
                        Button("Use the computed figure") {
                            onSave(nil)
                            dismiss()
                        }
                        .font(Typography.rowSecondary)
                        .foregroundStyle(Palette.brandPurple)
                    }
                }
                .padding(16)
            }
            .background(Palette.appBackground)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Statement Balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isAmountFocused = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(MoneyInput.magnitudeCents(from: amountText))
                        dismiss()
                    }
                }
            }
        }
        .autoFocus($isAmountFocused)
    }
}
