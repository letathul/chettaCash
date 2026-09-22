import Foundation
import Domain

/// Rebuilding the products' derived state (§7.3).
///
/// Split from ``ProductsViewModel`` to keep each file within the 300-line limit.
extension ProductsViewModel {

    /// Recomputes every derived value in one pass.
    ///
    /// Call after the data changes, after the filter or sort changes, and after the
    /// display currency changes — the card models carry formatted amounts and dates, so
    /// a currency switch invalidates them the way a filter change does.
    public func refresh() {
        accountsByID = Dictionary(
            accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        categoriesByID = Dictionary(
            categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        transactionsByID = Dictionary(
            transactions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        productsByTransactionID = Dictionary(grouping: products, by: \.transactionID)
            .mapValues { $0.sorted { $0.sortIndex < $1.sortIndex } }

        selectableAccounts = accounts.filter { !$0.isClosed }
        selectableCategories = categories.filter {
            $0.context == .product && !$0.isArchived && !SystemCategoryID.isSystem($0.id)
        }
        let usedCategoryIDs = Set(products.compactMap(\.categoryID))
        usedCategories = selectableCategories.filter { usedCategoryIDs.contains($0.id) }
        availableTags = Array(Set(products.flatMap(\.tags))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        listings = products.compactMap { product in
            guard let purchase = transactionsByID[product.transactionID] else { return nil }
            return Domain.ProductListing.make(product: product, purchase: purchase)
        }
        visibleListings = ProductBrowser.sort(filter.apply(to: listings), by: sort)
        isFilteredToZero = !products.isEmpty && visibleListings.isEmpty

        let currencyCode = settings.currencyCode
        // One calendar for the whole pass. `Calendar.current` builds a fresh value on
        // every access, and the status line used to ask for three of them per card.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        visibleCards = visibleListings.map {
            card(for: $0, currencyCode: currencyCode, calendar: calendar, today: today)
        }

        attachablePurchases = transactions
            .filter { $0.type == .expense || $0.type == .income }
            .sorted { $0.date > $1.date }
        purchaseRows = attachablePurchases.map { purchaseRow(for: $0, currencyCode: currencyCode) }
    }

    /// Renders one product card.
    /// - Parameters:
    ///   - listing: The product and its purchase.
    ///   - currencyCode: The display currency.
    ///   - calendar: The calendar deciding day boundaries.
    ///   - today: The start of today, against which dates are counted.
    /// - Returns: The card model.
    private func card(
        for listing: Domain.ProductListing,
        currencyCode: String,
        calendar: Calendar,
        today: Date
    ) -> ProductCardModel {
        let product = listing.product
        let daysUntil: (Date) -> Int = { date in
            calendar.dateComponents(
                [.day], from: today, to: calendar.startOfDay(for: date)
            ).day ?? 0
        }
        let urgency = ProductBrowser.nearestDate(of: product).map(daysUntil)
        return ProductCardModel(
            id: product.id,
            name: product.name,
            purchaseLine: purchaseLine(for: listing),
            statusLine: statusLine(for: listing, daysUntil: daysUntil),
            isUrgent: urgency.map { (0...7).contains($0) } ?? false,
            billingLine: billingLine(for: product, currencyCode: currencyCode),
            hasReceipt: listing.hasReceipt,
            accent: ProductAccent.of(product),
            product: product
        )
    }

    /// The category and where it was bought.
    /// - Parameter listing: The product and its purchase.
    /// - Returns: The line.
    private func purchaseLine(for listing: Domain.ProductListing) -> String {
        let label = category(id: listing.product.categoryID)?.label ?? "Uncategorised"
        let merchant = listing.merchant.isEmpty ? "No merchant" : listing.merchant
        return "\(label) · \(merchant)"
    }

    /// The status line, describing the nearest relevant date.
    /// - Parameters:
    ///   - listing: The product and its purchase.
    ///   - daysUntil: Counts whole days from today to a date.
    /// - Returns: The line.
    private func statusLine(
        for listing: Domain.ProductListing,
        daysUntil: (Date) -> Int
    ) -> String {
        let product = listing.product
        if product.hasTrial, let ends = product.trialEndsDate {
            let days = daysUntil(ends)
            if days < 0 {
                return "Trial ended \(ends.formatted(.dateTime.day().month(.abbreviated)))"
            }
            return days == 0 ? "Trial ends today" : "Trial ends in \(days) days"
        }
        if product.hasWarranty, let expires = product.warrantyExpiresDate {
            guard daysUntil(expires) >= 0 else { return "Warranty expired" }
            let date = expires.formatted(.dateTime.day().month(.abbreviated).year())
            return "Warranty until \(date)"
        }
        let bought = listing.purchaseDate.formatted(.dateTime.day().month(.abbreviated).year())
        return "Bought \(bought)"
    }

    /// The billing subline for products that bill on a schedule.
    /// - Parameters:
    ///   - product: The product to describe.
    ///   - currencyCode: The display currency.
    /// - Returns: The subline, or `nil` when the product does not bill.
    private func billingLine(for product: Domain.Product, currencyCode: String) -> String? {
        guard let rule = rulesByProductID[product.id] else { return nil }
        let amount = CurrencyFormatter.string(
            fromCents: rule.amountCents, currencyCode: currencyCode
        ) + "/" + rule.frequency.shortSuffix
        guard let accountName = account(id: rule.accountID)?.name else { return amount }
        return "\(amount) · \(accountName)"
    }

    /// Renders one row of the purchase picker (§7.8).
    /// - Parameters:
    ///   - purchase: The transaction the row offers.
    ///   - currencyCode: The display currency.
    /// - Returns: The row model.
    private func purchaseRow(
        for purchase: Domain.Transaction,
        currencyCode: String
    ) -> PurchaseRowModel {
        let date = purchase.date.formatted(.dateTime.day().month(.abbreviated).year())
        let accountName = account(id: purchase.accountID)?.name
        let head = accountName.map { "\(date) · \($0)" } ?? date
        let count = productsByTransactionID[purchase.id]?.count ?? 0
        let subtitle: String
        switch count {
        case 0: subtitle = head
        case 1: subtitle = "\(head) · 1 product"
        default: subtitle = "\(head) · \(count) products"
        }
        return PurchaseRowModel(
            id: purchase.id,
            title: purchase.merchant.isEmpty ? "Untitled purchase" : purchase.merchant,
            subtitle: subtitle,
            amountText: CurrencyFormatter.string(
                fromCents: purchase.amountCents, currencyCode: currencyCode
            ),
            hasReceipt: purchase.receiptFileID != nil,
            // Lowercased once here so the picker's search compares two plain strings
            // rather than running a locale-aware `range(of:options:)` per row per keystroke.
            searchKey: purchase.merchant.lowercased(),
            purchase: purchase
        )
    }
}
