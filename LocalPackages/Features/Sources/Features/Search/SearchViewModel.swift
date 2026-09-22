import Foundation
import Observation
import Domain

/// Which kind of thing the search screen is listing (§7.12).
public enum SearchScope: String, CaseIterable, Identifiable, Sendable {
    /// Transactions and products together.
    case all
    /// Transactions only.
    case transactions
    /// Products only.
    case products

    /// The case's identity, for `ForEach`.
    public var id: String { rawValue }

    /// The label shown on the segmented control.
    public var title: String {
        switch self {
        case .all: return "All"
        case .transactions: return "Transactions"
        case .products: return "Products"
        }
    }
}

/// Drives the global search screen (§7.12).
///
/// Reads the **shared** Ledger and products view models rather than repositories of its
/// own. Search that loaded its own copy could disagree with the screen the user came
/// from, and a result opened from here would then edit a different version of the row
/// than the Ledger shows.
///
/// One set of criteria drives both halves: they are projected onto a ``LedgerFilter`` for
/// transactions and a ``ProductFilter`` for products, so the filtering rules themselves
/// stay in Domain where they are tested.
@MainActor
@Observable
public final class SearchViewModel {
    /// Supplies transactions, accounts and categories, and edits a result.
    let ledgerModel: LedgerViewModel
    /// Supplies products and their purchases, and filters them.
    let productsModel: ProductsViewModel

    /// Which kind of thing to list.
    public var scope: SearchScope {
        get {
            access(keyPath: \.scope)
            return storedScope
        }
        set {
            withMutation(keyPath: \.scope) { storedScope = newValue }
            refresh()
            dropUnofferedCategory()
        }
    }

    /// Clears the category filter when the scope just chosen offers no chip for it.
    ///
    /// Each half offers only the categories its own data carries, so moving from All to
    /// Transactions can withdraw the product category that is selected. Left in place it
    /// would go on narrowing the results with nothing on screen to say so.
    private func dropUnofferedCategory() {
        guard let selected = storedCategoryID,
              !categories.contains(where: { $0.id == selected }) else { return }
        categoryID = nil
    }

    /// The live search term.
    public var search: String {
        get {
            access(keyPath: \.search)
            return storedSearch
        }
        set {
            withMutation(keyPath: \.search) { storedSearch = newValue }
            refresh()
        }
    }

    /// The purchase-date window. Defaults to all time: a search that silently hid
    /// anything older than this month would be worse than useless.
    public var period: LedgerPeriod {
        get {
            access(keyPath: \.period)
            return storedPeriod
        }
        set {
            withMutation(keyPath: \.period) { storedPeriod = newValue }
            refresh()
        }
    }

    /// The account to restrict to, or `nil` for every account.
    public var accountID: UUID? {
        get {
            access(keyPath: \.accountID)
            return storedAccountID
        }
        set {
            withMutation(keyPath: \.accountID) { storedAccountID = newValue }
            refresh()
        }
    }

    /// The category to restrict to, or `nil` for every category.
    public var categoryID: UUID? {
        get {
            access(keyPath: \.categoryID)
            return storedCategoryID
        }
        set {
            withMutation(keyPath: \.categoryID) { storedCategoryID = newValue }
            refresh()
        }
    }

    /// Tags a result must carry **all** of, or empty for no tag restriction.
    public var tags: Set<String> {
        get {
            access(keyPath: \.tags)
            return storedTags
        }
        set {
            withMutation(keyPath: \.tags) { storedTags = newValue }
            refresh()
        }
    }

    /// Whether to show only results whose purchase carries a receipt.
    public var receiptsOnly: Bool {
        get {
            access(keyPath: \.receiptsOnly)
            return storedReceiptsOnly
        }
        set {
            withMutation(keyPath: \.receiptsOnly) { storedReceiptsOnly = newValue }
            refresh()
        }
    }

    /// Which products to include: trials, warranties, subscriptions or everything.
    public var productStatus: ProductStatus {
        get {
            access(keyPath: \.productStatus)
            return storedProductStatus
        }
        set {
            withMutation(keyPath: \.productStatus) { storedProductStatus = newValue }
            refresh()
        }
    }

    /// How the product results are ordered.
    public var productSort: ProductSort {
        get {
            access(keyPath: \.productSort)
            return productsModel.sort
        }
        set { productsModel.sort = newValue }
    }

    // Backing storage. `@Observable` transforms *stored* properties only, so each
    // criterion above is written out by hand to keep it observable — the chip rows bind
    // straight into them — while still rebuilding the results on the way through.
    /// Backing storage for ``scope``.
    @ObservationIgnored private var storedScope: SearchScope = .all
    /// Backing storage for ``search``.
    @ObservationIgnored private var storedSearch = ""
    /// Backing storage for ``period``.
    @ObservationIgnored private var storedPeriod: LedgerPeriod = .allTime
    /// Backing storage for ``accountID``.
    @ObservationIgnored private var storedAccountID: UUID?
    /// Backing storage for ``categoryID``.
    @ObservationIgnored private var storedCategoryID: UUID?
    /// Backing storage for ``tags``.
    @ObservationIgnored private var storedTags: Set<String> = []
    /// Backing storage for ``receiptsOnly``.
    @ObservationIgnored private var storedReceiptsOnly = false
    /// Backing storage for ``productStatus``.
    @ObservationIgnored private var storedProductStatus: ProductStatus = .all

    // MARK: - Derived state
    //
    // Stored and rebuilt by `refresh()`, following the Ledger and the product list: a
    // view body must never re-run the filter pipeline to answer a question about it.

    /// The matching transactions, as rendered rows.
    var transactionRows: [LedgerRowModel] = []
    /// The matching products, as rendered cards.
    var productCards: [ProductCardModel] = []
    /// Accounts offered in the filter row, closed ones included (§4.7).
    public internal(set) var accounts: [Domain.Account] = []
    /// Categories offered in the filter row, appropriate to the current scope.
    public internal(set) var categories: [Domain.Category] = []
    /// Every tag in use on a transaction or a product.
    public internal(set) var availableTags: [String] = []
    /// Whether the criteria matched no transaction that does exist (§7.0).
    public internal(set) var transactionsFilteredToZero = false
    /// Whether the criteria matched no product that does exist (§7.0).
    public internal(set) var productsFilteredToZero = false

    /// Whether the underlying data is still loading.
    public var isLoading: Bool { ledgerModel.isLoading || productsModel.isLoading }

    /// Whether the app holds nothing at all to search, which is the first-run state.
    public var hasNothingToSearch: Bool {
        ledgerModel.allTransactions.isEmpty && productsModel.products.isEmpty
    }

    /// Whether every visible section came back empty.
    public var hasNoResults: Bool {
        switch scope {
        case .all: return transactionRows.isEmpty && productCards.isEmpty
        case .transactions: return transactionRows.isEmpty
        case .products: return productCards.isEmpty
        }
    }

    /// Creates the view model.
    /// - Parameters:
    ///   - ledgerModel: The shared Ledger view model.
    ///   - productsModel: The shared products view model.
    public init(ledgerModel: LedgerViewModel, productsModel: ProductsViewModel) {
        self.ledgerModel = ledgerModel
        self.productsModel = productsModel
    }

    /// Loads whichever of the two models has not been asked for yet.
    ///
    /// Search opens from the Dashboard, which may be the only tab the user has visited,
    /// so neither the Ledger's data nor the products' can be assumed present.
    public func load() async {
        await ledgerModel.loadIfNeeded()
        await productsModel.loadIfNeeded()
        refresh()
    }
}
