import SwiftUI
import Domain

/// The Ledger screen (§7.4).
public struct LedgerView: View {
    /// The screen's view model.
    @State private var model: LedgerViewModel
    /// Whether the Add Transaction sheet is showing.
    @State private var isAdding = false
    /// The transaction whose detail screen is open.
    @State private var selectedTransaction: Domain.Transaction?

    /// A tip teaching the Add Expense phrase, supplied by the app (§10).
    ///
    /// Type-erased because the intent it names lives in the app target, which
    /// `Features` must not know about. The tip hides itself once dismissed.
    private let siriTip: AnyView?

    /// Creates the screen.
    /// - Parameters:
    ///   - model: The screen's view model.
    ///   - siriTip: A tip teaching the Add Expense phrase, if the app supplies one.
    public init(model: LedgerViewModel, siriTip: AnyView? = nil) {
        _model = State(initialValue: model)
        self.siriTip = siriTip
    }

    /// The view body.
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let errorMessage = model.errorMessage {
                        ErrorBanner(message: errorMessage) {
                            Task { await model.load() }
                        }
                    }
                    if let siriTip, !model.items.isEmpty { siriTip }
                    LedgerFiltersBar(
                        accounts: model.accounts,
                        categories: model.filterCategories,
                        period: $model.filter.period,
                        accountID: $model.filter.accountID,
                        categoryID: $model.filter.categoryID
                    )
                    content
                }
                .padding(16)
            }
            .background(Palette.appBackground)
            .navigationDestination(item: $selectedTransaction) { transaction in
                TransactionDetailView(model: model, transaction: transaction)
            }
            .navigationTitle("Ledger")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAdding = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add transaction")
                }
            }
        }
        .task { await model.load() }
        // The rows carry formatted amounts, so a currency switch invalidates them the
        // way a filter change does — but nothing writes the filter here, because its
        // setter rebuilds on its own.
        .onChange(of: model.settings.currencyCode) { model.refresh() }
        .sheet(isPresented: $isAdding) {
            TransactionSheet(model: model, editing: nil)
        }
    }

    /// The list, or whichever empty state applies (§7.0).
    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            SkeletonCard(rowCount: 4)
        } else if model.isEmpty {
            emptyState
        } else {
            LedgerSummaryBanner(
                scopeLabel: model.scopeLabel,
                spendCents: model.spendCents,
                incomeCents: model.incomeCents,
                netCents: model.netCents,
                count: model.bannerCount,
                currencyCode: model.settings.currencyCode
            )
            LedgerUpcomingSection(rows: model.upcomingRows) { selectedTransaction = $0 }
            LedgerPostedSection(
                days: model.postedDays,
                isFilteredToZero: model.isFilteredToZero
            ) { selectedTransaction = $0 }
        }
    }

    /// The first-run empty state (§7.0).
    private var emptyState: some View {
        CardContainer {
            EmptyStateView(
                icon: "list.bullet.rectangle",
                title: "No transactions yet",
                message: "Log your first expense, income or transfer.",
                actionTitle: "Log transaction"
            ) {
                isAdding = true
            }
        }
    }
}

/// Display names for the Ledger's period filter.
extension LedgerPeriod {
    /// The label shown on the segmented control.
    var filterLabel: String {
        switch self {
        case .thisMonth: return "This month"
        case .lastMonth: return "Last month"
        case .allTime: return "All time"
        }
    }
}
