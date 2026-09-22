import Foundation
import SwiftData
import Domain
import Data
import Features

/// The composition root.
///
/// This is the only place that knows both `Data` and `Features` exist. `Features`
/// receives Domain protocols, never concrete SwiftData types, which is what keeps
/// the module boundary one-way.
@MainActor
final class AppDependencies {
    /// The SwiftData container backing every repository.
    let container: ModelContainer
    /// Reads and writes accounts and groups.
    let accounts: any AccountRepository
    /// Reads and writes ledger transactions.
    let transactions: any TransactionRepository
    /// Reads and writes categories.
    let categories: any CategoryRepository
    /// Reads and writes recurring rules.
    let recurringRules: any RecurringRuleRepository
    /// Reads and writes card statements and their payment allocations.
    let cardStatements: any CardStatementRepository
    /// Reads and writes Smart Vault products.
    let products: any ProductRepository
    /// Reads and writes saved price comparisons.
    let comparisons: any ComparisonRepository
    /// Reads and writes merchant-to-category pins (§4.8).
    let merchantRules: any MerchantCategoryRuleRepository
    /// Writes everything one Shortcut entry implies, in one commit (§15).
    let quickEntries: any QuickEntryWriting
    /// Loads and persists preferences.
    let settingsStore: any AppSettingsStore
    /// Stores receipt images and backup archives (§9.2).
    let receiptStore: any ReceiptStore
    /// Builds and writes backup archives (§9.4).
    let backupWriter: any BackupWriting
    /// Performs device-owner authentication (§11).
    let lockAuthenticator: any AppLockAuthenticating = SystemAppLockAuthenticator()
    /// Requests permission to post local notifications.
    let notifications: any NotificationAuthorizing = SystemNotificationAuthorizer()
    /// Schedules and cancels local notifications.
    let notificationScheduler: any NotificationScheduling = SystemNotificationScheduler()
    /// User-facing preferences.
    let settings = AppSettings()
    /// Whether this build may offer the feature-flag menu (§7.6).
    let showsFeatureFlags = BuildChannel.current.showsFeatureFlags

    /// Seeds the built-in categories, off the main actor.
    private let seeder: SwiftDataCategorySeeder

    /// Builds the container and wires the repositories.
    ///
    /// Wiring only. Seeding is ``prepare()``'s job, because it touches the store and this
    /// initialiser runs on the main actor — and an App Intent is often the first thing to
    /// build this graph, on a cold launch with no window, so whatever happens here is charged
    /// to a Shortcut that only wanted to record a coffee.
    ///
    /// - Parameter inMemory: When `true`, nothing is written to disk.
    /// - Throws: A `SwiftDataError` if the schema fails validation.
    init(inMemory: Bool = false) throws {
        let container = try ModelContainerFactory.make(inMemory: inMemory)
        self.seeder = SwiftDataCategorySeeder(modelContainer: container)
        self.container = container
        self.accounts = SwiftDataAccountRepository(modelContainer: container)
        self.transactions = SwiftDataTransactionRepository(modelContainer: container)
        self.categories = SwiftDataCategoryRepository(modelContainer: container)
        self.recurringRules = SwiftDataRecurringRuleRepository(modelContainer: container)
        self.cardStatements = SwiftDataCardStatementRepository(modelContainer: container)
        self.products = SwiftDataProductRepository(modelContainer: container)
        self.comparisons = SwiftDataComparisonRepository(modelContainer: container)
        self.merchantRules = SwiftDataMerchantCategoryRuleRepository(modelContainer: container)
        self.quickEntries = SwiftDataQuickEntryWriter(modelContainer: container)

        // The ubiquity container needs a signed build with the iCloud entitlement;
        // without one the store falls back to on-device Documents, which still shows
        // up in the Files app (§9.2).
        let receiptStore = FileSystemReceiptStore(ubiquityContainerID: nil)
        self.receiptStore = receiptStore
        self.backupWriter = BackupWriter(repositories: BackupRepositories(
            accounts: self.accounts,
            transactions: self.transactions,
            categories: self.categories,
            recurringRules: self.recurringRules,
            statements: self.cardStatements,
            products: self.products,
            comparisons: self.comparisons,
            merchantRules: self.merchantRules
        ))

        let settingsStore = UserDefaultsAppSettingsStore()
        settingsStore.load(into: settings)
        self.settingsStore = settingsStore
    }

    /// Seeds the built-in categories.
    ///
    /// Separate from `init` so the store work happens off the main actor, and idempotent so
    /// ``AppEnvironment`` can call it without tracking whether it already has.
    ///
    /// - Throws: A persistence error if seeding fails.
    func prepare() async throws {
        try await seeder.seedIfNeeded()
    }
}
