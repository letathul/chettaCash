import SwiftUI
import Domain

/// Saving and deleting from the transaction sheet, including the series scope
/// prompt a recurring row needs (§4.5, §7.11).
///
/// Split from ``TransactionSheet`` to keep each file within the 300-line limit.
extension TransactionSheet {
    /// Validates and saves, closing the sheet only on success (§7.11).
    ///
    /// A row belonging to a live series asks for scope first (§4.5).
    func save() {
        if let editing, model.seriesRule(for: editing) != nil {
            guard form.attemptSave() else { return }
            pendingSeriesAction = .edit
            return
        }
        Task {
            // A photo captured moments ago may still be encoding. Waiting for it is what
            // lets Save stay live during a scan: the save carries the receipt either way,
            // and only the pre-fill the user chose not to wait for is given up.
            await attachingReceipt?.value
            if await model.save(form, receiptImageData: receiptImageData) { dismiss() }
        }
    }

    /// Starts a delete, asking for scope first when the row belongs to a series.
    func beginDelete() {
        if let editing, model.seriesRule(for: editing) != nil {
            pendingSeriesAction = .delete
        } else {
            isConfirmingDelete = true
        }
    }

    /// Applies the chosen scope to the pending series action.
    /// - Parameters:
    ///   - action: Whether the user was editing or deleting.
    ///   - scope: How far the change reaches.
    func applySeriesScope(_ action: SeriesAction, scope: SeriesScope) {
        guard let editing, let rule = model.seriesRule(for: editing) else { return }
        Task {
            switch action {
            case .edit:
                await model.applySeriesEdit(form, rule: rule, target: editing, scope: scope)
            case .delete:
                await model.applySeriesDelete(rule: rule, target: editing, scope: scope)
            }
            dismiss()
        }
    }
}
