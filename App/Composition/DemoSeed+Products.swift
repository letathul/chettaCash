import Foundation
import Domain

/// The demo products, and the purchases they hang off (§7.8).
///
/// Split from ``DemoSeed`` to keep each file within the 300-line limit.
extension DemoSeed {
    /// Inserts products covering a trial, a warranty, a free item and a subscription.
    ///
    /// Every one of them hangs off a purchase, because that is the only way a product
    /// exists (§7.8). The desk lamp deliberately shares its purchase with a second
    /// product, so one receipt covering several things has something to show; the
    /// hand-me-down chair is a zero-cost purchase, the free-product path.
    ///
    /// - Parameters:
    ///   - dependencies: The composition root to seed through.
    ///   - card: The credit card products are billed to.
    ///   - chequing: The spending account.
    static func seedProducts(
        _ dependencies: AppDependencies,
        card: Domain.Account,
        chequing: Domain.Account
    ) async {
        let purchases = await seedPurchases(dependencies, card: card, chequing: chequing)
        await seedProducts(dependencies, purchases: purchases)
    }

    /// The four demo purchases products hang off.
    struct DemoPurchases {
        /// A subscription's first charge.
        let streaming: Domain.Transaction
        /// A single warranted item.
        let headphones: Domain.Transaction
        /// One purchase holding two products.
        let homeware: Domain.Transaction
        /// A zero-cost purchase, the free-product path.
        let gift: Domain.Transaction
    }

    /// Writes the purchases, which must exist before any product can point at one.
    /// - Parameters:
    ///   - dependencies: The composition root to seed through.
    ///   - card: The credit card.
    ///   - chequing: The spending account.
    /// - Returns: The purchases.
    static func seedPurchases(
        _ dependencies: AppDependencies,
        card: Domain.Account,
        chequing: Domain.Account
    ) async -> DemoPurchases {
        let purchases = DemoPurchases(
            streaming: Domain.Transaction(
                amountCents: 1_499, type: .expense, accountID: card.id,
                date: day(-12), merchant: "Streaming Plus"
            ),
            headphones: Domain.Transaction(
                amountCents: 24_999, type: .expense, accountID: chequing.id,
                date: day(-60), merchant: "Sony Store"
            ),
            // One purchase, two products — the case the old one-receipt-per-product
            // model could not express.
            homeware: Domain.Transaction(
                amountCents: 12_400, type: .expense, accountID: chequing.id,
                date: day(-30), merchant: "Homeware Co"
            ),
            // Nothing was paid for this: a zero-cost purchase moves no balance.
            gift: Domain.Transaction(
                amountCents: 0, type: .expense, accountID: chequing.id,
                date: day(-8), merchant: "Hand-me-down"
            )
        )
        for purchase in [
            purchases.streaming, purchases.headphones, purchases.homeware, purchases.gift
        ] {
            try? await dependencies.transactions.save(purchase)
        }
        return purchases
    }

    /// Hangs the products off their purchases, and bills the subscription.
    /// - Parameters:
    ///   - dependencies: The composition root to seed through.
    ///   - purchases: The purchases to attach to.
    static func seedProducts(
        _ dependencies: AppDependencies,
        purchases: DemoPurchases
    ) async {
        let categories = (try? await dependencies.categories.allCategories()) ?? []
        func categoryID(_ label: String) -> UUID? {
            categories.first { $0.label == label && $0.context == .product }?.id
        }

        let trial = trialProduct(purchases: purchases, categoryID: categoryID("Subscription"))
        for product in demoProducts(
            purchases: purchases, trial: trial, categoryID: categoryID
        ) {
            try? await dependencies.products.save(product)
        }

        // A subscription that bills, so the billing subline has something to show.
        if let rule = ProductBilling.recurringRule(
            for: trial, purchase: purchases.streaming, frequency: .monthly
        ) {
            try? await dependencies.recurringRules.save(rule)
            var billed = trial
            billed.recurringRuleID = rule.id
            try? await dependencies.products.save(billed)
        }
    }

    /// The subscription product, which is also the one that bills.
    /// - Parameters:
    ///   - purchases: The purchases to attach to.
    ///   - categoryID: Its category.
    /// - Returns: The product.
    private static func trialProduct(
        purchases: DemoPurchases,
        categoryID: UUID?
    ) -> Domain.Product {
        var trial = Domain.Product(
            transactionID: purchases.streaming.id, name: "Streaming Plus",
            categoryID: categoryID
        )
        trial.hasTrial = true
        trial.trialEndsDate = day(2)
        trial.trialReminderLeadTime = .threeDaysBefore
        return trial
    }

    /// Every demo product, including the two sharing one purchase.
    /// - Parameters:
    ///   - purchases: The purchases to attach to.
    ///   - trial: The subscription product.
    ///   - categoryID: Resolves a category label to its identifier.
    /// - Returns: The products to write.
    private static func demoProducts(
        purchases: DemoPurchases,
        trial: Domain.Product,
        categoryID: (String) -> UUID?
    ) -> [Domain.Product] {
        var warranty = Domain.Product(
            transactionID: purchases.headphones.id, name: "Sony Headphones",
            categoryID: categoryID("Electronics"), tags: ["gift"]
        )
        warranty.hasWarranty = true
        warranty.warrantyExpiresDate = day(305)

        var chair = Domain.Product(
            transactionID: purchases.gift.id, name: "Office Chair",
            categoryID: categoryID("Home"), notes: "From a friend. Still under warranty."
        )
        chair.hasWarranty = true
        chair.warrantyExpiresDate = day(120)

        return [
            trial, warranty, chair,
            Domain.Product(
                transactionID: purchases.homeware.id, name: "Desk Lamp",
                categoryID: categoryID("Home"), sortIndex: 0
            ),
            Domain.Product(
                transactionID: purchases.homeware.id, name: "Hallway Rug",
                categoryID: categoryID("Home"), sortIndex: 1
            )
        ]
    }
}
