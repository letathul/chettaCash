import Foundation
import Observation
import Domain

/// Drives the product forms and the search screen's product results (§7.3, §7.7).
///
/// Products have no tab of their own: one is created from the transaction that bought
/// it (§7.8) and browsed from the search screen (§7.12). This model is built once and
/// shared by all three, so no two of them can hold disagreeing lists.
///
/// Loads products **and** the transactions they belong to, joining them into
/// ``Domain/ProductListing`` values. A product carries no price, account or date of its
/// own, so nothing here can be filtered or sorted without its purchase alongside.
@MainActor
@Observable
public final class ProductsViewModel {
    /// Reads and writes products.
    let productRepository: any ProductRepository
    /// Supplies the purchases products belong to, and creates the free-purchase row.
    let transactionRepository: any TransactionRepository
    /// Supplies accounts for the filter row and the free-purchase default.
    let accountRepository: any AccountRepository
    /// Supplies and creates product categories.
    let categoryRepository: any CategoryRepository
    /// Creates and updates the billing rule.
    let recurringRuleRepository: any RecurringRuleRepository
    /// Reads attached receipts back, so a product can show its purchase's image.
    ///
    /// Internal rather than private: ``ProductSheet`` reads through it for a thumbnail.
    let receiptStorage: ReceiptStorageCoordinator?

    /// User preferences, for the display currency.
    public let settings: AppSettings

    /// Every product.
    public internal(set) var products: [Domain.Product] = []
    /// Every transaction, so each product can be joined to its purchase.
    public internal(set) var transactions: [Domain.Transaction] = []
    /// Open accounts, for the picker.
    public internal(set) var accounts: [Domain.Account] = []
    /// Every category.
    public internal(set) var categories: [Domain.Category] = []
    /// Rules billing for products, keyed by product.
    public internal(set) var rulesByProductID: [UUID: Domain.RecurringRule] = [:]
    /// Whether the first load is still running.
    public internal(set) var isLoading = true
    /// A load or save failure to surface above the content (§7.0).
    public internal(set) var errorMessage: String?

    /// The active filter combination.
    ///
    /// Writing this rebuilds the derived state immediately, so a caller can never read a
    /// stale `visibleListings` after moving the filter. The accessors are written out by
    /// hand because `@Observable` transforms *stored* properties only — this keeps
    /// `filter` observable (the chip rows bind straight into it) while still running
    /// `refresh()` on the way through.
    public var filter: ProductFilter {
        get {
            access(keyPath: \.filter)
            return storedFilter
        }
        set {
            withMutation(keyPath: \.filter) { storedFilter = newValue }
            refresh()
        }
    }

    /// The chosen ordering, which rebuilds the list the way ``filter`` does.
    public var sort: ProductSort {
        get {
            access(keyPath: \.sort)
            return storedSort
        }
        set {
            withMutation(keyPath: \.sort) { storedSort = newValue }
            refresh()
        }
    }

    /// Backing storage for ``filter``.
    @ObservationIgnored private var storedFilter = ProductFilter()
    /// Backing storage for ``sort``.
    @ObservationIgnored private var storedSort: ProductSort = .soonest

    /// Creates the view model.
    /// - Parameters:
    ///   - productRepository: Reads and writes products.
    ///   - transactionRepository: Supplies and creates purchases.
    ///   - accountRepository: Supplies accounts.
    ///   - categoryRepository: Supplies and creates categories.
    ///   - recurringRuleRepository: Creates and updates billing rules.
    ///   - settings: The shared preferences object.
    ///   - receiptStorage: Reads stored receipts, when one is available.
    public init(
        productRepository: any ProductRepository,
        transactionRepository: any TransactionRepository,
        accountRepository: any AccountRepository,
        categoryRepository: any CategoryRepository,
        recurringRuleRepository: any RecurringRuleRepository,
        settings: AppSettings,
        receiptStorage: ReceiptStorageCoordinator? = nil
    ) {
        self.productRepository = productRepository
        self.transactionRepository = transactionRepository
        self.accountRepository = accountRepository
        self.categoryRepository = categoryRepository
        self.recurringRuleRepository = recurringRuleRepository
        self.settings = settings
        self.receiptStorage = receiptStorage
    }

    // MARK: - Derived state (§7.3)
    //
    // Stored rather than computed, and rebuilt by `refresh()`. As computed properties
    // the full join-filter-sort pipeline ran twice per body evaluation — once for
    // `isFilteredToZero` and once for the list itself — which the search field re-ran on
    // every keystroke.

    /// Every product joined to its purchase.
    ///
    /// A product whose purchase is missing is dropped rather than shown with invented
    /// figures — the repository refuses to create one, so this is belt and braces.
    public internal(set) var listings: [Domain.ProductListing] = []
    /// The products to list, filtered and ordered.
    public internal(set) var visibleListings: [Domain.ProductListing] = []
    /// Every tag in use, for the tag filter row.
    public internal(set) var availableTags: [String] = []
    /// Whether the filters matched nothing, as distinct from having no data (§7.0).
    public internal(set) var isFilteredToZero = false
    /// Accounts offered in the picker — open ones only (§4.7).
    public internal(set) var selectableAccounts: [Domain.Account] = []
    /// Purchases a product may be attached to (§7.8).
    public internal(set) var attachablePurchases: [Domain.Transaction] = []
    /// Product categories, excluding archived and system ones (§4.8).
    public internal(set) var selectableCategories: [Domain.Category] = []
    /// Those of ``selectableCategories`` at least one product carries.
    ///
    /// What the search screen offers as chips, where a category nothing is filed under
    /// can only ever return no results. The picker above keeps the full list.
    public internal(set) var usedCategories: [Domain.Category] = []

    /// The cards to render, in the same order as ``visibleListings``.
    var visibleCards: [ProductCardModel] = []
    /// Every attachable purchase as a rendered picker row, newest first.
    var purchaseRows: [PurchaseRowModel] = []

    /// Accounts by identifier, replacing a linear scan per row.
    var accountsByID: [UUID: Domain.Account] = [:]
    /// Categories by identifier, replacing a linear scan per row.
    var categoriesByID: [UUID: Domain.Category] = [:]
    /// Purchases by identifier, replacing a linear scan per lookup.
    var transactionsByID: [UUID: Domain.Transaction] = [:]
    /// Products grouped by the purchase they belong to, in display order.
    var productsByTransactionID: [UUID: [Domain.Product]] = [:]

    // MARK: - Loading

    /// Loads products, purchases, accounts, categories and billing rules.
    public func load() async {
        do {
            products = try await productRepository.products()
            transactions = try await transactionRepository.transactions(accountID: nil, in: nil)
            accounts = try await accountRepository.accounts(includeClosed: true)
            categories = try await categoryRepository.allCategories()
            let rules = try await recurringRuleRepository.rules(activeOnly: false)
            rulesByProductID = Dictionary(
                rules.compactMap { rule in rule.productID.map { ($0, rule) } },
                uniquingKeysWith: { first, _ in first }
            )
            errorMessage = nil
        } catch {
            errorMessage = "Could not load your products."
        }
        refresh()
        isLoading = false
    }

    /// Loads once, for callers that may arrive before anything else has asked.
    ///
    /// The Ledger adds products from its own tab (§7.8). Without this the form shows no
    /// categories, because nothing had asked the repositories yet.
    public func loadIfNeeded() async {
        guard isLoading else { return }
        await load()
    }
}
