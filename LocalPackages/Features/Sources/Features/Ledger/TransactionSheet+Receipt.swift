import SwiftUI
import Domain

/// The transaction sheet's receipt rows (§7.8, §9.7).
///
/// The receipt belongs here rather than on a product: one till receipt covers whatever
/// that purchase contained, and the scan reads back exactly the fields this form has —
/// amount, merchant, date and time, location, category and the account it was paid from.
///
/// Split from ``TransactionSheet`` to keep each file within the 300-line limit.
extension TransactionSheet {

    /// The Scan receipt row, hidden in transfer mode (§9.7).
    @ViewBuilder
    var scanRow: some View {
        if form.mode != .transfer {
            ReceiptCaptureView(prefill: scanPrefill, phase: scanner.phase) { image in
                Task { await scan(image) }
            }
        }
    }

    /// The attached receipt, with a way to look at it (§9.3).
    @ViewBuilder
    var receiptRow: some View {
        if form.mode != .transfer, form.receiptFileID != nil || receiptImageData != nil {
            ReceiptAttachmentView(
                fileID: form.receiptFileID,
                pendingData: receiptImageData,
                storage: model.receiptStorage,
                onRemove: removeReceipt
            )
        }
    }

    /// Reads a captured photo into the form.
    ///
    /// On Edit the fields are left alone: the user has already corrected them, and
    /// re-reading the receipt would undo that. The image itself is always kept.
    ///
    /// **The photo is attached before it is read**, and the two run concurrently.
    /// Encoding the bytes takes a fraction of what the readers take, so they are in
    /// place long before anyone could reach Save — which is what lets Save stay live
    /// through a scan instead of being disabled. Saving mid-scan then costs only the
    /// pre-fill the user did not wait for, never the receipt itself.
    ///
    /// - Parameter image: The captured photo.
    func scan(_ image: UIImage) async {
        attachingReceipt = Task { @MainActor in
            let data = await ReceiptScanner.storableDataOffMainActor(for: image)
            // The encode runs detached and does not itself stop on cancellation, so the
            // check belongs here: without it, removing the receipt while the bytes were
            // still encoding would see them land afterwards and the receipt come back.
            guard !Task.isCancelled else { return }
            receiptImageData = data
        }
        let result = await scanner.scan(image, context: scanContext)
        await attachingReceipt?.value

        let prefill = ReceiptPrefillBuilder.prefill(
            from: result,
            resolvedAgainst: ReceiptResolutionContext(
                accounts: model.accounts,
                categories: model.categories,
                history: model.allTransactions,
                categoryContext: form.mode.categoryContext ?? .expense
            )
        )
        scanPrefill = prefill
        guard !prefill.isEmpty, editing == nil else { return }
        apply(prefill)
    }

    /// What the reader needs to know beyond the receipt (§9.7).
    ///
    /// The category labels come from whatever this form's picker is actually offering,
    /// so the reader can only ever name a category the user really has — and switching
    /// the sheet between Expense and Income changes what it may suggest.
    var scanContext: ReceiptScanContext {
        let context = form.mode.categoryContext ?? .expense
        return ReceiptScanContext(
            categoryLabels: model.categories
                .filter { $0.context == context && !$0.isArchived }
                .filter { !SystemCategoryID.isSystem($0.id) }
                .map(\.label)
        )
    }

    /// Detaches the receipt.
    ///
    /// Only the form is changed here. The stored file is deleted on save, so cancelling
    /// out of the sheet leaves the receipt where it was.
    func removeReceipt() {
        attachingReceipt?.cancel()
        attachingReceipt = nil
        receiptImageData = nil
        form.receiptFileID = nil
        form.receiptFileName = nil
        form.receiptChecksum = nil
        form.receiptUploadState = .none
        scanPrefill = nil
    }

    /// Pre-fills the form from a scan (§9.7).
    ///
    /// Every field stays editable, and a field the scan could not read is left as it
    /// was. Nothing here is a commitment — the user still has to press Save.
    ///
    /// Tags are the deliberate omission. They are unlimited free text (§4.8), so writing
    /// them automatically would grow a vocabulary nobody chose; they are offered as
    /// chips under the tag field instead, and reach the form only when tapped.
    ///
    /// - Parameter prefill: What the scan found, resolved against the user's own data.
    func apply(_ prefill: ReceiptPrefill) {
        if let merchant = prefill.scan.merchant { form.merchant = merchant }
        if let amountCents = prefill.scan.amountCents {
            form.amountText = MoneyInput.magnitudeText(fromCents: amountCents)
        }
        if let date = prefill.scan.date { form.date = date }
        if let location = prefill.scan.location { form.location = location }
        if let categoryID = prefill.categoryID { form.categoryID = categoryID }
        if let accountID = prefill.accountID { form.accountID = accountID }
    }

    /// Adds a suggested tag the user tapped (§4.8).
    /// - Parameter tag: The tag to add.
    func acceptTag(_ tag: String) {
        guard !form.tags.contains(where: { $0.lowercased() == tag.lowercased() }) else { return }
        form.tags.append(tag)
    }
}

/// Keeping the sheet's product list in step with the store (§7.8).
extension TransactionSheet {

    /// Loads this purchase's products when editing one that already exists.
    func loadProducts() async {
        guard let editing, let productsModel = model.productsModel else { return }
        await productsModel.loadIfNeeded()
        form.products = productsModel.products(for: editing.id)
    }

    /// Re-reads the product list after a product sheet closes.
    ///
    /// Only meaningful on Edit: there the product sheet wrote straight to the store, so
    /// the form's copy is stale. On Add nothing was written and the pending list is
    /// already correct.
    func refreshProducts() {
        guard let editing, let productsModel = model.productsModel else { return }
        form.products = productsModel.products(for: editing.id)
    }
}
