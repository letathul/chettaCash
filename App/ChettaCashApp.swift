import SwiftUI
import AppIntents
import Domain
import Features

/// The application entry point.
///
/// Launch runs the §3 gates in order: the app-lock gate (§11, Phase 13) comes first,
/// then onboarding, then the tab shell (§6.1): Dashboard, Ledger, More, Settings.
@main
struct ChettaCashApp: App {
    /// The composition root, or `nil` until it is built.
    @State private var dependencies: AppDependencies?
    /// The error to surface if the container failed to initialise.
    @State private var startupError: String?
    /// Drives reconcile when the app returns to the foreground (§4.5, §4.6).
    @Environment(\.scenePhase) private var scenePhase
    /// The app lock's controller, built once the graph exists (§11).
    @State private var lockController: AppLockController?
    /// Drives receipt uploads, the cache and backups (§9).
    @State private var storage: ReceiptStorageCoordinator?
    /// Mirrors the persisted flag so finishing onboarding re-renders the root.
    ///
    /// `AppSettings` is observable, but the gate is read during the same update in
    /// which onboarding writes it; this makes the transition explicit.
    @State private var hasCompletedOnboarding = false

    /// The app's scene graph.
    var body: some Scene {
        WindowGroup {
            lockedContent
                .task { await start() }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active, let dependencies else { return }
                    Task { await reconcile(dependencies) }
                }
                // A Shortcut can run while the app is already foregrounded, and
                // `scenePhase` does not change then — so the reconcile above never
                // fires and the Ledger would keep showing figures that no longer match.
                .onReceive(
                    NotificationCenter.default.publisher(for: .chettaCashDataDidChange)
                ) { _ in
                    guard let dependencies else { return }
                    Task { await reconcile(dependencies) }
                }
        }
    }

    /// The root content behind the §11 app-lock gate.
    @ViewBuilder
    private var lockedContent: some View {
        if let lockController {
            AppLockGate(controller: lockController) { content }
        } else {
            content
        }
    }

    /// The root content, showing a startup error rather than crashing on failure.
    @ViewBuilder
    private var content: some View {
        if let startupError {
            ContentUnavailableView(
                "Could not open your data",
                systemImage: "exclamationmark.triangle",
                description: Text(startupError)
            )
        } else if let dependencies, !hasCompletedOnboarding {
            OnboardingView(
                model: OnboardingViewModel(
                    accountRepository: dependencies.accounts,
                    notifications: dependencies.notifications,
                    settingsStore: dependencies.settingsStore,
                    settings: dependencies.settings
                ),
                onFinish: { hasCompletedOnboarding = true }
            )
        } else if let dependencies {
            rootTabView(dependencies)
        } else {
            ProgressView()
        }
    }

    /// The tab shell, with its five view models.
    ///
    /// A function rather than more of `content` so the products model can be built once
    /// and handed to three places: the Dashboard's purchase picker, the search screen
    /// (§7.12), and the Ledger's product section (§7.8). They must see the *same* list,
    /// or a product added from a transaction would not appear until the next reload.
    ///
    /// - Parameter dependencies: The composition root to build from.
    /// - Returns: The tab shell.
    private func rootTabView(_ dependencies: AppDependencies) -> some View {
        let productsModel = ProductsViewModel(
            productRepository: dependencies.products,
            transactionRepository: dependencies.transactions,
            accountRepository: dependencies.accounts,
            categoryRepository: dependencies.categories,
            recurringRuleRepository: dependencies.recurringRules,
            settings: dependencies.settings,
            receiptStorage: storage
        )
        return RootTabView(
                dashboardModel: dashboardModel(dependencies),
                productsModel: productsModel,
                ledgerModel: LedgerViewModel(
                    transactionRepository: dependencies.transactions,
                    accountRepository: dependencies.accounts,
                    categoryRepository: dependencies.categories,
                    recurringRuleRepository: dependencies.recurringRules,
                    settings: dependencies.settings,
                    productsModel: productsModel,
                    receiptStorage: storage
                ),
                compareModel: CompareViewModel(
                    repository: dependencies.comparisons,
                    settings: dependencies.settings
                ),
                settingsModel: settingsModel(dependencies),
                siriTip: siriTip(dependencies)
            )
    }

    /// The tip teaching the Add Expense phrase (§10).
    ///
    /// Built here rather than in `Features` because it names ``AddExpenseIntent``,
    /// which lives in this target. Dismissal is persisted: a tip that comes back after
    /// the user has closed it is an advert.
    ///
    /// - Parameter dependencies: The composition root, for settings and their store.
    /// - Returns: The tip, already hidden if it has been dismissed.
    private func siriTip(_ dependencies: AppDependencies) -> AnyView {
        AnyView(
            SiriTipView(
                intent: AddExpenseIntent(),
                isVisible: Binding(
                    get: { !dependencies.settings.hasDismissedShortcutTip },
                    set: { isVisible in
                        dependencies.settings.hasDismissedShortcutTip = !isVisible
                        dependencies.settingsStore.save(dependencies.settings)
                    }
                )
            )
        )
    }

    /// The Dashboard tab's view model.
    /// - Parameter dependencies: The composition root to build from.
    /// - Returns: The view model.
    private func dashboardModel(_ dependencies: AppDependencies) -> DashboardViewModel {
        DashboardViewModel(
            accountRepository: dependencies.accounts,
            transactionRepository: dependencies.transactions,
            categoryRepository: dependencies.categories,
            recurringRuleRepository: dependencies.recurringRules,
            statementRepository: dependencies.cardStatements,
            productRepository: dependencies.products,
            settings: dependencies.settings,
            settingsStore: dependencies.settingsStore
        )
    }

    /// The Settings tab's view model.
    /// - Parameter dependencies: The composition root to build from.
    /// - Returns: The view model.
    private func settingsModel(_ dependencies: AppDependencies) -> SettingsViewModel {
        SettingsViewModel(
            accountRepository: dependencies.accounts,
            transactionRepository: dependencies.transactions,
            settingsStore: dependencies.settingsStore,
            settings: dependencies.settings,
            statementRepository: dependencies.cardStatements,
            categoryRepository: dependencies.categories,
            storage: storage,
            appLock: lockController,
            merchantRuleRepository: dependencies.merchantRules,
            showsFeatureFlags: dependencies.showsFeatureFlags
        )
    }

    /// Builds the dependency graph.
    private func start() async {
        guard dependencies == nil, startupError == nil else { return }
        do {
            let dependencies = try await AppEnvironment.shared()
            #if DEBUG
            if DemoSeed.isRequested { await DemoSeed.run(dependencies) }
            #endif
            // Read the persisted gate before publishing the graph, so the first
            // render already knows whether onboarding has run (§7.10).
            hasCompletedOnboarding = dependencies.settings.hasCompletedOnboarding
            lockController = AppLockController(
                authenticator: dependencies.lockAuthenticator,
                settings: dependencies.settings,
                settingsStore: dependencies.settingsStore
            )
            storage = ReceiptStorageCoordinator(
                store: dependencies.receiptStore,
                transactions: dependencies.transactions,
                backups: dependencies.backupWriter,
                settings: dependencies.settings
            )
            await reconcile(dependencies)
            self.dependencies = dependencies
        } catch {
            startupError = error.localizedDescription
        }
    }

    /// Posts due recurring occurrences and closes any statements that have come due.
    ///
    /// Runs at app level rather than from a screen, so occurrences post whether or
    /// not the user visits the Ledger (§4.5). Takes the graph explicitly: during
    /// startup the `@State` property has not yet been published.
    ///
    /// This is also where the §9.5 receipt queue is drained. Nothing else drives it
    /// automatically — Settings has a manual retry — so without this a captured
    /// receipt never leaves the in-memory cache and is lost at the next launch.
    ///
    /// - Parameter dependencies: The composition root to reconcile through.
    private func reconcile(_ dependencies: AppDependencies) async {
        await AppReconciler(
            transactions: dependencies.transactions,
            rules: dependencies.recurringRules,
            statements: dependencies.cardStatements,
            accounts: dependencies.accounts
        ).run()
        await syncReminders(dependencies)
        await storage?.flushUploads()
        await storage?.writeScheduledBackupIfDue()
        await ensureUsableAccount(dependencies)
        // Without this, "Add a Chetta Cash expense to Chequing" keeps resolving against the
        // account list the system cached when the app was installed. The picker's own lookup
        // is unaffected — `AccountEntityQuery` reads the live store on every resolution.
        ChettaCashShortcuts.updateAppShortcutParameters()
    }

    /// Keeps at least one open account in the app (§7.10).
    ///
    /// Runs **after** the reconcile above, which is what restores an imported backup:
    /// seeding first would briefly add a stray Cash account alongside the restored
    /// ones. It no-ops while any open account exists, so ordering only matters within
    /// a single launch.
    ///
    /// Gated on onboarding having finished — otherwise a first launch would seed Cash
    /// before the user ever reaches the group page.
    ///
    /// - Parameter dependencies: The composition root to seed through.
    private func ensureUsableAccount(_ dependencies: AppDependencies) async {
        guard dependencies.settings.hasCompletedOnboarding else { return }
        await StarterAccountCoordinator(
            accounts: dependencies.accounts,
            settings: dependencies.settings,
            settingsStore: dependencies.settingsStore
        ).ensureUsableAccount()
    }

    /// Recomputes and reschedules every local notification (§10).
    ///
    /// Runs alongside the foreground reconcile, so a date changed on another device —
    /// or a statement that has since closed — is reflected in what is scheduled.
    ///
    /// - Parameter dependencies: The composition root to sync through.
    private func syncReminders(_ dependencies: AppDependencies) async {
        await ReminderCoordinator(
            accounts: dependencies.accounts,
            products: dependencies.products,
            authorizer: dependencies.notifications,
            scheduler: dependencies.notificationScheduler
        ).sync(settings: dependencies.settings)
    }
}
