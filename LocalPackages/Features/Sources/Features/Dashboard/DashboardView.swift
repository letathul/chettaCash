import SwiftUI
import Domain

/// The Dashboard (§7.1).
///
/// A greeting, the hero account carousel, and today's transactions. Everything
/// time-sensitive lives in the carousel's digest chips and behind its chevron, so
/// nothing else here carries a badge. "Log transaction" lives in the tab bar and
/// "Add product" is the floating button in the bottom-trailing corner — see
/// ``RootTabView``.
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
    /// The transaction whose detail screen is open.
    @State private var selectedTransaction: Domain.Transaction?
    /// Opens the Ledger tab.
    private let onSeeAll: () -> Void

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
                        carousel
                        todaySection
                    }
                }
                .padding(16)
                // The floating button sits over this content, so the last row has to
                // be able to scroll clear of it rather than hide underneath.
                .padding(.bottom, showsAddProductButton ? 76 : 0)
            }
            .background(Palette.appBackground)
            .overlay(alignment: .bottomTrailing) {
                if showsAddProductButton {
                    addProductButton
                }
            }
            .navigationDestination(item: $selectedTransaction) { transaction in
                TransactionDetailView(model: ledgerModel, transaction: transaction)
            }
            .navigationTitle(Self.greeting())
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
        // The rows and hero pages carry formatted amounts, so a currency switch
        // invalidates them.
        .onChange(of: model.settings.currencyCode) { model.refresh() }
        .sheet(isPresented: $isShowingToday) {
            TodaySheet(model: model)
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

    /// Whether the floating "Add product" button is showing.
    private var showsAddProductButton: Bool {
        !model.isLoading && !model.hasNoAccounts
    }

    /// The greeting the screen is titled with.
    ///
    /// A `static func` rather than a computed property so it is evaluated once per
    /// body rather than captured as view state that would go stale at midnight.
    ///
    /// - Parameters:
    ///   - now: The moment to greet for.
    ///   - calendar: The calendar deciding the hour.
    /// - Returns: The greeting.
    static func greeting(now: Date = .now, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: now) {
        case 0..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    /// The hero carousel, one page per open account behind "All accounts".
    private var carousel: some View {
        HeroAccountCarousel(
            pages: model.heroPages,
            digest: model.digest,
            currencyCode: model.settings.currencyCode,
            focusedAccountID: focusedAccountBinding,
            onOpenToday: { isShowingToday = true }
        )
    }

    /// A two-way binding onto the focused-account setting.
    ///
    /// Writes go through ``DashboardViewModel/setFocusedAccount(_:)`` so the choice is
    /// persisted and every derived figure recomputes, rather than just updating local
    /// view state.
    private var focusedAccountBinding: Binding<UUID?> {
        Binding(
            get: { model.settings.focusedAccountID },
            set: { model.setFocusedAccount($0) }
        )
    }

    /// The floating "Add product" action (§7.1).
    ///
    /// "Log transaction" lives in the tab bar (``RootTabView``), so this is the only
    /// quick action the Dashboard itself still owns.
    private var addProductButton: some View {
        Button { isPickingPurchase = true } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Palette.brandPurple, in: .circle)
                .shadow(color: Palette.cardShadow, radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        .accessibilityLabel("Add product")
    }

    /// Today's posted transactions, or the most recent ones when today is quiet (§7.1).
    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.recentSectionTitle).sectionLabel()
            if model.recentRows.isEmpty {
                CardContainer {
                    FilteredEmptyNotice(message: "Nothing posted yet.")
                }
            } else {
                CardContainer {
                    VStack(spacing: 12) {
                        if model.isShowingRecentFallback { fallbackNote }
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
                        Divider().overlay(Palette.borderSubtle)
                        seeAllButton
                    }
                }
            }
        }
    }

    /// Says why the list is showing older transactions on a quiet day.
    private var fallbackNote: some View {
        Text("No activity today — showing recent")
            .font(Typography.rowSecondary)
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The link into the Ledger, which the mock places inside the card.
    private var seeAllButton: some View {
        Button("See all transactions", action: onSeeAll)
            .font(Typography.rowSecondary.weight(.semibold))
            .foregroundStyle(Palette.brandPurple)
            .frame(maxWidth: .infinity)
            .tappableSurface()
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
}
