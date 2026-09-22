import Foundation
import Domain

/// One product card, with every string already rendered (§7.3).
///
/// Built once per reload, filter change or sort change by ``ProductsViewModel``. The
/// card used to derive all of this in its own `body`: two linear lookups, a currency
/// format, up to two date formats and six `Calendar.current` constructions — per card,
/// on every keystroke in the search field above it.
struct ProductCardModel: Identifiable, Hashable {
    /// The card's identity, which is the product's.
    let id: UUID
    /// The product's name.
    let name: String
    /// The "Category · Merchant" line.
    let purchaseLine: String
    /// The line describing the nearest relevant date.
    let statusLine: String
    /// Whether that date is within a week, which tints the line amber.
    let isUrgent: Bool
    /// The billing subline, for products that bill on a schedule.
    let billingLine: String?
    /// Whether the purchase carries a receipt image.
    let hasReceipt: Bool
    /// Which tint the icon takes.
    let accent: ProductAccent
    /// The product a tap opens for editing.
    let product: Domain.Product
}

/// What a product card's icon is signalling (§7.3).
enum ProductAccent: Hashable {
    /// On a free trial. Reads amber.
    case trial
    /// Under warranty. Reads green.
    case warranty
    /// Neither. Reads in the brand colour.
    case plain

    /// The SF Symbol drawn inside the icon.
    var glyph: String {
        switch self {
        case .trial: return "hourglass"
        case .warranty: return "checkmark.shield.fill"
        case .plain: return "shippingbox.fill"
        }
    }

    /// Which accent a product takes, trial winning over warranty.
    /// - Parameter product: The product to describe.
    /// - Returns: The accent.
    static func of(_ product: Domain.Product) -> ProductAccent {
        if product.hasTrial { return .trial }
        if product.hasWarranty { return .warranty }
        return .plain
    }
}

/// One selectable purchase in the picker (§7.8).
struct PurchaseRowModel: Identifiable, Hashable {
    /// The row's identity, which is the transaction's.
    let id: UUID
    /// The merchant, or a stand-in when the purchase has none.
    let title: String
    /// The "date · account · product count" line.
    let subtitle: String
    /// The currency-formatted amount.
    let amountText: String
    /// Whether the purchase carries a receipt image.
    let hasReceipt: Bool
    /// Lowercased merchant, so searching does not lowercase per keystroke per row.
    let searchKey: String
    /// The purchase itself, handed to the product form.
    let purchase: Domain.Transaction
}
