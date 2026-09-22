import SwiftUI
import Domain

/// Add and Edit Product (§7.7, §6.3, §7.11).
///
/// A `Cancel / Title / Save` header with no back chevron and no bottom Save button.
/// Add is `interactiveDismissDisabled`; Edit keeps standard swipe-to-dismiss and gains
/// a Delete row below the form.
///
/// The purchase sits at the top as a read-only summary. There is no price field and no
/// Scan receipt row here: both belong to the transaction, which is where they are
/// edited (§7.8).
struct ProductSheet: View {
    /// The screen's view model.
    let model: ProductsViewModel
    /// The product being edited, or `nil` when adding.
    let editing: Domain.Product?
    /// Called with the committed product instead of saving, when the purchase does not
    /// exist yet — the Add Transaction form collects products before it has an id.
    let onCommit: ((Domain.Product) -> Void)?

    /// Dismisses the sheet.
    @Environment(\.dismiss) private var dismiss
    /// The editable form state.
    @State var form: ProductFormState
    /// Whether the delete confirmation is showing (§7.11).
    @State private var isConfirmingDelete = false
    /// Which field holds the keyboard.
    @FocusState private var focusedField: ProductField?

    /// Creates the sheet.
    /// - Parameters:
    ///   - model: The screen's view model.
    ///   - purchase: The transaction the product belongs to.
    ///   - editing: The product being edited, or `nil` when adding.
    ///   - sortIndex: Where a new product sits among the purchase's products.
    ///   - onCommit: Receives the product instead of saving it, for a purchase that has
    ///     not been persisted yet.
    init(
        model: ProductsViewModel,
        purchase: Domain.Transaction,
        editing: Domain.Product? = nil,
        sortIndex: Int = 0,
        onCommit: ((Domain.Product) -> Void)? = nil
    ) {
        self.model = model
        self.editing = editing
        self.onCommit = onCommit
        if let editing {
            _form = State(initialValue: ProductFormState(editing: editing, purchase: purchase))
        } else {
            _form = State(initialValue: ProductFormState(
                purchase: purchase, sortIndex: sortIndex
            ))
        }
    }

    /// Whether this sheet is editing rather than adding.
    var isEditing: Bool { editing != nil }

    /// The view body.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PurchaseSummaryCard(
                        purchase: form.purchase,
                        accountName: model.account(id: form.purchase.accountID)?.name,
                        currencyCode: model.settings.currencyCode
                    )
                    ProductDetailsCard(
                        form: form,
                        categories: model.selectableCategories,
                        focus: $focusedField
                    ) { label in
                        Task { form.categoryID = await model.addCategory(label: label) }
                    }
                    ProductDatesCard(
                        form: form,
                        defaultLeadTimeLabel: model.settings.defaultReminderLeadTime.settingsLabel
                    )
                    if isEditing, onCommit == nil { deleteRow }
                }
                .padding(16)
            }
            .background(Palette.appBackground)
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneToolbar($focusedField)
            .navigationTitle(isEditing ? "Edit Product" : "Add Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
        .interactiveDismissDisabled(!isEditing)
        .autoFocus($focusedField, on: .name)
        .task {
            // Reachable from the Ledger (§7.8), which can be the first tab shown, so
            // the products' own data may never have been asked for.
            await model.loadIfNeeded()
        }
        .alert("Delete this product?", isPresented: $isConfirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let editing else { return }
                Task {
                    await model.delete(editing)
                    dismiss()
                }
            }
        } message: {
            Text("The purchase stays in your Ledger, receipt and all.")
        }
    }

    /// The Delete row, which lives below the form rather than in the header (§6.3).
    private var deleteRow: some View {
        CardContainer {
            Button { isConfirmingDelete = true } label: {
                Text("Delete product")
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.negativeRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tappableSurface()
            }
            .buttonStyle(.plain)
        }
    }

    /// Validates and saves, closing the sheet only on success (§7.11).
    ///
    /// With `onCommit` set the product is handed back rather than written: its purchase
    /// does not exist yet, and the repository would rightly refuse the orphan.
    private func save() {
        if let onCommit {
            guard let product = form.commit() else { return }
            onCommit(product)
            dismiss()
            return
        }
        Task {
            if await model.save(form) { dismiss() }
        }
    }
}
