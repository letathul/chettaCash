import Foundation
import Observation
import Domain

/// Drives the Settings screen and its Accounts section (§7.6, §7.9, §4.7).
@MainActor
@Observable
public final class SettingsViewModel {
    /// Reads and writes accounts and groups.
    let accountRepository: any AccountRepository
    /// Creates the zeroing transfer offered by the close flow (§4.7).
    let transactionRepository: any TransactionRepository
    /// Persists preference changes.
    let settingsStore: any AppSettingsStore
    /// Generates card statements and allocates payments (§4.6).
    let statements: StatementCoordinator?
    /// Reads statement files and applies what they imply, when the app wires it.
    let statementImport: StatementImportCoordinator?
    /// The import screen's state, kept so unresolved conflicts survive the sheet closing.
    var pendingImport: StatementImportViewModel?
    /// The Bills category interest and fees are filed under (§4.6).
    var billsCategoryID: UUID?
    /// Drives receipt uploads, the cache and backups (§9).
    let storage: ReceiptStorageCoordinator?
    /// The app lock's controller (§11).
    let appLock: AppLockController?
    /// Whether this build may show the feature-flag menu (§7.6).
    ///
    /// Decided by the app, which is the only layer that knows how the build reached the
    /// device. `Features` must not read the build configuration itself.
    public let showsFeatureFlags: Bool

    /// Where storage stands right now (§9.6).
    public internal(set) var syncStatus = SyncStatus(state: .upToDate(lastSynced: nil), isUsingCloud: false)
    /// How much the receipt cache is holding.
    public internal(set) var cacheSummary = ""
    /// When the most recent archive was written.
    public internal(set) var lastBackupSummary = ""
    /// Whether a backup is being written.
    public internal(set) var isBackingUp = false
    /// Whether a sync is running.
    public internal(set) var isSyncing = false

    /// User preferences, shared with the rest of the app.
    public let settings: AppSettings

    /// Groups in sort order.
    public private(set) var groups: [Domain.AccountGroup] = []
    /// Every account, closed ones included, in sort order.
    public private(set) var accounts: [Domain.Account] = []
    /// Whether the first load is still running.
    public private(set) var isLoading = true
    /// A load or save failure to surface above the content (§7.0).
    public internal(set) var errorMessage: String?
    /// Identifiers of groups the user has collapsed.
    public var collapsedGroupIDs: Set<UUID> = []

    /// Creates the view model.
    /// - Parameters:
    ///   - accountRepository: Reads and writes accounts and groups.
    ///   - transactionRepository: Creates the close flow's zeroing transfer.
    ///   - settingsStore: Persists preference changes.
    ///   - settings: The shared preferences object.
    ///   - statementRepository: Reads and writes card statements, if available.
    ///   - categoryRepository: Supplies the Bills category for interest charges.
    ///   - storage: Drives receipt uploads, the cache and backups.
    ///   - appLock: The app lock's controller.
    ///   - merchantRuleRepository: Reads and writes merchant-to-category pins.
    ///   - showsFeatureFlags: Whether this build may show the feature-flag menu.
    public init(
        accountRepository: any AccountRepository,
        transactionRepository: any TransactionRepository,
        settingsStore: any AppSettingsStore,
        settings: AppSettings,
        statementRepository: (any CardStatementRepository)? = nil,
        categoryRepository: (any CategoryRepository)? = nil,
        storage: ReceiptStorageCoordinator? = nil,
        appLock: AppLockController? = nil,
        merchantRuleRepository: (any MerchantCategoryRuleRepository)? = nil,
        showsFeatureFlags: Bool = false
    ) {
        self.showsFeatureFlags = showsFeatureFlags
        self.storage = storage
        self.appLock = appLock
        self.accountRepository = accountRepository
        self.transactionRepository = transactionRepository
        self.settingsStore = settingsStore
        self.settings = settings
        self.categoryRepository = categoryRepository
        self.merchantRuleRepository = merchantRuleRepository
        self.statements = statementRepository.map {
            StatementCoordinator(statements: $0, transactions: transactionRepository)
        }
        // Built from repositories this model already holds, so statement import needs no
        // new init parameter and no change at the composition root.
        self.statementImport = categoryRepository.map {
            StatementImportCoordinator(
                accounts: accountRepository,
                transactions: transactionRepository,
                categories: $0,
                merchantRules: merchantRuleRepository
            )
        }
    }

    /// Supplies the Bills category for interest charges.
    private let categoryRepository: (any CategoryRepository)?
    /// Reads and writes merchant-to-category pins (§4.8).
    private let merchantRuleRepository: (any MerchantCategoryRuleRepository)?

    /// Whether the merchant mapping screen can be opened.
    ///
    /// Both repositories are optional here because the previews used by tests wire
    /// neither, and a row that pushes an empty screen is worse than no row.
    public var canMapMerchants: Bool {
        merchantRuleRepository != nil && categoryRepository != nil
    }

    /// Builds the merchant mapping screen's state.
    /// - Returns: The view model, or `nil` when the repositories were not wired.
    public func makeMerchantMappingModel() -> MerchantMappingViewModel? {
        guard let merchantRuleRepository, let categoryRepository else { return nil }
        return MerchantMappingViewModel(
            ruleRepository: merchantRuleRepository,
            categoryRepository: categoryRepository,
            transactionRepository: transactionRepository
        )
    }

    // MARK: - Derived figures
    //
    // Grouped once by `refresh()` rather than scanned per call. Every group block asked
    // for `accounts(in:)` and `subtotalCents(for:)`, and the subtotal scanned the list a
    // second time — two full passes over every account, per group, per body evaluation.

    /// Accounts that may be offered in a picker — open ones only (§4.7).
    public internal(set) var selectableAccounts: [Domain.Account] = []
    /// Net Worth across every open account, cards included (§4.1).
    public internal(set) var netWorthCents = 0

    /// Accounts per group, closed ones included so history stays visible.
    var accountsByGroupID: [UUID: [Domain.Account]] = [:]
    /// Each group's open-account subtotal in cents.
    var subtotalsByGroupID: [UUID: Int] = [:]

    /// Recomputes the grouped figures.
    ///
    /// Call whenever `groups` or `accounts` changes.
    public func refresh() {
        selectableAccounts = accounts.filter { !$0.isClosed }
        netWorthCents = selectableAccounts.reduce(0) { $0 + $1.cachedBalanceCents }
        accountsByGroupID = Dictionary(grouping: accounts.compactMap { account in
            account.groupID.map { (groupID: $0, account: account) }
        }, by: \.groupID).mapValues { $0.map(\.account) }
        subtotalsByGroupID = accountsByGroupID.mapValues { grouped in
            grouped.lazy.filter { !$0.isClosed }.reduce(0) { $0 + $1.cachedBalanceCents }
        }
    }

    /// Returns the accounts in one group, in sort order.
    /// - Parameter group: The group to list.
    /// - Returns: That group's accounts, closed ones included so history stays visible.
    public func accounts(in group: Domain.AccountGroup) -> [Domain.Account] {
        accountsByGroupID[group.id] ?? []
    }

    /// Sums the balances of one group's open accounts.
    /// - Parameter group: The group to total.
    /// - Returns: The subtotal in cents.
    public func subtotalCents(for group: Domain.AccountGroup) -> Int {
        subtotalsByGroupID[group.id] ?? 0
    }

    // MARK: - Loading

    /// Loads groups and accounts, replacing any previous error.
    public func load() async {
        do {
            groups = try await accountRepository.groups()
            accounts = try await accountRepository.accounts(includeClosed: true)
            billsCategoryID = try await categoryRepository?.allCategories()
                .first { $0.label == "Bills" && $0.context == .expense }?.id
            errorMessage = nil
            await loadStorage()
        } catch {
            errorMessage = "Could not load your accounts."
        }
        refresh()
        isLoading = false
    }

    // MARK: - Preferences

    /// Persists the current preference values.
    public func persistSettings() {
        settingsStore.save(settings)
    }

    // MARK: - Groups and accounts

    /// Creates a group, placing it after the existing ones.
    ///
    /// Returns the group so the caller can open the add-account sheet scoped to it —
    /// creating a group and then hunting for it in a list would be a step too many.
    ///
    /// - Parameter name: The group's display name.
    /// - Returns: The saved group, or `nil` when the write failed.
    @discardableResult
    public func addGroup(named name: String) async -> Domain.AccountGroup? {
        let group = Domain.AccountGroup(name: name, sortIndex: groups.count)
        await perform("Could not save that group.") {
            try await self.accountRepository.save(group)
        }
        return errorMessage == nil ? group : nil
    }

    /// Renames a group, leaving its accounts and ordering alone.
    /// - Parameters:
    ///   - group: The group to rename.
    ///   - name: The new display name.
    public func rename(_ group: Domain.AccountGroup, to name: String) async {
        var renamed = group
        renamed.name = name
        await perform("Could not rename that group.") {
            try await self.accountRepository.save(renamed)
        }
    }

    /// Inserts or updates an account.
    ///
    /// A card's opening balance is normalised to negative regardless of the sign the
    /// user typed (§7.9); the running balance's sign always comes from transaction
    /// types, never from this.
    ///
    /// - Parameter draft: The account to persist.
    public func save(_ draft: Domain.Account) async {
        var account = draft
        account.openingBalanceCents = BalanceEngine.normalizedOpeningBalanceCents(
            draft.openingBalanceCents, kind: draft.kind
        )
        await perform("Could not save that account.") {
            try await self.accountRepository.save(account)
        }
    }

    /// The next sort position within a group.
    /// - Parameter groupID: The group an account is being added to.
    /// - Returns: The position to give the new account.
    public func nextSortIndex(inGroup groupID: UUID?) -> Int {
        accounts.filter { $0.groupID == groupID }.count
    }

    // MARK: - Reordering

    /// Reports whether an account can move within its group (§7.6).
    /// - Parameters:
    ///   - account: The account to move.
    ///   - offset: `-1` to move up, `1` to move down.
    /// - Returns: `false` at the group's boundary, which disables the arrow.
    public func canMove(_ account: Domain.Account, by offset: Int) -> Bool {
        guard let groupID = account.groupID else { return false }
        let siblings = accounts.filter { $0.groupID == groupID }
        guard let index = siblings.firstIndex(where: { $0.id == account.id }) else { return false }
        return siblings.indices.contains(index + offset)
    }

    /// Moves an account up or down within its group and renumbers its siblings.
    /// - Parameters:
    ///   - account: The account to move.
    ///   - offset: `-1` to move up, `1` to move down.
    public func move(_ account: Domain.Account, by offset: Int) async {
        guard canMove(account, by: offset), let groupID = account.groupID else { return }
        var siblings = accounts.filter { $0.groupID == groupID }
        guard let index = siblings.firstIndex(where: { $0.id == account.id }) else { return }
        siblings.swapAt(index, index + offset)

        await perform("Could not reorder your accounts.") {
            for (position, var sibling) in siblings.enumerated() where sibling.sortIndex != position {
                sibling.sortIndex = position
                try await self.accountRepository.save(sibling)
            }
        }
    }

    /// Runs a repository mutation, reloads, and surfaces a failure as a banner.
    /// - Parameters:
    ///   - failureMessage: What to show if the work throws.
    ///   - work: The mutation to run.
    func perform(
        _ failureMessage: String,
        _ work: () async throws -> Void
    ) async {
        do {
            try await work()
            await load()
        } catch {
            errorMessage = failureMessage
        }
    }
}
