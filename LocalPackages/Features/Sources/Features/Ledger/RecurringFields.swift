import SwiftUI
import Domain

/// The Recurring toggle and its revealed fields (§7.8, §4.5).
///
/// The end condition is optional: with neither an end date nor an occurrence count,
/// the rule runs until deleted.
struct RecurringFields: View {
    /// The form being edited.
    @Bindable var form: TransactionFormState
    /// The screen's keyboard focus, shared so its Done button can release this field.
    @FocusState.Binding var focus: TransactionField?

    /// The view body.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToggleRow(title: "Recurring", isOn: $form.isRecurring) { isOn in
                isOn
                    ? "Creates a repeating series from this transaction"
                    : "A one-off transaction"
            }
            if form.isRecurring {
                OptionPickerRow(
                    label: "Frequency",
                    options: RecurringFrequency.allCases,
                    selection: $form.frequency,
                    display: \.formLabel,
                    subtitle: \.formDetail
                )
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ends").sectionLabel()
                    SegmentedPillControl(
                        options: TransactionFormState.RecurringEndCondition.allCases,
                        selection: $form.endCondition,
                        display: \.title
                    )
                    endConditionDetail
                }
            }
        }
    }

    /// The field revealed by the chosen end condition.
    @ViewBuilder
    private var endConditionDetail: some View {
        switch form.endCondition {
        case .never:
            Text("Runs until you delete it.")
                .font(Typography.errorCaption)
                .foregroundStyle(Palette.textSecondary)
        case .onDate:
            DatePicker("Ends on", selection: $form.endDate, displayedComponents: .date)
                .font(Typography.rowSecondary)
                .tint(Palette.brandPurple)
        case .afterCount:
            HStack {
                Text("Occurrences")
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                TextField("12", text: $form.occurrenceLimitText)
                    .font(Typography.rowPrimary)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focus, equals: .occurrences)
                    .frame(width: 80)
            }
        }
    }
}

/// Display names for recurring frequencies.
extension RecurringFrequency {
    /// The label shown in the transaction form.
    var formLabel: String {
        switch self {
        case .weekly: return "Weekly"
        case .biweekly: return "Every 2 weeks"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    /// The explanatory line shown beneath ``formLabel`` in the picker.
    var formDetail: String? {
        switch self {
        case .weekly: return "Every 7 days"
        case .biweekly: return "Every 14 days"
        case .monthly: return "The same day each month, clamped in shorter months"
        case .yearly: return "The same day each year"
        }
    }

    /// The compact suffix used on a billing subline, such as "$9.99/mo".
    var shortSuffix: String {
        switch self {
        case .weekly: return "wk"
        case .biweekly: return "2wk"
        case .monthly: return "mo"
        case .yearly: return "yr"
        }
    }
}
