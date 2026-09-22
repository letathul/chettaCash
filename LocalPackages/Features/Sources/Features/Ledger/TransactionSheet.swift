import SwiftUI
import Domain

/// What the series scope prompt is about to do (§4.5).
enum SeriesAction: Identifiable {
    /// Saving edited values.
    case edit
    /// Removing the occurrence.
    case delete

    /// The case's identity, for `sheet(item:)`.
    var id: String {
        switch self {
        case .edit: return "edit"
        case .delete: return "delete"
        }
    }
}

/// Add and Edit Transaction (§7.8, §6.3, §7.11).
///
/// A `Cancel / Title / Save` header with no back chevron and no bottom Save button.
/// Add is `interactiveDismissDisabled`, so only Cancel or Save closes it; Edit keeps
/// standard swipe-to-dismiss and gains a Delete row below the form.
struct TransactionSheet: View {
    /// The screen's view model.
    let model: LedgerViewModel
    /// The transaction being edited, or `nil` when adding.
    let editing: Domain.Transaction?

    /// Dismisses the sheet.
    @Environment(\.dismiss) var dismiss
    /// The editable form state.
    @State var form: TransactionFormState
    /// Whether the delete confirmation is showing (§7.11).
    @State var isConfirmingDelete = false
    /// Whether the Add Product form is showing for this purchase (§7.8).
    @State var isAddingProduct = false
    /// The product whose Edit form is showing.
    @State var editingProduct: Domain.Product?
    /// Reads a photographed receipt (§9.7).
    @State var scanner = ReceiptScanner()
    /// What the last scan found, resolved against the user's data, or `nil` before one
    /// has run.
    @State var scanPrefill: ReceiptPrefill?
    /// The scanned image to store against this transaction, if any.
    @State var receiptImageData: Data?
    /// The in-flight encode of a just-captured photo, if one is running.
    ///
    /// Held so Save can wait for it. Without the handle there is a sub-second window,
    /// between the photo arriving and its bytes being ready, in which a save would
    /// commit the transaction with no receipt attached.
    @State var attachingReceipt: Task<Void, Never>?
    /// Which action the series scope prompt is collecting a scope for.
    @State var pendingSeriesAction: SeriesAction?
    /// Which field holds the keyboard.
    @FocusState var focusedField: TransactionField?

    /// Creates the sheet.
    /// - Parameters:
    ///   - model: The screen's view model.
    ///   - editing: The transaction being edited, or `nil` when adding.
    init(model: LedgerViewModel, editing: Domain.Transaction?) {
        self.model = model
        self.editing = editing
        if let editing {
            _form = State(initialValue: TransactionFormState(
                editing: editing,
                counterpartAccountID: model.counterpartAccountID(for: editing)
            ))
        } else {
            _form = State(initialValue: TransactionFormState(
                accountID: model.selectableAccounts.first?.id
            ))
        }
    }

    /// Whether this sheet is editing rather than adding.
    var isEditing: Bool { editing != nil }

    /// The view body.
    var body: some View {
        NavigationStack {
            ScrollView {
                formContent.padding(16)
            }
            .background(Palette.appBackground)
            .scrollDismissesKeyboard(.interactively)
            .keyboardToolbar($focusedField) { addProductButton }
            .navigationTitle(isEditing ? "Edit Transaction" : "Add Transaction")
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
        .autoFocus($focusedField, on: .amount)
        .task { await loadProducts() }
        .sheet(isPresented: $isAddingProduct, onDismiss: refreshProducts) {
            addProductSheet
        }
        .sheet(item: $editingProduct, onDismiss: refreshProducts) { product in
            editProductSheet(product)
        }
        .sheet(item: $pendingSeriesAction) { action in
            SeriesScopeSheet(isDelete: action == .delete) { scope in
                applySeriesScope(action, scope: scope)
            }
        }
        .alert("Delete this transaction?", isPresented: $isConfirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let editing else { return }
                Task {
                    await model.delete(editing)
                    dismiss()
                }
            }
        } message: {
            Text(form.isExistingTransfer
                 ? "Both sides of this transfer will be removed."
                 : "This cannot be undone.")
        }
    }

    /// How a product sheet hands its product back.
    ///
    /// `nil` on Edit, where the purchase exists and the product sheet writes straight
    /// to the store. On Add there is no row to point at yet, so the product is held
    /// here until the transaction is saved (§7.8).
    private var productCommit: ((Domain.Product) -> Void)? {
        isEditing ? nil : { product in recordProduct(product) }
    }

    /// The Add Product sheet for this purchase.
    @ViewBuilder
    private var addProductSheet: some View {
        if let productsModel = model.productsModel {
            ProductSheet(
                model: productsModel,
                purchase: provisionalPurchase,
                sortIndex: form.products.count,
                onCommit: productCommit
            )
        }
    }

    /// The Edit Product sheet for one of this purchase's products.
    /// - Parameter product: The product being edited.
    /// - Returns: The sheet.
    @ViewBuilder
    private func editProductSheet(_ product: Domain.Product) -> some View {
        if let productsModel = model.productsModel {
            ProductSheet(
                model: productsModel,
                purchase: provisionalPurchase,
                editing: product,
                onCommit: productCommit
            )
        }
    }

    /// The form's stacked cards.
    ///
    /// Extracted from `body` so the type checker has a smaller expression to solve;
    /// inline it and the whole sheet stops compiling in reasonable time.
    @ViewBuilder
    private var formContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            modePicker
            amountField
            scanRow
            receiptRow
            detailsCard
            if form.mode != .transfer { extrasCard }
            productsCard
            memoCard
            if isEditing { deleteRow }
        }
    }

    /// Category or transfer destination, account, date and merchant.
    private var detailsCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                if form.mode == .transfer {
                    transferFields
                } else {
                    categoryField
                }
                accountField
                datePicker
                locationField
            }
        }
    }

    /// The Expense / Income / Transfer segmented control.
    private var modePicker: some View {
        SegmentedPillControl(
            options: TransactionFormMode.allCases,
            selection: Binding(
                get: { form.mode },
                set: { newMode in
                    form.mode = newMode
                    // Categories do not carry across contexts, and transfers have none.
                    form.categoryID = nil
                }
            ),
            display: \.title
        )
        .disabled(form.isExistingTransfer)
    }

    /// The large centred amount entry (§7.8).
    ///
    /// Handed the bound text rather than the form: this body must not read `amountText`,
    /// or every character typed would invalidate the whole sheet again.
    private var amountField: some View {
        AmountField(
            text: $form.amountText,
            mode: form.mode,
            hasAttemptedSave: form.hasAttemptedSave,
            focus: $focusedField
        )
    }

    /// The "Add Product" action pinned above the keyboard (§7.8).
    ///
    /// Same guard as ``productsCard``: a transfer contains no products, and without a
    /// Products view model there is nowhere to put one. It opens the same Add Product
    /// form the card's chip does — a product is a thing in its own right, with a
    /// category, dates and billing, never a name typed into a chip.
    @ViewBuilder
    private var addProductButton: some View {
        if form.mode != .transfer, model.productsModel != nil {
            Button {
                // Let the keyboard fall before the sheet rises; the product form asks
                // for focus itself once it has appeared.
                focusedField = nil
                isAddingProduct = true
            } label: {
                Label("Add Product", systemImage: "plus.circle")
                    .font(Typography.rowSecondary.weight(.semibold))
            }
        }
    }

    /// The memo field, which stays optional in every mode.
    private var memoCard: some View {
        MemoCard(memo: $form.memo, focus: $focusedField)
    }

    /// The Delete row, which lives below the form rather than in the header (§6.3).
    private var deleteRow: some View {
        CardContainer {
            Button(action: beginDelete) {
                Text("Delete transaction")
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.negativeRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tappableSurface()
            }
            .buttonStyle(.plain)
        }
    }
}
