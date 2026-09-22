import SwiftUI
import Domain

/// The global search screen (§7.12).
///
/// Opened full-screen from the Dashboard. One field searches transactions and products
/// at once — merchants, memos, locations, product names, notes and tags — and the filter
/// rows below narrow by period, account, category and tag.
///
/// This is also where products are browsed, now that they have no tab of their own: the
/// trial, warranty and subscription filters live on the product status row.
public struct SearchView: View {
    /// The screen's view model.
    @State private var model: SearchViewModel
    /// Closes the screen.
    @Environment(\.dismiss) private var dismiss
    /// What the user has typed, before it reaches the filter.
    ///
    /// Held here rather than bound straight to `model.search`, so a keystroke invalidates
    /// only ``SearchField`` and the results are rebuilt on a pause in typing.
    @State private var searchDraft = ""
    /// Keyboard focus for the search field.
    @FocusState private var isSearchFocused: Bool
    /// Whether the product sort picker is showing.
    @State private var isSortPickerPresented = false
    /// The transaction whose detail screen is open.
    @State private var selectedTransaction: Domain.Transaction?
    /// The product whose Edit sheet is open.
    @State private var editingProduct: Domain.Product?

    /// Creates the screen.
    /// - Parameters:
    ///   - ledgerModel: The shared Ledger view model.
    ///   - productsModel: The shared products view model.
    public init(ledgerModel: LedgerViewModel, productsModel: ProductsViewModel) {
        _model = State(initialValue: SearchViewModel(
            ledgerModel: ledgerModel, productsModel: productsModel
        ))
    }

    /// The view body.
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SearchField(
                        placeholder: "Search transactions and products",
                        text: $searchDraft,
                        isFocused: $isSearchFocused
                    )
                    SegmentedPillControl(
                        options: SearchScope.allCases,
                        selection: $model.scope,
                        display: \.title
                    )
                    if model.scope != .transactions { sortPill }
                    SearchFiltersBar(model: model)
                    content
                }
                .padding(16)
            }
            .background(Palette.appBackground)
            .scrollDismissesKeyboard(.interactively)
            .navigationDestination(item: $selectedTransaction) { transaction in
                TransactionDetailView(model: model.ledgerModel, transaction: transaction)
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isSearchFocused = false }
                }
            }
        }
        .task { await model.load() }
        .autoFocus($isSearchFocused)
        // Debounced: re-filtering everything on each character is what made the old
        // product list lag. `.task(id:)` cancels the pending push when the next arrives.
        .task(id: searchDraft) {
            guard model.search != searchDraft else { return }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            model.search = searchDraft
        }
        .sheet(item: $editingProduct) { product in
            productSheet(product)
        }
    }

    /// The product sort pill, which presents the shared picker sheet.
    private var sortPill: some View {
        Button { isSortPickerPresented = true } label: {
            HStack(spacing: 4) {
                Text("Sort products: \(model.productSort.title)")
                    .font(Typography.rowSecondary.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(Palette.brandPurple)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Palette.brandPurple.opacity(0.12), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort products")
        .accessibilityValue(model.productSort.title)
        .accessibilityHint("Double tap to choose")
        .sheet(isPresented: $isSortPickerPresented) {
            OptionPickerSheet(
                title: "Sort products",
                options: ProductSort.allCases,
                selection: Binding(
                    get: { model.productSort },
                    set: { model.productSort = $0 }
                ),
                display: \.title,
                subtitle: \.detail
            )
        }
    }

    /// The results, or whichever empty state applies (§7.0).
    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            SkeletonCard(rowCount: 4)
        } else if model.hasNothingToSearch {
            CardContainer {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "Nothing to search yet",
                    message: "Log a transaction and its products will be searchable here too."
                )
            }
        } else if model.hasNoResults {
            CardContainer {
                FilteredEmptyNotice(message: "Nothing matches your search or filters.")
            }
        } else {
            if !model.transactionRows.isEmpty { transactionSection }
            if !model.productCards.isEmpty { productSection }
        }
    }

    /// The matching transactions, newest first.
    private var transactionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transactions").sectionLabel()
            CardContainer {
                VStack(spacing: 12) {
                    ForEach(model.transactionRows) { row in
                        if row.id != model.transactionRows.first?.id {
                            Divider().overlay(Palette.borderSubtle)
                        }
                        LedgerRowButton(row: row) { selectedTransaction = $0 }
                    }
                }
            }
        }
    }

    /// The matching products, in the chosen order.
    private var productSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Products").sectionLabel()
            ForEach(model.productCards) { card in
                Button {
                    editingProduct = card.product
                } label: {
                    ProductCard(card: card)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The Edit Product sheet, which needs the purchase the product belongs to.
    /// - Parameter product: The product being edited.
    /// - Returns: The sheet.
    @ViewBuilder
    private func productSheet(_ product: Domain.Product) -> some View {
        if let purchase = model.productsModel.purchase(id: product.transactionID) {
            ProductSheet(model: model.productsModel, purchase: purchase, editing: product)
        }
    }
}
