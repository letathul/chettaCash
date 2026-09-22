import SwiftUI
import Domain

/// Which field of the product form holds the keyboard (§7.11).
enum ProductField: Hashable {
    /// The product's name.
    case name
    /// The optional note.
    case notes
    /// The tag being typed.
    case tag
}

/// The read-only purchase summary at the top of the product form (§7.8).
///
/// Shown rather than made editable on purpose: this is the one place the money lives,
/// and letting a product edit it would create a second source of truth.
///
/// Its own view taking plain values, so formatting the amount and the date does not
/// re-run on every character typed into the name field below it.
struct PurchaseSummaryCard: View {
    /// The purchase being summarised.
    let purchase: Domain.Transaction
    /// The purchase's account name, already resolved.
    let accountName: String?
    /// The display currency.
    let currencyCode: String

    /// The view body.
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text("From this purchase").sectionLabel()
                HStack(spacing: 10) {
                    Image(systemName: "receipt")
                        .font(.title3)
                        .foregroundStyle(Palette.brandPurple)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(purchase.merchant.isEmpty
                             ? "Untitled purchase"
                             : purchase.merchant)
                            .font(Typography.rowPrimary)
                            .foregroundStyle(Palette.textPrimary)
                        Text(subtitle)
                            .font(Typography.rowSecondary)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: 8)
                    if purchase.receiptFileID != nil {
                        Image(systemName: "paperclip")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.textSecondary)
                            .accessibilityLabel("This purchase has a receipt")
                    }
                }
                Text(purchase.amountCents == 0
                     ? "Nothing was paid for this. Edit the purchase in the Ledger to change that."
                     : "Price, account and receipt are edited on the purchase.")
                    .font(Typography.errorCaption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    /// Amount, date and account, in one line.
    private var subtitle: String {
        let amount = CurrencyFormatter.string(
            fromCents: purchase.amountCents, currencyCode: currencyCode
        )
        let date = purchase.date.formatted(.dateTime.day().month(.abbreviated).year())
        guard let accountName else { return "\(amount) · \(date)" }
        return "\(amount) · \(date) · \(accountName)"
    }
}

/// Name, category, notes and tags (§7.7).
struct ProductDetailsCard: View {
    /// The form being edited.
    @Bindable var form: ProductFormState
    /// The categories to offer.
    let categories: [Domain.Category]
    /// The screen's keyboard focus.
    @FocusState.Binding var focus: ProductField?
    /// Creates a category and selects it.
    let onAddCategory: (String) -> Void

    /// The view body.
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                ValidatedField(label: "Name", error: form.nameError) {
                    TextField("Sony headphones", text: $form.name)
                        .font(Typography.rowPrimary)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .focused($focus, equals: .name)
                        .onSubmit { focus = .notes }
                }
                CategoryChipRow(
                    categories: categories,
                    categoryID: $form.categoryID,
                    onAdd: onAddCategory
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes").sectionLabel()
                    TextField("Optional", text: $form.notes, axis: .vertical)
                        .font(Typography.rowPrimary)
                        .lineLimit(2...5)
                        .focused($focus, equals: .notes)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tags").sectionLabel()
                    TagInput(tags: $form.tags, focus: $focus, field: ProductField.tag)
                }
            }
        }
    }
}
