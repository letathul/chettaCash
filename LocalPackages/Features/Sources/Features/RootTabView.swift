import SwiftUI
import Domain

/// The app's tab shell (§6.1).
///
/// Tab order is Dashboard, Ledger, Add, More, Settings — Add sits dead centre, where
/// the reach is shortest. Products has no tab of its
/// own: a product is always part of a purchase (§7.8), so it is created from the
/// transaction form, the Dashboard's floating button, and browsed from the search
/// screen, which carries the trial, warranty and subscription filters the tab used
/// to. Add is not a real destination — see the `onChange` below.
public struct RootTabView: View {
    /// The Dashboard tab's view model.
    private let dashboardModel: DashboardViewModel
    /// The products view model, shared by the Dashboard, the search screen and the
    /// transaction form so that no two of them can hold disagreeing lists (§7.8).
    private let productsModel: ProductsViewModel
    /// The Ledger tab's view model.
    private let ledgerModel: LedgerViewModel
    /// The Compare screen's view model, reached through the More tab.
    private let compareModel: CompareViewModel
    /// The Settings tab's view model.
    private let settingsModel: SettingsViewModel
    /// A tip teaching the Add Expense phrase, passed through to Settings (§10).
    private let siriTip: AnyView?

    /// Which tab is selected.
    @State private var selection: TabIdentifier = TabIdentifier.initialSelection
    /// Whether the Add Transaction sheet is showing, opened from the tab bar (§7.1).
    @State private var isAddingTransaction = false

    /// The tabs that currently exist.
    fileprivate enum TabIdentifier: Hashable {
        /// The Dashboard.
        case dashboard
        /// The Ledger.
        case ledger
        /// The More tab.
        case more
        /// Settings.
        case settings
        /// Not a real destination: selecting it opens Add Transaction instead (§7.1).
        case addTransaction

        /// Which tab the app opens on.
        ///
        /// Always the Dashboard, except in debug builds launched with
        /// `--start-tab=<name>`, which exists so a screen can be captured without
        /// driving the UI by hand.
        static var initialSelection: TabIdentifier {
            #if DEBUG
            let argument = ProcessInfo.processInfo.arguments
                .first { $0.hasPrefix("--start-tab=") }?
                .replacingOccurrences(of: "--start-tab=", with: "")
            switch argument {
            case "ledger": return .ledger
            case "more": return .more
            case "settings": return .settings
            default: return .dashboard
            }
            #else
            return .dashboard
            #endif
        }
    }

    /// Creates the tab shell.
    /// - Parameters:
    ///   - dashboardModel: The Dashboard tab's view model.
    ///   - productsModel: The shared products view model.
    ///   - ledgerModel: The Ledger tab's view model.
    ///   - compareModel: The Compare screen's view model.
    ///   - settingsModel: The Settings tab's view model.
    ///   - siriTip: A tip teaching the Add Expense phrase, if the app supplies one.
    public init(
        dashboardModel: DashboardViewModel,
        productsModel: ProductsViewModel,
        ledgerModel: LedgerViewModel,
        compareModel: CompareViewModel,
        settingsModel: SettingsViewModel,
        siriTip: AnyView? = nil
    ) {
        self.dashboardModel = dashboardModel
        self.productsModel = productsModel
        self.ledgerModel = ledgerModel
        self.compareModel = compareModel
        self.settingsModel = settingsModel
        self.siriTip = siriTip
    }

    /// The view body.
    public var body: some View {
        TabView(selection: $selection) {
            Tab("Dashboard", systemImage: "house", value: TabIdentifier.dashboard) {
                DashboardView(
                    model: dashboardModel,
                    ledgerModel: ledgerModel,
                    productsModel: productsModel,
                    onSeeAll: { selection = .ledger }
                )
            }
            Tab("Ledger", systemImage: "list.bullet", value: TabIdentifier.ledger) {
                LedgerView(model: ledgerModel, siriTip: siriTip)
            }
            Tab("Add", systemImage: "banknote.fill", value: TabIdentifier.addTransaction) {
                EmptyView()
            }
            Tab("More", systemImage: "ellipsis", value: TabIdentifier.more) {
                MoreView(compareModel: compareModel)
            }
            Tab("Settings", systemImage: "gearshape", value: TabIdentifier.settings) {
                SettingsView(model: settingsModel, siriTip: siriTip)
            }
        }
        .tint(Palette.brandPurple)
        // Native `TabView` has no notion of an action item, so this tab is
        // intercepted rather than let switch: selecting it immediately reverts to
        // whichever tab was showing and opens Add Transaction instead.
        .onChange(of: selection) { oldValue, newValue in
            if newValue == .addTransaction {
                selection = oldValue
                beginLoggingTransaction()
            }
        }
        // The same form the Ledger's + button and the Dashboard's old quick action
        // opened, over the shared Ledger view model.
        .sheet(isPresented: $isAddingTransaction, onDismiss: reloadDashboard) {
            TransactionSheet(model: ledgerModel, editing: nil)
        }
    }

    /// Opens the Add Transaction sheet, loading the Ledger first if it is still cold.
    ///
    /// ``TransactionSheet`` seeds its form from `selectableAccounts` at *init*, so a
    /// sheet presented over an unloaded Ledger opens with no account chosen and empty
    /// pickers — and the Dashboard may well be the only tab visited before this fires.
    /// A no-op on every later tap.
    private func beginLoggingTransaction() {
        Task {
            await ledgerModel.loadIfNeeded()
            isAddingTransaction = true
        }
    }

    /// Reloads the Dashboard after a transaction may have been added.
    ///
    /// The Dashboard and Ledger view models hold independent snapshots, so saving
    /// through the Ledger's leaves the Dashboard's figures stale until this runs.
    private func reloadDashboard() {
        Task { await dashboardModel.load() }
    }
}
