import SwiftUI
import Domain

/// An unsigned money field paired with the side of zero it falls on (§4.1).
///
/// Money fields present a `.decimalPad`, which has no minus key, so the user types the
/// figure and picks its direction here rather than typing a sign. The wording follows
/// the account's kind: a card is "Owed" or "In credit", an account "In hand" or
/// "Overdrawn" — one word for both would be wrong in one of the two cases.
struct BalanceDirectionField<Field: Hashable>: View {
    /// The field's label.
    let label: String
    /// The validation message, or `nil` when valid.
    let error: String?
    /// Which kind of account this balance belongs to, which decides the wording.
    let kind: AccountKind
    /// The typed magnitude.
    @Binding var text: String
    /// Which side of zero the figure falls on.
    @Binding var direction: BalanceEntry.Direction
    /// The screen's keyboard focus.
    @FocusState.Binding var focus: Field?
    /// Which field this is, in the screen's focus enum.
    let field: Field

    /// The view body.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ValidatedField(label: label, error: error) {
                TextField("0.00", text: $text)
                    .font(Typography.rowPrimary)
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: field)
            }
            SegmentedPillControl(
                options: BalanceEntry.Direction.allCases,
                selection: $direction,
                display: { BalanceEntry.label(for: $0, kind: kind) }
            )
            Text(explanation)
                .font(Typography.errorCaption)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    /// What the chosen direction means for the stored balance.
    ///
    /// Spelled out because the app stores money owed as a negative number (§4.1) while
    /// the field above shows an unsigned figure — the user should not have to infer
    /// that a typed "1,200" is about to become "−$1,200".
    private var explanation: String {
        switch direction {
        case .negative:
            return kind == .card
                ? "Money you owe on this card. Shown as a negative balance."
                : "This account is overdrawn. Shown as a negative balance."
        case .positive:
            return kind == .card
                ? "This card is in credit — you have overpaid it."
                : "Money you have in this account."
        }
    }
}
