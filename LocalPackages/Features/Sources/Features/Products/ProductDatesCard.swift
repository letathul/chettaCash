import SwiftUI
import Domain

/// The three date-driven toggles (§7.7).
///
/// The purchase date is not here: it belongs to the transaction and is shown read-only
/// in the sheet's header (§7.8).
///
/// **Warranty / expiry appears on Edit as well as Add** — the original mockup omitted
/// it, which was an oversight: the product list displays warranty items, so the app
/// must let you edit them.
struct ProductDatesCard: View {
    /// The form being edited.
    @Bindable var form: ProductFormState
    /// What ``ReminderLeadTime/useDefault`` currently resolves to, for the picker's
    /// explanatory line. The card cannot read it itself — settings live on the view model.
    let defaultLeadTimeLabel: String

    /// The view body.
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                trialSection

                Divider().overlay(Palette.borderSubtle)
                warrantySection

                Divider().overlay(Palette.borderSubtle)
                recurringSection
            }
        }
    }

    /// The free-trial toggle and its revealed fields.
    private var trialSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToggleRow(title: "Free trial", isOn: $form.hasTrial) { isOn in
                isOn ? "Reminds you before the trial ends" : "No trial to track"
            }
            if form.hasTrial {
                DatePicker(
                    "Trial ends", selection: $form.trialEndsDate, displayedComponents: .date
                )
                .font(Typography.rowSecondary)
                .tint(Palette.brandPurple)
                reminderRow(selection: $form.trialReminderLeadTime)
            }
        }
    }

    /// The warranty toggle and its revealed fields.
    private var warrantySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToggleRow(title: "Warranty / expiry", isOn: $form.hasWarranty) { isOn in
                isOn ? "Reminds you before it expires" : "No warranty to track"
            }
            if form.hasWarranty {
                DatePicker(
                    "Expires on", selection: $form.warrantyExpiresDate,
                    displayedComponents: .date
                )
                .font(Typography.rowSecondary)
                .tint(Palette.brandPurple)
                reminderRow(selection: $form.warrantyReminderLeadTime)
            }
        }
    }

    /// The recurring-charge toggle and its frequency picker.
    private var recurringSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToggleRow(title: "Recurring charge", isOn: $form.isRecurring) { isOn in
                isOn
                    ? "Creates a repeating charge in your Ledger"
                    : "A one-off purchase"
            }
            if form.isRecurring {
                OptionPickerRow(
                    label: "Frequency",
                    options: RecurringFrequency.allCases,
                    selection: $form.frequency,
                    display: \.formLabel,
                    subtitle: \.formDetail
                )
            }
        }
    }

    /// A reminder lead-time row (§8.4).
    /// - Parameter selection: The bound lead time.
    /// - Returns: The row view.
    private func reminderRow(selection: Binding<ReminderLeadTime>) -> some View {
        OptionPickerRow(
            label: "Remind me",
            options: ReminderLeadTime.allCases,
            selection: selection,
            display: \.settingsLabel,
            subtitle: { lead in
                guard lead == .useDefault else { return lead.settingsDetail }
                return "Currently \(defaultLeadTimeLabel)"
            }
        )
    }
}
