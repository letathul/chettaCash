import SwiftUI
import Domain

/// The account form's fields, shared by the Add sheet and the Edit sheet (§7.9).
///
/// The balance field is the **opening** balance, not a current balance: the current
/// balance is derived from transaction history and cannot be typed in (§4.1).
///
/// The group picker is deliberately **not** here: ``AddAccountSheet`` is already scoped
/// to one group, so only the Edit sheet composes ``AccountGroupField`` above this stack.
struct AccountFormFields: View {
    /// The vertical rhythm of the stack, so callers composing above it can match.
    static let fieldSpacing: CGFloat = 14

    /// The form being edited.
    @Bindable var form: AccountFormState
    /// Whether every field is disabled, as it is for a closed account (§4.7).
    var isReadOnly = false
    /// The screen's keyboard focus.
    @FocusState.Binding var focus: AccountField?

    /// The view body.
    var body: some View {
        VStack(alignment: .leading, spacing: Self.fieldSpacing) {
            typeField
            ValidatedField(label: "Account name", error: form.nameError) {
                TextField("TD Chequing", text: $form.name)
                    .font(Typography.rowPrimary)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .focused($focus, equals: .name)
                    .onSubmit { focus = .openingBalance }
            }
            openingBalanceField
            if form.kind == .card { cardFields }
            cardIdentityFields
        }
        .disabled(isReadOnly)
    }

    /// The Account / Card segmented control.
    private var typeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Account type").sectionLabel()
            SegmentedPillControl(
                options: AccountKind.allCases,
                selection: $form.kind,
                display: { $0 == .account ? "Account" : "Card" }
            )
        }
    }

    /// The opening balance field and its "as of" date.
    private var openingBalanceField: some View {
        VStack(alignment: .leading, spacing: 8) {
            BalanceDirectionField(
                label: "Opening balance",
                error: form.openingBalanceError,
                kind: form.kind,
                text: $form.openingBalanceText,
                direction: $form.balanceDirection,
                focus: $focus,
                field: AccountField.openingBalance
            )
            DatePicker(
                "Opening balance as of",
                selection: $form.openingBalanceDate,
                displayedComponents: .date
            )
            .font(Typography.rowSecondary)
            .foregroundStyle(Palette.textSecondary)
            Text("Don't know it? Leave 0 and correct it later.")
                .font(Typography.errorCaption)
                .foregroundStyle(Palette.textSecondary)
            if form.kind == .card {
                Text("Cards are stored as money owed, whichever sign you type.")
                    .font(Typography.errorCaption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    /// Statement and payment fields, shown for cards only.
    private var cardFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            dayRow("Statement date", selection: $form.statementDayOfMonth)
            dayRow("Payment due date", selection: $form.paymentDueDayOfMonth)
            ToggleRow(title: "Remind me before due date", isOn: $form.remindBeforeDueDate) { isOn in
                isOn ? "Reminds you three days before the due date" : "No payment reminder"
            }
        }
    }

    /// The account's last four digits and card network (§9.7, §4.2).
    ///
    /// Shown for every account kind, not just ``AccountKind/card``: a chequing account
    /// has a debit card, and a receipt prints its digits the same way. Entirely optional
    /// — it exists so a scanned receipt or a Shortcut can find its way back to the right
    /// account, and an account without it simply is not matched automatically.
    private var cardIdentityFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Account number").sectionLabel()
            HStack(spacing: 12) {
                TextField("Last 4 digits", text: $form.last4Text)
                    .font(Typography.rowPrimary)
                    .keyboardType(.numberPad)
                    .focused($focus, equals: .last4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: form.last4Text) { _, typed in
                        // Clamped as the user types: the field accepts only what it can
                        // actually store, rather than silently dropping the rest on save.
                        let digits = String(typed.filter(\.isNumber).prefix(4))
                        if digits != typed { form.last4Text = digits }
                    }
                networkPicker
            }
            Text("Optional. Lets a scanned receipt or a Shortcut pick this account for you.")
                .font(Typography.errorCaption)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    /// The card network menu.
    private var networkPicker: some View {
        // A Menu rather than a compact Picker, matching `dayRow` and `accountPicker`:
        // the Picker only accepts taps on its value bubble, leaving the rest dead.
        Menu {
            Picker("Card network", selection: $form.cardNetwork) {
                Text("Not set").tag(CardNetwork?.none)
                ForEach(CardNetwork.allCases, id: \.self) { network in
                    Text(network.displayName).tag(CardNetwork?.some(network))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(form.cardNetwork?.displayName ?? "Network")
                    .font(Typography.rowPrimary)
                    .foregroundStyle(
                        form.cardNetwork == nil ? Palette.textSecondary : Palette.textPrimary
                    )
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Palette.textSecondary)
            }
            .tappableSurface()
        }
    }

    /// A day-of-month picker row.
    ///
    /// The label is drawn alongside the menu rather than left to the picker, which
    /// renders label-less inside a `VStack` and leaves two bare numbers on screen.
    ///
    /// - Parameters:
    ///   - label: The row's label.
    ///   - selection: The bound day of month.
    /// - Returns: The row view.
    private func dayRow(_ label: String, selection: Binding<Int>) -> some View {
        // A Menu rather than a compact Picker: the Picker only accepts taps on its own
        // value bubble, leaving the label and the gap dead. This matches accountPicker.
        Menu {
            Picker(label, selection: selection) {
                ForEach(1...28, id: \.self) { day in
                    Text(dayOrdinal(day)).tag(day)
                }
            }
        } label: {
            HStack {
                Text(label)
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 12)
                Text(dayOrdinal(selection.wrappedValue))
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.brandPurple)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Palette.textSecondary)
            }
            .tappableSurface()
        }
        .accessibilityElement(children: .combine)
    }

    /// Every day of the month as an ordinal, such as "5th", built once.
    ///
    /// Indexed by day, so `dayOrdinals[5]` is "5th" and index 0 is unused. Built at
    /// first use rather than per call: the statement and due-date menus each render 28
    /// rows, so computing these inline allocated 29 `NumberFormatter`s on every pass of
    /// this body — which typing the account name re-runs on every keystroke.
    private static let dayOrdinals: [String] = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return (0...28).map { day in
            formatter.string(from: NSNumber(value: day)) ?? "\(day)"
        }
    }()

    /// Renders a day of the month as an ordinal, such as "5th".
    /// - Parameter day: The day number, which the callers constrain to `1...28`.
    /// - Returns: The ordinal string.
    private func dayOrdinal(_ day: Int) -> String {
        Self.dayOrdinals.indices.contains(day) ? Self.dayOrdinals[day] : "\(day)"
    }
}

/// Which field of the account form holds the keyboard (§7.11).
enum AccountField: Hashable {
    /// The account's display name.
    case name
    /// The opening balance.
    case openingBalance
    /// The card's last four digits.
    case last4
}
