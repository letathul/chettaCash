import SwiftUI
import Domain

/// Which field of the transaction form holds the keyboard (§7.11).
///
/// One enum for the whole screen, so the Done button above the keyboard can release
/// whichever field raised it — including the tag and occurrence fields, whose numeric
/// and compact keyboards have no return key of their own.
enum TransactionField: Hashable {
    /// The large centred amount.
    case amount
    /// The merchant name.
    case merchant
    /// The optional location.
    case location
    /// The optional memo.
    case memo
    /// The tag being typed.
    case tag
    /// The recurring series' occurrence count.
    case occurrences
}

/// The large centred amount entry (§7.8).
///
/// Its own view, and given the raw text rather than the form, so that typing here
/// invalidates this and nothing else. As a computed property on the sheet it shared one
/// invalidation scope with the mode picker, both account pickers, the category chips,
/// the products card and the memo — all re-evaluated on every character.
///
/// The error and the colour are derived here for the same reason: reading them from the
/// parent would make the parent depend on `amountText` again.
struct AmountField: View {
    /// The typed amount.
    @Binding var text: String
    /// Expense, income or transfer, which decides the colour and the zero rule.
    let mode: TransactionFormMode
    /// Whether Save has been attempted, which is what reveals validation (§7.11).
    let hasAttemptedSave: Bool
    /// The screen's keyboard focus.
    @FocusState.Binding var focus: TransactionField?

    /// The field's size, which scales with Dynamic Type (§12).
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize: CGFloat = 44

    /// The view body.
    var body: some View {
        VStack(spacing: 6) {
            TextField("0.00", text: $text)
                .font(.system(size: amountSize, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
                // A decimal pad, not `.numbersAndPunctuation`: the sign comes from the
                // mode above, so there is nothing here for a minus key to mean.
                .keyboardType(.decimalPad)
                .focused($focus, equals: .amount)
                .accessibilityLabel("Amount")
            Text(error ?? " ")
                .font(Typography.errorCaption)
                .foregroundStyle(Palette.negativeRed)
                .opacity(error == nil ? 0 : 1)
                .accessibilityHidden(error == nil)
        }
        .frame(maxWidth: .infinity)
    }

    /// The field's error, or `nil` when valid.
    ///
    /// Shares ``TransactionFormState/amountError(text:mode:hasAttemptedSave:)`` with the
    /// form, so this can never disagree with what Save will accept.
    private var error: String? {
        TransactionFormState.amountError(
            text: text, mode: mode, hasAttemptedSave: hasAttemptedSave
        )
    }

    /// Green for income, red only when invalid, otherwise primary text (§7.8).
    private var color: Color {
        if error != nil { return Palette.negativeRed }
        return mode == .income ? Palette.positiveGreen : Palette.textPrimary
    }
}

/// The merchant and location fields.
struct MerchantLocationFields: View {
    /// The merchant name.
    @Binding var merchant: String
    /// The optional location.
    @Binding var location: String
    /// The screen's keyboard focus.
    @FocusState.Binding var focus: TransactionField?

    /// The view body.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Merchant").sectionLabel()
            TextField("Whole Foods", text: $merchant)
                .font(Typography.rowPrimary)
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .focused($focus, equals: .merchant)
                .onSubmit { focus = .location }
            Text("Location").sectionLabel()
            TextField("Optional", text: $location)
                .font(Typography.rowPrimary)
                .submitLabel(.next)
                .focused($focus, equals: .location)
                .onSubmit { focus = .memo }
        }
    }
}

/// The memo field, which stays optional in every mode.
struct MemoCard: View {
    /// The optional memo.
    @Binding var memo: String
    /// The screen's keyboard focus.
    @FocusState.Binding var focus: TransactionField?

    /// The view body.
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text("Memo").sectionLabel()
                TextField("Optional", text: $memo, axis: .vertical)
                    .font(Typography.rowPrimary)
                    .lineLimit(1...4)
                    .focused($focus, equals: .memo)
            }
        }
    }
}

/// A chip row of selectable categories with an inline "+ Custom" chip (§8.4).
///
/// Its own view, taking the already-filtered categories, so the sheet does not re-filter
/// every category and re-derive every swatch on each keystroke elsewhere.
struct CategoryChipRow: View {
    /// The categories to offer.
    let categories: [Domain.Category]
    /// The chosen category.
    @Binding var categoryID: UUID?
    /// Creates a category and selects it.
    let onAdd: (String) -> Void

    /// The view body.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Category").sectionLabel()
            FlowLayout(spacing: 8) {
                ForEach(categories) { category in
                    CategoryChip(
                        category: category,
                        isSelected: categoryID == category.id
                    ) {
                        categoryID = categoryID == category.id ? nil : category.id
                    }
                }
                InlineAddChip(title: "+ Custom", existing: labels, onCommit: onAdd)
            }
        }
    }

    /// The existing labels, for case-insensitive de-duplication in the add chip.
    private var labels: [String] { categories.map(\.label) }
}

/// One selectable category chip, tinted from the category palette (§8.2).
struct CategoryChip: View {
    /// The category the chip selects.
    let category: Domain.Category
    /// Whether it is the chosen one.
    let isSelected: Bool
    /// Selects or clears it.
    let action: () -> Void

    /// The view body.
    var body: some View {
        let swatch = CategoryPalette.swatch(
            for: category.label, creationIndex: category.sortIndex
        )
        Button(action: action) {
            Text(category.label)
                .font(Typography.rowSecondary)
                .foregroundStyle(isSelected ? .white : swatch.foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Palette.brandPurple : swatch.background, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// A labelled account picker with its validation message.
struct AccountPickerField: View {
    /// The field's label — "Account", or "From"/"To" in transfer mode.
    let label: String
    /// The validation message, or `nil` when valid.
    let error: String?
    /// The accounts to offer.
    let accounts: [Domain.Account]
    /// The chosen account.
    @Binding var selection: UUID?

    /// The view body.
    var body: some View {
        ValidatedField(label: label, error: error) {
            Menu {
                ForEach(accounts) { account in
                    Button(account.name) { selection = account.id }
                }
            } label: {
                HStack {
                    Text(chosenName ?? "Choose an account")
                        .font(Typography.rowPrimary)
                        .foregroundStyle(
                            chosenName == nil ? Palette.placeholder : Palette.textPrimary
                        )
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(Palette.textSecondary)
                }
                // ValidatedField paints its chrome outside the Menu, so without this only
                // the name and the chevron would open it.
                .tappableSurface()
            }
        }
    }

    /// The chosen account's name, or `nil` when none is chosen.
    private var chosenName: String? {
        guard let selection else { return nil }
        return accounts.first { $0.id == selection }?.name
    }
}
