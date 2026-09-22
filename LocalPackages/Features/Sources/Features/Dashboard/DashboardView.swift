import SwiftUI
import Domain

/// The Dashboard (§7.1).
///
/// Sections top to bottom: Today card, account strip, quick actions, Trends, Recent
/// transactions. Everything time-sensitive lives in the Today card, so nothing else
/// here carries a badge.
public struct DashboardView: View {
    /// The screen's view model.
    @State private var model: DashboardViewModel
    /// The Ledger's view model, for the recent rows' detail screen and for search (§7.12).
    private let ledgerModel: LedgerViewModel
    /// The products view model, for the purchase picker and for search (§7.8, §7.12).
    private let productsModel: ProductsViewModel
    /// Whether the Today sheet is showing.
    @State private var isShowingToday = false
    /// Whether the search screen is showing (§7.12).
    @State private var isSearching = false
    /// Whether the purchase picker is showing (§7.8).
    @State private var isPickingPurchase = false
    /// Whether the Add Transaction sheet is showing (§7.1).
    @State private var isAddingTransaction = false
    /// The transaction whose detail screen is open.
    @State private var selectedTransaction: Domain.Transaction?
    /// Opens the Ledger tab.
    private let onSeeAll: () -> Void
    /// Width of an account mini-card, which grows with Dynamic Type (§12).
    ///
    /// A fixed width truncates the name and the balance at accessibility sizes. The
    /// strip scrolls horizontally, so widening costs nothing.
    @ScaledMetric(relativeTo: .subheadline) private var accountCardWidth: CGFloat = 150

    /// Creates the screen.
    /// - Parameters:
    ///   - model: The screen's view model.
    ///   - ledgerModel: The Ledger's view model, shared so a transaction opened from here
    ///     reads and edits exactly as it does on the Ledger.
    ///   - productsModel: The products view model, shared for the same reason.
    ///   - onSeeAll: Opens the Ledger.
    public init(
        model: DashboardViewModel,
        ledgerModel: LedgerViewModel,
        productsModel: ProductsViewModel,
        onSeeAll: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.ledgerModel = ledgerModel
        self.productsModel = productsModel
        self.onSeeAll = onSeeAll
    }

    /// The view body.
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let errorMessage = model.errorMessage {
                        ErrorBanner(message: errorMessage) {
                            Task { await model.load() }
                        }
                    }
                    // Outside the branch below: the note applies in every state,
                    // including the empty one a skipped onboarding lands on.
                    if model.showsStarterAccountNote {
                        StarterAccountNote { model.dismissStarterAccountNote() }
                    }
                    if model.isLoading {
                        SkeletonCard(rowCount: 4)
                    } else if model.hasNoAccounts {
                        emptyState
                    } else {
                        todayCard
                        accountStrip
                        quickActions
                        TrendsSection(
                            spend: model.spendTrend,
                            netWorth: model.netWorthTrend,
                            currencyCode: model.settings.currencyCode
                        )
                        recentSection
                    }
                }
                .padding(16)
            }
            .background(Palette.appBackground)
            .navigationDestination(item: $selectedTransaction) { transaction in
                TransactionDetailView(model: ledgerModel, transaction: transaction)
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isSearching = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search")
                }
            }
        }
        .task { await model.load() }
        // The recent rows carry formatted amounts, so a currency switch invalidates them.
        .onChange(of: model.settings.currencyCode) { model.refresh() }
        .sheet(isPresented: $isShowingToday) {
            TodaySheet(model: model)
        }
        // The same form the Ledger's + button opens, over the same shared view model.
        .sheet(isPresented: $isAddingTransaction, onDismiss: reload) {
            TransactionSheet(model: ledgerModel, editing: nil)
        }
        // A product is always part of a purchase (§7.8), so adding one starts by
        // choosing which — or by recording that nothing was paid for it.
        .sheet(isPresented: $isPickingPurchase) {
            PickPurchaseSheet(model: productsModel)
        }
        .fullScreenCover(isPresented: $isSearching) {
            SearchView(ledgerModel: ledgerModel, productsModel: productsModel)
        }
    }

    /// The Today card, tappable into the Today sheet.
    private var todayCard: some View {
        Button {
            isShowingToday = true
        } label: {
            TodayCard(
                digest: model.digest,
                availableCashCents: model.availableCashCents,
                netWorthCents: model.netWorthCents,
                currencyCode: model.settings.currencyCode
            )
        }
        .buttonStyle(.plain)
    }

    /// Horizontally scrolling account mini-cards — reference data, so it sits below Today.
    private var accountStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accounts").sectionLabel()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.openAccounts) { account in
                        accountCard(account)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    /// One account mini-card.
    /// - Parameter account: The account to show.
    /// - Returns: The card view.
    private func accountCard(_ account: Domain.Account) -> some View {
        CardContainer(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: account.kind == .card ? "creditcard.fill" : "banknote.fill")
                    .font(.callout)
                    .foregroundStyle(
                        account.kind == .card ? Palette.attentionAmber : Palette.brandPurple
                    )
                    .accessibilityHidden(true)
                Text(account.name)
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(money(account.cachedBalanceCents))
                    .moneyText(Typography.rowPrimary)
                    .foregroundStyle(
                        account.cachedBalanceCents < 0 ? Palette.negativeRed : Palette.textPrimary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: accountCardWidth)
    }

    /// The two quick actions (§7.1).
    private var quickActions: some View {
        HStack(spacing: 10) {
            Button(action: beginLoggingTransaction) {
                Text("Log transaction")
                    .font(Typography.rowPrimary.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Palette.brandPurple, in: .capsule)
            }
            .buttonStyle(.plain)
            Button { isPickingPurchase = true } label: {
                Text("Add product")
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.brandPurple)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Palette.surface, in: .capsule)
                    .overlay { Capsule().strokeBorder(Palette.borderSubtle, lineWidth: 1) }
            }
            .buttonStyle(.plain)
        }
    }

    /// Opens the Add Transaction sheet, loading the Ledger first if it is still cold.
    ///
    /// ``TransactionSheet`` seeds its form from `selectableAccounts` at *init*, so a sheet
    /// presented over an unloaded Ledger opens with no account chosen and empty pickers —
    /// and the Dashboard may well be the only tab visited. A no-op on every later tap.
    private func beginLoggingTransaction() {
        Task {
            await ledgerModel.loadIfNeeded()
            isAddingTransaction = true
        }
    }

    /// Reloads after a sheet that may have written something.
    ///
    /// The two view models hold independent snapshots, so saving through the Ledger's
    /// leaves the Today card, balances, trends and Recent rows stale until this runs.
    private func reload() {
        Task { await model.load() }
    }

    /// The most recent posted transactions, with a link into the Ledger.
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent").sectionLabel()
                Spacer()
                Button("See all", action: onSeeAll)
                    .font(Typography.rowSecondary.weight(.semibold))
                    .foregroundStyle(Palette.brandPurple)
            }
            if model.recentRows.isEmpty {
                CardContainer {
                    FilteredEmptyNotice(message: "Nothing posted yet.")
                }
            } else {
                CardContainer {
                    VStack(spacing: 12) {
                        ForEach(model.recentRows) { row in
                            if row.id != model.recentRows.first?.id {
                                Divider().overlay(Palette.borderSubtle)
                            }
                            Button {
                                selectedTransaction = row.transaction
                            } label: {
                                RecentRow(row: row)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// The Dashboard's empty state, shown only when there are zero accounts (§7.1).
    private var emptyState: some View {
        CardContainer {
            EmptyStateView(
                icon: "wallet.bifold",
                title: "No accounts yet",
                message: "Add an account to start tracking your balance.",
                actionTitle: "Add your first account",
                action: onSeeAll
            )
        }
    }

    /// Formats an amount using the display currency.
    /// - Parameter cents: The amount in cents.
    /// - Returns: The formatted string.
    private func money(_ cents: Int) -> String {
        CurrencyFormatter.string(fromCents: cents, currencyCode: model.settings.currencyCode)
    }
}
