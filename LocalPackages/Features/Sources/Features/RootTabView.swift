import SwiftUI
import Domain

/// The app's tab shell (§6.1).
///
/// Tab order is Dashboard, Ledger, More, Settings. Products has no tab of its own: a
/// product is always part of a purchase (§7.8), so it is created from the transaction
/// form and browsed from the search screen, which carries the trial, warranty and
/// subscription filters the tab used to.
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
            Tab("Ledger", systemImage: "book.closed", value: TabIdentifier.ledger) {
                LedgerView(model: ledgerModel, siriTip: siriTip)
            }
            Tab("More", systemImage: "ellipsis", value: TabIdentifier.more) {
                MoreView(compareModel: compareModel)
            }
            Tab("Settings", systemImage: "gearshape", value: TabIdentifier.settings) {
                SettingsView(model: settingsModel, siriTip: siriTip)
            }
        }
        .tint(Palette.brandPurple)
    }
}
