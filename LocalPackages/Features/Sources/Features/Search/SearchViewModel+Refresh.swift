import Foundation
import Domain

/// Rebuilding the search screen's results (§7.12).
///
/// Split from ``SearchViewModel`` to keep each file within the 300-line limit.
extension SearchViewModel {

    /// Recomputes both halves of the results in one pass.
    ///
    /// Runs on every criterion change and after a load. Transactions are filtered here
    /// through ``Domain/LedgerFilter``; products are filtered by writing
    /// ``ProductsViewModel/filter``, which rebuilds that model's cards — so the product
    /// pipeline stays in the one place that has always owned it.
    func refresh() {
        accounts = ledgerModel.accounts
        categories = collectCategories()
        availableTags = collectTags()

        refreshTransactions()
        refreshProducts()
    }

    /// Filters and renders the transaction half.
    private func refreshTransactions() {
        guard scope != .products else {
            transactionRows = []
            transactionsFilteredToZero = false
            return
        }
        let filter = Domain.LedgerFilter(
            period: period,
            accountID: accountID,
            categoryID: categoryID,
            search: search,
            tags: tags,
            receiptsOnly: receiptsOnly
        )
        let matched = filter.apply(to: ledgerModel.allTransactions)
        // Transfers collapse to one row only when no account is chosen, exactly as on
        // the Ledger: under an account filter the user asked to see one side (§4.3).
        let items = LedgerAssembler.items(
            from: matched, collapseTransfers: !filter.isAccountFiltered
        )
        let currencyCode = ledgerModel.settings.currencyCode
        transactionRows = items
            .sorted { $0.date > $1.date }
            .map { ledgerModel.row(for: $0, currencyCode: currencyCode) }
        transactionsFilteredToZero =
            !ledgerModel.allTransactions.isEmpty && transactionRows.isEmpty
    }

    /// Filters and renders the product half.
    private func refreshProducts() {
        guard scope != .transactions else {
            productCards = []
            productsFilteredToZero = false
            return
        }
        productsModel.filter = Domain.ProductFilter(
            search: search,
            status: productStatus,
            categoryID: categoryID,
            tags: tags,
            accountID: accountID,
            period: period,
            receiptsOnly: receiptsOnly
        )
        productCards = productsModel.visibleCards
        productsFilteredToZero = productsModel.isFilteredToZero
    }

    /// The category chips the current scope can match.
    ///
    /// Each half already offers only the categories its own data carries, so nothing here
    /// needs to consult the results: `.all` is simply the union, transactions first, with
    /// the few categories both halves use listed once.
    ///
    /// - Returns: The categories to offer.
    private func collectCategories() -> [Domain.Category] {
        switch scope {
        case .transactions:
            return ledgerModel.filterCategories
        case .products:
            return productsModel.usedCategories
        case .all:
            var seen = Set<UUID>()
            return (ledgerModel.filterCategories + productsModel.usedCategories)
                .filter { seen.insert($0.id).inserted }
        }
    }

    /// Every tag in use, across transactions and products alike.
    /// - Returns: The tags, sorted case-insensitively.
    private func collectTags() -> [String] {
        var all = Set(ledgerModel.allTransactions.flatMap(\.tags))
        all.formUnion(productsModel.products.flatMap(\.tags))
        return all.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
