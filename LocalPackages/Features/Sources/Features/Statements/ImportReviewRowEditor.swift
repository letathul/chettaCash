import SwiftUI
import Domain

/// The editor a review row opens into (§9.7).
///
/// Every field a statement line can get wrong, in the order the user will notice them: the
/// direction first, because a charge filed as income is the correction this screen exists for.
struct ImportReviewRowEditor: View {
    /// The row's editable state.
    @Bindable var draft: StatementReviewDraft
    /// The categories to offer.
    let categories: [Domain.Category]
    /// Keyboard focus for the name field.
    @FocusState private var focus: Field?

    /// Which field the keyboard is in.
    private enum Field: Hashable {
        /// The merchant name.
        case merchant
        /// The amount.
        case amount
    }

    /// The view body.
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            directionPicker
            HStack(alignment: .top, spacing: 12) {
                nameField
                amountField
            }
            datePicker
            CategoryChipRow(categories: categories, categoryID: $draft.categoryID) { _ in }
            sourceLine
        }
        .padding(.leading, 36)
        .padding(.top, 4)
    }

    /// Money out or money in.
    private var directionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Direction").sectionLabel()
            Picker("Direction", selection: $draft.isIncome) {
                Text("Money out").tag(false)
                Text("Money in").tag(true)
            }
            .pickerStyle(.segmented)
        }
    }

    /// The merchant name.
    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name").sectionLabel()
            TextField("Merchant", text: $draft.merchant)
                .font(Typography.rowPrimary)
                .textInputAutocapitalization(.words)
                .focused($focus, equals: .merchant)
        }
    }

    /// The amount, unsigned.
    private var amountField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Amount").sectionLabel()
            TextField("0.00", text: $draft.amountText)
                .font(Typography.rowPrimary)
                .keyboardType(.decimalPad)
                .focused($focus, equals: .amount)
                .frame(maxWidth: 110)
        }
    }

    /// The date, which a line may not have had at all.
    @ViewBuilder
    private var datePicker: some View {
        if let date = draft.date {
            DatePicker(
                "Date",
                selection: Binding(get: { date }, set: { draft.date = $0 }),
                displayedComponents: .date
            )
            .font(Typography.rowSecondary)
        } else {
            Button("Set a date") { draft.date = .now }
                .font(Typography.rowSecondary)
                .foregroundStyle(Palette.brandPurple)
        }
    }

    /// The statement's own wording, so the user can check it against their bank.
    private var sourceLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("On your statement").sectionLabel()
            Text(draft.sourceText)
                .font(Typography.rowSecondary)
                .foregroundStyle(Palette.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The ledger entry a duplicate row was paired with (§4.2).
///
/// Shown inside the row rather than in a wizard of its own: the question "is this the same
/// purchase?" is answered by looking at the two side by side, and everything else the user
/// needs to decide is already on this screen.
struct DuplicateNotice: View {
    /// The entry the ledger already holds.
    let existing: Domain.Transaction
    /// What a reader concluded about the pairing.
    let rationale: String?
    /// The currency amounts are shown in.
    let currencyCode: String

    /// The view body.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Already in your ledger").sectionLabel()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(existing.merchant)
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 8)
                Text(CurrencyFormatter.string(
                    fromCents: existing.amountCents, currencyCode: currencyCode
                ))
                .font(Typography.rowSecondary)
                .foregroundStyle(Palette.textSecondary)
                .monospacedDigit()
            }
            if let rationale {
                Text(rationale)
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.segmentTrack, in: .rect(cornerRadius: 12))
        .padding(.leading, 36)
    }
}
