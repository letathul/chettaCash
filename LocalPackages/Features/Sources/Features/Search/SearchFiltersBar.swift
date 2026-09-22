import SwiftUI
import Domain

/// The search screen's attribute filters (§7.12).
///
/// Period, accounts, categories and tags, plus the product status row that the Products
/// screen used to carry. Its own view so that typing in the field above does not rebuild
/// four chip rows.
///
/// Criteria are ANDed, and tags are ANDed among themselves: choosing two tags narrows
/// rather than widens.
struct SearchFiltersBar: View {
    /// The screen's view model.
    @Bindable var model: SearchViewModel

    /// The view body.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SegmentedPillControl(
                options: LedgerPeriod.allCases,
                selection: $model.period,
                display: \.filterLabel
            )
            if model.scope != .transactions {
                SegmentedPillControl(
                    options: ProductStatus.allCases,
                    selection: $model.productStatus,
                    display: \.title
                )
            }
            if !model.categories.isEmpty { categoryRow }
            if !model.availableTags.isEmpty { tagRow }
            accountRow
        }
    }

    /// The category chips, drawn from whichever categories the current scope can match.
    ///
    /// Hidden entirely when that list is empty, like the tag row: a lone "All categories"
    /// chip filters nothing.
    private var categoryRow: some View {
        FilterChipRow(title: "Categories") {
            FilterChip(label: "All categories", isSelected: model.categoryID == nil) {
                model.categoryID = nil
            }
            ForEach(model.categories) { category in
                FilterChip(
                    label: category.label,
                    isSelected: model.categoryID == category.id
                ) {
                    model.categoryID = category.id
                }
            }
        }
    }

    /// The tag chips, multi-select and ANDed.
    private var tagRow: some View {
        FilterChipRow(title: "Tags") {
            ForEach(model.availableTags, id: \.self) { tag in
                FilterChip(label: tag, isSelected: model.tags.contains(tag)) {
                    if model.tags.contains(tag) {
                        model.tags.remove(tag)
                    } else {
                        model.tags.insert(tag)
                    }
                }
            }
        }
    }

    /// The account chips, closed accounts included so history stays searchable (§4.7).
    private var accountRow: some View {
        FilterChipRow(title: "Accounts") {
            FilterChip(label: "All accounts", isSelected: model.accountID == nil) {
                model.accountID = nil
            }
            ForEach(model.accounts) { account in
                FilterChip(
                    label: account.isClosed ? "\(account.name) (closed)" : account.name,
                    isSelected: model.accountID == account.id
                ) {
                    model.accountID = account.id
                }
            }
            FilterChip(label: "Has receipt", isSelected: model.receiptsOnly) {
                model.receiptsOnly.toggle()
            }
        }
    }
}
