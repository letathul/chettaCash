import Foundation

/// How the product list is ordered (§7.3).
public enum ProductSort: String, CaseIterable, Identifiable, Sendable {
    /// Ascending by the nearest relevant date — trial end or warranty expiry.
    case soonest
    /// Descending by purchase date.
    case newest
    /// Alphabetical by name.
    case name
    /// Alphabetical by the merchant the product was bought from.
    case merchant

    /// The case's identity, for `ForEach`.
    public var id: String { rawValue }
}

/// Which products the list shows (§7.3).
public enum ProductStatus: String, CaseIterable, Identifiable, Sendable {
    /// Every product.
    case all
    /// Products on a free trial that has not yet ended.
    case activeTrials
    /// Products under a warranty that has not yet expired.
    case warranties
    /// Products billed by a recurring rule.
    case subscriptions
    /// Products whose trial or warranty has already run out.
    case expired

    /// The case's identity, for `ForEach`.
    public var id: String { rawValue }
}

/// A product paired with the purchase facts that live on its transaction (§7.8).
///
/// A ``Product`` holds none of the money, the account or the date — those belong to the
/// purchase. Joining the two here keeps filtering and sorting in Domain, where they can
/// be tested, instead of scattered across the view.
public struct ProductListing: Identifiable, Hashable, Sendable {
    /// The product.
    public var product: Product
    /// The merchant the purchase was made from.
    public var merchant: String
    /// When the purchase happened.
    public var purchaseDate: Date
    /// The account the purchase was made with.
    public var accountID: UUID?
    /// The whole purchase in cents — not this product's share, which does not exist.
    public var amountCents: Int
    /// Whether the purchase carries a receipt image.
    public var hasReceipt: Bool

    /// The product's identity, which is the listing's.
    public var id: UUID { product.id }

    /// Creates a listing.
    /// - Parameters:
    ///   - product: The product.
    ///   - merchant: The merchant the purchase was made from.
    ///   - purchaseDate: When the purchase happened.
    ///   - accountID: The account the purchase was made with.
    ///   - amountCents: The whole purchase in cents.
    ///   - hasReceipt: Whether the purchase carries a receipt image.
    public init(
        product: Product,
        merchant: String = "",
        purchaseDate: Date = .now,
        accountID: UUID? = nil,
        amountCents: Int = 0,
        hasReceipt: Bool = false
    ) {
        self.product = product
        self.merchant = merchant
        self.purchaseDate = purchaseDate
        self.accountID = accountID
        self.amountCents = amountCents
        self.hasReceipt = hasReceipt
    }

    /// Builds a listing by joining a product to the purchase it belongs to.
    /// - Parameters:
    ///   - product: The product.
    ///   - purchase: The transaction the product was part of.
    /// - Returns: The listing.
    public static func make(product: Product, purchase: Transaction) -> ProductListing {
        ProductListing(
            product: product,
            merchant: purchase.merchant,
            purchaseDate: purchase.date,
            accountID: purchase.accountID,
            amountCents: purchase.amountCents,
            hasReceipt: purchase.receiptFileID != nil
        )
    }
}

/// The attributes the product list filters on (§7.3).
///
/// Shaped like ``LedgerFilter``: a value type whose criteria are ANDed in one
/// ``apply(to:reference:calendar:)`` pass, so the view holds one filter object and the
/// rules stay testable.
public struct ProductFilter: Equatable, Sendable {
    /// The live search term, matched against product name and merchant.
    public var search: String
    /// Which products to include.
    public var status: ProductStatus
    /// The category to restrict to, or `nil` for every category.
    public var categoryID: UUID?
    /// Tags a product must carry **all** of, or empty for no tag restriction.
    public var tags: Set<String>
    /// The account to restrict to, or `nil` for every account.
    public var accountID: UUID?
    /// The purchase-date window.
    public var period: LedgerPeriod
    /// Whether to show only products whose purchase has a receipt.
    public var receiptsOnly: Bool

    /// Creates a filter.
    /// - Parameters:
    ///   - search: The search term.
    ///   - status: Which products to include.
    ///   - categoryID: The category to restrict to.
    ///   - tags: Tags a product must carry all of.
    ///   - accountID: The account to restrict to.
    ///   - period: The purchase-date window.
    ///   - receiptsOnly: Whether to require a receipt.
    public init(
        search: String = "",
        status: ProductStatus = .all,
        categoryID: UUID? = nil,
        tags: Set<String> = [],
        accountID: UUID? = nil,
        period: LedgerPeriod = .allTime,
        receiptsOnly: Bool = false
    ) {
        self.search = search
        self.status = status
        self.categoryID = categoryID
        self.tags = tags
        self.accountID = accountID
        self.period = period
        self.receiptsOnly = receiptsOnly
    }

    /// Whether any criterion is narrowing the list.
    ///
    /// Lets a view tell "you own nothing yet" apart from "nothing matched" (§7.0).
    public var isNarrowing: Bool {
        self != ProductFilter()
    }

    /// Applies every criterion at once.
    ///
    /// Search is a live, case-insensitive substring match on the product name or the
    /// merchant. Tags are ANDed: selecting two tags shows products carrying both.
    ///
    /// - Parameters:
    ///   - listings: The products to filter.
    ///   - reference: The moment deciding the period window and whether a date has passed.
    ///   - calendar: The calendar deciding month boundaries.
    /// - Returns: The matching products.
    public func apply(
        to listings: [ProductListing],
        reference: Date = .now,
        calendar: Calendar = .current
    ) -> [ProductListing] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = period.dateRange(containing: reference, calendar: calendar)
        return listings.filter { listing in
            guard ProductBrowser.matches(listing, status: status, now: reference) else {
                return false
            }
            if let categoryID, listing.product.categoryID != categoryID { return false }
            if let accountID, listing.accountID != accountID { return false }
            if receiptsOnly, !listing.hasReceipt { return false }
            if let range, !range.contains(listing.purchaseDate) { return false }
            if !tags.isEmpty, !tags.isSubset(of: Set(listing.product.tags)) { return false }
            guard !term.isEmpty else { return true }
            return listing.product.name.range(of: term, options: .caseInsensitive) != nil
                || listing.merchant.range(of: term, options: .caseInsensitive) != nil
        }
    }
}

/// Orders the product list and answers status questions about a product (§7.3).
public enum ProductBrowser {

    /// Orders products by the chosen sort.
    ///
    /// Under ``ProductSort/soonest`` a product with no relevant date sorts last rather
    /// than jumping to the front on a missing value.
    ///
    /// - Parameters:
    ///   - listings: The products to order.
    ///   - sort: The chosen ordering.
    /// - Returns: The ordered products.
    public static func sort(
        _ listings: [ProductListing],
        by sort: ProductSort
    ) -> [ProductListing] {
        switch sort {
        case .newest:
            return listings.sorted {
                $0.purchaseDate == $1.purchaseDate
                    ? $0.product.name < $1.product.name
                    : $0.purchaseDate > $1.purchaseDate
            }
        case .name:
            return listings.sorted {
                $0.product.name.localizedCaseInsensitiveCompare($1.product.name)
                    == .orderedAscending
            }
        case .merchant:
            return listings.sorted { left, right in
                let comparison = left.merchant.localizedCaseInsensitiveCompare(right.merchant)
                return comparison == .orderedSame
                    ? left.product.name < right.product.name
                    : comparison == .orderedAscending
            }
        case .soonest:
            return listings.sorted { left, right in
                switch (nearestDate(of: left.product), nearestDate(of: right.product)) {
                case let (lhs?, rhs?):
                    return lhs == rhs ? left.product.name < right.product.name : lhs < rhs
                case (nil, _?): return false
                case (_?, nil): return true
                case (nil, nil): return left.product.name < right.product.name
                }
            }
        }
    }

    /// The nearest trial-end or warranty-expiry date on a product.
    /// - Parameter product: The product to inspect.
    /// - Returns: The earlier of the two dates, or `nil` when it has neither.
    public static func nearestDate(of product: Product) -> Date? {
        let dates = [
            product.hasTrial ? product.trialEndsDate : nil,
            product.hasWarranty ? product.warrantyExpiresDate : nil
        ].compactMap { $0 }
        return dates.min()
    }

    /// Whether a product belongs in a status.
    /// - Parameters:
    ///   - listing: The product to test.
    ///   - status: The status being applied.
    ///   - now: The moment deciding whether a date has passed.
    /// - Returns: `true` when the product belongs.
    public static func matches(
        _ listing: ProductListing,
        status: ProductStatus,
        now: Date
    ) -> Bool {
        let product = listing.product
        switch status {
        case .all:
            return true
        case .activeTrials:
            guard product.hasTrial, let ends = product.trialEndsDate else { return false }
            return ends >= now
        case .warranties:
            guard product.hasWarranty else { return false }
            guard let expires = product.warrantyExpiresDate else { return true }
            return expires >= now
        case .subscriptions:
            return product.recurringRuleID != nil
        case .expired:
            let trialOver = product.hasTrial && (product.trialEndsDate.map { $0 < now } ?? false)
            let warrantyOver = product.hasWarranty
                && (product.warrantyExpiresDate.map { $0 < now } ?? false)
            return trialOver || warrantyOver
        }
    }
}
