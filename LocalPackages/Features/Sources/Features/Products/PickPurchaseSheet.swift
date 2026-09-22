import SwiftUI
import Domain

/// Choosing which purchase a new product belongs to (§7.8).
///
/// A product is never created on its own, so "Add product" asks this first:
/// pick the purchase it came in, or — when nothing was paid for it — start a zero-cost
/// one, which moves no balance and contributes to no total.
struct PickPurchaseSheet: View {
    /// The screen's view model.
    let model: ProductsViewModel

    /// Dismisses the sheet.
    @Environment(\.dismiss) private var dismiss
    /// What the user has typed.
    @State private var searchDraft = ""
    /// The debounced term the list actually filters on.
    @State private var search = ""
    /// The purchase chosen, which opens the product form.
    @State private var chosen: Domain.Transaction?
    /// Whether the free-purchase row is busy writing its transaction.
    @State private var isStartingFree = false
    /// Keyboard focus for the search field.
    @FocusState private var isSearchFocused: Bool

    /// How many results the list shows at once.
    ///
    /// The unsearched list was already capped; the searched one was not, so a one-letter
    /// term could render every purchase ever made.
    private static let resultLimit = 50

    /// Purchases matching the search term, most recent first.
    ///
    /// Compares against ``PurchaseRowModel/searchKey``, lowercased once when the rows
    /// were built, rather than running a locale-aware `range(of:options:)` per row.
    private var matches: [PurchaseRowModel] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return Array(model.purchaseRows.prefix(Self.resultLimit)) }
        return model.purchaseRows
            .lazy
            .filter { $0.searchKey.contains(term) }
            .prefix(Self.resultLimit)
            .map { $0 }
    }

    /// The view body.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    freePurchaseRow
                    SearchField(
                        placeholder: "Search purchases",
                        text: $searchDraft,
                        isFocused: $isSearchFocused
                    )
                    purchaseList
                }
                .padding(16)
            }
            .background(Palette.appBackground)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Which purchase?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isSearchFocused = false }
                }
            }
        }
        .task { await model.loadIfNeeded() }
        .task(id: searchDraft) {
            guard search != searchDraft else { return }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            search = searchDraft
        }
        .autoFocus($isSearchFocused)
        .sheet(item: $chosen) { purchase in
            ProductSheet(
                model: model,
                purchase: purchase,
                sortIndex: model.products(for: purchase.id).count
            )
        }
    }

    /// The escape hatch for something that cost nothing (§7.8).
    private var freePurchaseRow: some View {
        CardContainer {
            Button {
                startFreePurchase()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "gift")
                        .font(.title3)
                        .foregroundStyle(Palette.brandPurple)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nothing was paid for it")
                            .font(Typography.rowPrimary)
                            .foregroundStyle(Palette.textPrimary)
                        Text("Records a zero-cost purchase. Your balances do not move.")
                            .font(Typography.errorCaption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: 8)
                    if isStartingFree {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Palette.textSecondary)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(isStartingFree)
        }
    }

    /// The matching purchases, or the reason there are none (§7.0).
    @ViewBuilder
    private var purchaseList: some View {
        if model.purchaseRows.isEmpty {
            CardContainer {
                EmptyStateView(
                    icon: "book.closed",
                    title: "No purchases yet",
                    message: "Log a transaction in the Ledger first, or use the row above "
                        + "for something that cost nothing."
                )
            }
        } else {
            PurchaseResults(rows: matches) { chosen = $0 }
        }
    }

    /// Writes the zero-cost purchase and opens the product form on it.
    private func startFreePurchase() {
        isStartingFree = true
        Task {
            chosen = await model.makeFreePurchase()
            isStartingFree = false
        }
    }
}

/// The matching purchases, or the notice that nothing matched (§7.0).
struct PurchaseResults: View {
    /// The rows to show.
    let rows: [PurchaseRowModel]
    /// Chooses a purchase.
    let onSelect: (Domain.Transaction) -> Void

    /// The view body.
    var body: some View {
        if rows.isEmpty {
            CardContainer {
                FilteredEmptyNotice(message: "No purchases match that search.")
            }
        } else {
            CardContainer {
                VStack(spacing: 12) {
                    ForEach(rows) { row in
                        if row.id != rows.first?.id {
                            Divider().overlay(Palette.borderSubtle)
                        }
                        purchaseRow(row)
                    }
                }
            }
        }
    }

    /// One selectable purchase.
    /// - Parameter row: The row to render.
    /// - Returns: The row view.
    private func purchaseRow(_ row: PurchaseRowModel) -> some View {
        Button {
            onSelect(row.purchase)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(Typography.rowPrimary)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Text(row.subtitle)
                        .font(Typography.rowSecondary)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if row.hasReceipt {
                    Image(systemName: "paperclip")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityLabel("Has a receipt")
                }
                Text(row.amountText)
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
