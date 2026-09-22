import Foundation
import Testing
@testable import Domain

/// A product is always part of a purchase, and reads its money off it (§7.8).
@Suite("Product listings")
struct ProductListingTests {

    /// The moment every test evaluates against.
    private var now: Date { Date(timeIntervalSince1970: 1_789_000_000) }

    /// A date offset from ``now`` by whole days.
    /// - Parameter days: Days to offset.
    /// - Returns: The offset date.
    private func day(_ days: Int) -> Date {
        now.addingTimeInterval(Double(days) * 86_400)
    }

    /// Builds a purchase.
    /// - Parameters:
    ///   - merchant: Where it was bought.
    ///   - cents: What it cost.
    ///   - date: When it happened.
    ///   - accountID: The account it was paid from.
    ///   - receipt: Whether it carries a receipt image.
    /// - Returns: The transaction.
    private func purchase(
        merchant: String = "Shop",
        cents: Int = 1_000,
        date: Date? = nil,
        accountID: UUID? = nil,
        receipt: Bool = false
    ) -> Transaction {
        Transaction(
            amountCents: cents, type: .expense, accountID: accountID,
            date: date ?? day(-10), merchant: merchant,
            receiptFileID: receipt ? "Receipts/2026/2026-09/r.jpg" : nil
        )
    }

    /// Builds a listing.
    /// - Parameters:
    ///   - name: The product name.
    ///   - purchase: The purchase it belongs to.
    /// - Returns: The listing.
    private func listing(_ name: String, purchase: Transaction) -> ProductListing {
        ProductListing.make(
            product: Product(transactionID: purchase.id, name: name), purchase: purchase
        )
    }

    @Test("A product cannot be built without a purchase")
    func productAlwaysHasATransaction() {
        // Not an assertion about a value so much as about the type: `transactionID` has
        // no default, so "a product with no purchase" does not compile.
        let bought = purchase()
        let product = Product(transactionID: bought.id, name: "Lamp")

        #expect(product.transactionID == bought.id)
    }

    @Test("A listing reads its money, date and account off the purchase")
    func listingTakesFactsFromThePurchase() {
        let account = UUID()
        let bought = purchase(
            merchant: "Sony Store", cents: 24_999, date: day(-3),
            accountID: account, receipt: true
        )

        let result = listing("Headphones", purchase: bought)

        #expect(result.amountCents == 24_999, "the whole purchase, not a per-product share")
        #expect(result.merchant == "Sony Store")
        #expect(result.purchaseDate == day(-3))
        #expect(result.accountID == account)
        #expect(result.hasReceipt)
    }

    @Test("One purchase's products all report the same receipt")
    func oneReceiptCoversEveryProduct() {
        let bought = purchase(merchant: "Homeware Co", cents: 12_400, receipt: true)

        let lamp = listing("Desk Lamp", purchase: bought)
        let rug = listing("Hallway Rug", purchase: bought)

        #expect(lamp.hasReceipt && rug.hasReceipt)
        #expect(lamp.product.transactionID == rug.product.transactionID)
    }
}
