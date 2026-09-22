import Foundation
import Domain

/// Building the read-only transaction detail (§7.4).
///
/// Tapping a row opens this rather than the edit form: browsing history should not put
/// the user one stray keystroke away from rewriting a past transaction. Editing is an
/// explicit act from here.
///
/// Split from ``LedgerViewModel`` to keep each file within the 300-line limit.
extension LedgerViewModel {

    /// Renders one transaction's detail screen.
    ///
    /// A transfer is described from the leg the user opened, naming the account on the
    /// other side — the two legs are one movement of money, not two entries (§4.3).
    ///
    /// - Parameter transaction: The transaction to describe.
    /// - Returns: The detail model.
    func detail(for transaction: Domain.Transaction) -> TransactionDetailModel {
        let item = detailItem(for: transaction)
        let currencyCode = settings.currencyCode
        let row = row(for: item, currencyCode: currencyCode)
        return TransactionDetailModel(
            id: transaction.id,
            title: row.title,
            typeLabel: typeLabel(for: transaction),
            amountText: row.amountText,
            tone: row.tone,
            glyph: row.glyph,
            avatar: row.avatar,
            rows: detailRows(for: transaction),
            tags: transaction.tags,
            receiptName: transaction.receiptFileID == nil
                ? nil
                : (transaction.receiptFileName ?? "Receipt"),
            products: detailProducts(for: transaction),
            seriesName: seriesRule(for: transaction)?.name,
            isEditable: isEditable(item)
        )
    }

    /// The row the detail renders its headline and amount from.
    ///
    /// A transfer leg is paired with its partner so the title reads "Chequing → Visa";
    /// everything else stands alone.
    ///
    /// - Parameter transaction: The transaction opened.
    /// - Returns: The item to render.
    private func detailItem(for transaction: Domain.Transaction) -> LedgerItem {
        guard let groupID = transaction.transferGroupID,
              let outLeg = allTransactions.first(where: {
                  $0.transferGroupID == groupID && $0.type == .transferOut
              }),
              let inLeg = allTransactions.first(where: {
                  $0.transferGroupID == groupID && $0.type == .transferIn
              })
        else { return .single(transaction) }
        return .transfer(outLeg: outLeg, inLeg: inLeg)
    }

    /// What kind of entry this is, in words.
    /// - Parameter transaction: The transaction to describe.
    /// - Returns: The label.
    private func typeLabel(for transaction: Domain.Transaction) -> String {
        switch transaction.type {
        case .expense: return "Expense"
        case .income: return "Income"
        case .adjustment: return "Balance adjustment"
        case .transferIn, .transferOut: return "Transfer"
        }
    }

    /// The labelled facts, omitting every field the user left blank.
    /// - Parameter transaction: The transaction to describe.
    /// - Returns: The rows to list.
    private func detailRows(for transaction: Domain.Transaction) -> [TransactionDetailRow] {
        var rows: [TransactionDetailRow] = []
        if transaction.transferGroupID == nil {
            rows.append(TransactionDetailRow(
                label: "Category",
                value: category(id: transaction.categoryID)?.label ?? "Uncategorised"
            ))
        }
        rows.append(TransactionDetailRow(
            label: transaction.type == .transferOut ? "From" : "Account",
            value: account(id: transaction.accountID)?.name ?? "No account"
        ))
        if transaction.transferGroupID != nil,
           let counterpart = account(id: counterpartAccountID(for: transaction))?.name {
            rows.append(TransactionDetailRow(
                label: transaction.type == .transferOut ? "To" : "From",
                value: counterpart
            ))
        }
        rows.append(TransactionDetailRow(
            label: "Date",
            value: transaction.date.formatted(
                .dateTime.weekday(.abbreviated).day().month(.abbreviated).year()
                    .hour().minute()
            )
        ))
        if let location = transaction.location, !location.isEmpty {
            rows.append(TransactionDetailRow(label: "Location", value: location))
        }
        if let memo = transaction.memo, !memo.isEmpty {
            rows.append(TransactionDetailRow(label: "Note", value: memo))
        }
        return rows
    }

    /// The products this purchase contained, in display order (§7.8).
    /// - Parameter transaction: The purchase to describe.
    /// - Returns: The products, or empty when there are none.
    private func detailProducts(
        for transaction: Domain.Transaction
    ) -> [TransactionDetailProduct] {
        guard let productsModel else { return [] }
        return productsModel.products(for: transaction.id).map { product in
            TransactionDetailProduct(
                id: product.id,
                name: product.name,
                detail: productDetail(product, in: productsModel),
                glyph: ProductAccent.of(product).glyph,
                product: product
            )
        }
    }

    /// What a product row says under its name.
    /// - Parameters:
    ///   - product: The product to describe.
    ///   - productsModel: The model resolving its category.
    /// - Returns: The subtitle.
    private func productDetail(
        _ product: Domain.Product,
        in productsModel: ProductsViewModel
    ) -> String {
        var parts: [String] = []
        if let label = productsModel.category(id: product.categoryID)?.label {
            parts.append(label)
        }
        if product.hasTrial { parts.append("Free trial") }
        if product.hasWarranty { parts.append("Warranty") }
        if product.recurringRuleID != nil { parts.append("Subscription") }
        return parts.isEmpty ? "No dates tracked" : parts.joined(separator: " · ")
    }
}
