import SwiftUI
import Domain

/// The transaction sheet's category, account and date fields (§7.8).
///
/// Split from ``TransactionSheet`` to keep each file within the 300-line limit.
extension TransactionSheet {
    /// The category chip row, which swaps context entirely between expense and income.
    @ViewBuilder
    var categoryField: some View {
        if let context = form.mode.categoryContext {
            CategoryChipRow(
                categories: model.selectableCategories(for: context),
                categoryID: $form.categoryID
            ) { label in
                Task { form.categoryID = await model.addCategory(label: label, context: context) }
            }
        }
    }

    /// The source account row, labelled for the current mode.
    var accountField: some View {
        AccountPickerField(
            label: form.mode == .transfer ? "From" : "Account",
            error: form.accountError,
            accounts: model.selectableAccounts,
            selection: $form.accountID
        )
    }

    /// The destination account picker, shown in transfer mode only (§7.8).
    var transferFields: some View {
        AccountPickerField(
            label: "To",
            error: form.destinationError,
            accounts: model.selectableAccounts,
            selection: $form.destinationAccountID
        )
    }

    /// The date and time picker.
    var datePicker: some View {
        DatePicker("Date and time", selection: $form.date)
            .font(Typography.rowPrimary)
            .tint(Palette.brandPurple)
    }

    /// The merchant and location fields.
    var locationField: some View {
        MerchantLocationFields(
            merchant: $form.merchant,
            location: $form.location,
            focus: $focusedField
        )
    }
}
