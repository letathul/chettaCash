import Foundation
import Testing
@testable import Domain

/// Acceptance criteria for the product list and its Ledger links (§7.3, §7.7, §7.8).
@Suite("Products")
struct ProductTests {

    /// A fixed UTC calendar, so results never depend on the runner's locale.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// The moment every test evaluates against.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 12)) ?? .now
    }

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
            amountCents: cents,
            type: .expense,
            accountID: accountID,
            date: date ?? day(-10),
            merchant: merchant,
            receiptFileID: receipt ? "Receipts/2026/2026-09/r.jpg" : nil
        )
    }

    /// Builds a listing: a product joined to the purchase it came in.
    /// - Parameters:
    ///   - name: The product name.
    ///   - trialEnds: When a free trial ends, if any.
    ///   - warrantyExpires: When a warranty expires, if any.
    ///   - categoryID: Its category.
    ///   - tags: Its labels.
    ///   - subscription: Whether a rule bills for it.
    ///   - purchase: The purchase it belongs to.
    /// - Returns: The listing.
    private func listing(
        _ name: String,
        trialEnds: Date? = nil,
        warrantyExpires: Date? = nil,
        categoryID: UUID? = nil,
        tags: [String] = [],
        subscription: Bool = false,
        purchase: Transaction? = nil
    ) -> ProductListing {
        let bought = purchase ?? self.purchase()
        var product = Product(
            transactionID: bought.id, name: name, categoryID: categoryID, tags: tags
        )
        if let trialEnds {
            product.hasTrial = true
            product.trialEndsDate = trialEnds
        }
        if let warrantyExpires {
            product.hasWarranty = true
            product.warrantyExpiresDate = warrantyExpires
        }
        if subscription { product.recurringRuleID = UUID() }
        return ProductListing.make(product: product, purchase: bought)
    }

    /// Applies a filter at the fixed clock.
    /// - Parameters:
    ///   - filter: The filter to apply.
    ///   - listings: The products to filter.
    /// - Returns: The matching product names.
    private func names(_ filter: ProductFilter, _ listings: [ProductListing]) -> [String] {
        filter.apply(to: listings, reference: now, calendar: calendar).map(\.product.name)
    }

    // MARK: - Search and status (§7.3)

    @Test("Search matches a case-insensitive substring of the name")
    func searchIsSubstringAndCaseInsensitive() {
        let items = [listing("Netflix"), listing("Spotify"), listing("Notion")]

        #expect(names(ProductFilter(search: "net"), items) == ["Netflix"])
        #expect(names(ProductFilter(search: "TI"), items).sorted() == ["Notion", "Spotify"])
        #expect(names(ProductFilter(search: "  "), items).count == 3)
    }

    @Test("Search also matches the merchant the product came from")
    func searchMatchesMerchant() {
        let items = [
            listing("Headphones", purchase: purchase(merchant: "Sony Store")),
            listing("Lamp", purchase: purchase(merchant: "Homeware Co"))
        ]

        #expect(names(ProductFilter(search: "sony"), items) == ["Headphones"])
    }

    @Test("A search matching nothing returns empty rather than everything")
    func searchCanMatchNothing() {
        #expect(names(ProductFilter(search: "zzz"), [listing("Netflix")]).isEmpty)
    }

    @Test("Active trials exclude trials that have already ended")
    func activeTrialsStatus() {
        let items = [
            listing("Live", trialEnds: day(3)),
            listing("Expired", trialEnds: day(-3)),
            listing("Plain")
        ]

        #expect(names(ProductFilter(status: .activeTrials), items) == ["Live"])
    }

    @Test("The warranties status covers only warranties still running")
    func warrantiesStatus() {
        let items = [
            listing("Laptop", warrantyExpires: day(300)),
            listing("Phone", warrantyExpires: day(-30)),
            listing("Mug")
        ]

        #expect(names(ProductFilter(status: .warranties), items) == ["Laptop"])
    }

    @Test("Expired covers a lapsed trial or a lapsed warranty")
    func expiredStatus() {
        let items = [
            listing("Old trial", trialEnds: day(-3)),
            listing("Old warranty", warrantyExpires: day(-30)),
            listing("Live", trialEnds: day(3)),
            listing("Plain")
        ]

        #expect(names(ProductFilter(status: .expired), items).sorted()
                == ["Old trial", "Old warranty"])
    }

    @Test("Subscriptions covers products a rule bills for")
    func subscriptionsStatus() {
        let items = [listing("Streaming", subscription: true), listing("Lamp")]

        #expect(names(ProductFilter(status: .subscriptions), items) == ["Streaming"])
    }

    // MARK: - Attribute filters (§7.3)

    @Test("Category, account and receipt filters each narrow the list")
    func singleAttributeFilters() {
        let category = UUID()
        let account = UUID()
        let items = [
            listing("Matching", categoryID: category,
                    purchase: purchase(accountID: account, receipt: true)),
            listing("Other category", categoryID: UUID(),
                    purchase: purchase(accountID: account, receipt: true)),
            listing("Other account", categoryID: category,
                    purchase: purchase(accountID: UUID(), receipt: true)),
            listing("No receipt", categoryID: category,
                    purchase: purchase(accountID: account))
        ]

        #expect(names(ProductFilter(categoryID: category), items).sorted()
                == ["Matching", "No receipt", "Other account"])
        #expect(names(ProductFilter(accountID: account), items).sorted()
                == ["Matching", "No receipt", "Other category"])
        #expect(names(ProductFilter(receiptsOnly: true), items).sorted()
                == ["Matching", "Other account", "Other category"])
    }

    @Test("Selecting two tags narrows rather than widens")
    func tagsAreAnded() {
        let items = [
            listing("Both", tags: ["work", "gift"]),
            listing("One", tags: ["work"]),
            listing("None", tags: [])
        ]

        #expect(names(ProductFilter(tags: ["work"]), items).sorted() == ["Both", "One"])
        #expect(names(ProductFilter(tags: ["work", "gift"]), items) == ["Both"])
    }

    @Test("The period filter measures the purchase date, not any product date")
    func periodFiltersOnPurchaseDate() {
        // The warranty runs well into the future; the purchase is what decides.
        let items = [
            listing("Recent", warrantyExpires: day(300), purchase: purchase(date: day(-1))),
            listing("Old", warrantyExpires: day(300), purchase: purchase(date: day(-120)))
        ]

        #expect(names(ProductFilter(period: .thisMonth), items) == ["Recent"])
        #expect(names(ProductFilter(period: .allTime), items).sorted() == ["Old", "Recent"])
    }

    @Test("Every criterion combines with AND")
    func criteriaCombine() {
        let category = UUID()
        let items = [
            listing("Netflix", trialEnds: day(3), categoryID: category, tags: ["media"]),
            listing("Notion", trialEnds: day(5), categoryID: category, tags: ["work"]),
            listing("Nikon", categoryID: category, tags: ["media"])
        ]

        let filter = ProductFilter(
            search: "n", status: .activeTrials, categoryID: category, tags: ["media"]
        )

        #expect(names(filter, items) == ["Netflix"])
    }

    @Test("An untouched filter is not narrowing anything")
    func defaultFilterIsNotNarrowing() {
        #expect(!ProductFilter().isNarrowing)
        #expect(ProductFilter(search: "a").isNarrowing)
        #expect(ProductFilter(receiptsOnly: true).isNarrowing)
    }

    // MARK: - Sorting (§7.3)

    @Test("Soonest orders by the nearest trial or warranty date")
    func soonestOrdersByNearestDate() {
        let items = [
            listing("Later", trialEnds: day(20)),
            listing("Sooner", warrantyExpires: day(4)),
            listing("Both", trialEnds: day(30), warrantyExpires: day(9))
        ]

        #expect(ProductBrowser.sort(items, by: .soonest).map(\.product.name)
                == ["Sooner", "Both", "Later"])
    }

    @Test("A product with no relevant date sorts last, not first")
    func undatedSortsLast() {
        let items = [listing("Undated"), listing("Dated", trialEnds: day(5))]

        #expect(ProductBrowser.sort(items, by: .soonest).map(\.product.name)
                == ["Dated", "Undated"])
    }

    @Test("Newest, Name and Merchant each order as advertised")
    func remainingSorts() {
        let items = [
            listing("Zebra", purchase: purchase(merchant: "Yard", date: day(-30))),
            listing("apple", purchase: purchase(merchant: "Argos", date: day(-1))),
            listing("Mango", purchase: purchase(merchant: "Market", date: day(-10)))
        ]

        #expect(ProductBrowser.sort(items, by: .newest).map(\.product.name)
                == ["apple", "Mango", "Zebra"])
        #expect(ProductBrowser.sort(items, by: .name).map(\.product.name)
                == ["apple", "Mango", "Zebra"])
        #expect(ProductBrowser.sort(items, by: .merchant).map(\.product.name)
                == ["apple", "Mango", "Zebra"])
    }
}
