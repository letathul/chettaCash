import Foundation
import Domain

/// One transaction's detail screen, with every string already rendered (§7.4, §7.8).
///
/// Built by ``LedgerViewModel/detail(for:)`` rather than derived in the view's `body`,
/// the way ``LedgerRowModel`` is: the screen does no currency formatting, no date
/// formatting and no account or category lookup of its own.
struct TransactionDetailModel: Identifiable, Hashable {
    /// The screen's identity, which is the transaction's.
    let id: UUID
    /// The headline — a merchant, or "Chequing → Visa" for a transfer.
    let title: String
    /// What kind of entry this is: Expense, Income, Transfer or Adjustment.
    let typeLabel: String
    /// The signed, currency-formatted amount.
    let amountText: String
    /// Which palette entry the amount reads in.
    let tone: AmountTone
    /// The SF Symbol drawn inside the avatar.
    let glyph: String
    /// The avatar's tint.
    let avatar: RowAvatar
    /// The labelled facts: category, account, date and anything else that was filled in.
    let rows: [TransactionDetailRow]
    /// The transaction's tags, in the order they were entered.
    let tags: [String]
    /// The attached receipt's file name, or `nil` when there is no receipt.
    let receiptName: String?
    /// The products this purchase contained (§7.8).
    let products: [TransactionDetailProduct]
    /// The recurring series this occurrence belongs to, if it still belongs to one.
    let seriesName: String?
    /// Whether the transaction may be edited.
    ///
    /// `false` for a transaction touching a closed account (§4.7). The screen still
    /// opens — history stays readable — but it offers no Edit button.
    let isEditable: Bool
}

/// One labelled fact on the detail screen.
struct TransactionDetailRow: Identifiable, Hashable {
    /// The field's name, such as "Account".
    let label: String
    /// The rendered value.
    let value: String

    /// The row's identity, which is its label — each appears at most once.
    var id: String { label }
}

/// One product listed on the detail screen (§7.8).
struct TransactionDetailProduct: Identifiable, Hashable {
    /// The product's identifier.
    let id: UUID
    /// The product's name.
    let name: String
    /// What it is tracking: a category, a trial, a warranty, a subscription.
    let detail: String
    /// The SF Symbol describing that.
    let glyph: String
    /// The product itself, handed to the product form when the row is tapped.
    let product: Domain.Product
}
