import Foundation
import Observation
import Domain

/// Drives the Dashboard and its Today sheet (§7.1, §7.2).
///
/// The Dashboard answers "where do I stand"; the Today card answers "what needs me".
/// Everything time-sensitive lives in the Today card, so nothing else on the screen
/// needs a badge or an alert.
@MainActor
@Observable
public final class DashboardViewModel {
    /// Supplies accounts.
    private let accountRepository: any AccountRepository
    /// Supplies transactions.
    private let transactionRepository: any TransactionRepository
    /// Supplies categories, for Recent activity rows.
    private let categoryRepository: any CategoryRepository
    /// Supplies recurring rules.
    private let recurringRuleRepository: any RecurringRuleRepository
    /// Supplies card statements.
    private let statementRepository: any CardStatementRepository
    /// Supplies Vault products.
    private let productRepository: any ProductRepository

    /// User preferences, for the display currency.
    public let settings: AppSettings

    /// Every account, closed ones included.
    public private(set) var accounts: [Domain.Account] = []
    /// Every transaction.
    public private(set) var transactions: [Domain.Transaction] = []
    /// Every category.
    public private(set) var categories: [Domain.Category] = []
    /// Active recurring rules.
    public private(set) var rules: [Domain.RecurringRule] = []
    /// Every Vault product.
    public private(set) var products: [Domain.Product] = []
    /// What needs the user's attention today.
    public private(set) var digest = TodayDigest()
    /// Whether the first load is still running.
    public private(set) var isLoading = true
    /// A load failure to surface above the content, never replacing it (§7.0).
    public private(set) var errorMessage: String?

    /// How many recent transactions the Dashboard lists.
    private static let recentLimit = 5

    /// Creates the view model.
    /// - Parameters:
    ///   - accountRepository: Supplies accounts.
    ///   - transactionRepository: Supplies transactions.
    ///   - categoryRepository: Supplies categories.
    ///   - recurringRuleRepository: Supplies recurring rules.
    ///   - statementRepository: Supplies card statements.
    ///   - productRepository: Supplies products.
    ///   - settings: The shared preferences object.
    ///   - settingsStore: Persists the starter-account note's dismissal.
    public init(
        accountRepository: any AccountRepository,
        transactionRepository: any TransactionRepository,
        categoryRepository: any CategoryRepository,
        recurringRuleRepository: any RecurringRuleRepository,
        statementRepository: any CardStatementRepository,
        productRepository: any ProductRepository,
        settings: AppSettings,
        settingsStore: (any AppSettingsStore)? = nil
    ) {
        self.accountRepository = accountRepository
        self.transactionRepository = transactionRepository
        self.categoryRepository = categoryRepository
        self.recurringRuleRepository = recurringRuleRepository
        self.statementRepository = statementRepository
        self.productRepository = productRepository
        self.settings = settings
        self.settingsStore = settingsStore
    }

    /// Persists the starter-account note's dismissal, when the app wired one in.
    private let settingsStore: (any AppSettingsStore)?

    /// Whether the Dashboard still owes the starter-account explanation (§7.10).
    public var showsStarterAccountNote: Bool { settings.showsStarterAccountNote }

    /// Clears the starter-account note for good.
    public func dismissStarterAccountNote() {
        settings.showsStarterAccountNote = false
        settingsStore?.save(settings)
    }

    // MARK: - Derived figures (§4.1)
    //
    // Stored rather than computed, and rebuilt by `refresh()` at the end of `load()`.
    // `BalanceEngine.sumBalances` reduces over every transaction once per account, so as
    // computed properties these were O(accounts × transactions) *per body evaluation* —
    // and the trends multiplied that by six months.

    /// Open accounts, which is what the account strip shows.
    public internal(set) var openAccounts: [Domain.Account] = []
    /// This month's expense figures. Income never feeds them, so the Dashboard reads
    /// correctly for someone who only tracks spending.
    public internal(set) var spendSummary = SpendSummary()
    /// What is about to leave in the next week: card statements and subscription charges.
    public internal(set) var dueWithinWeekCents = 0
    /// Six months of spend.
    public internal(set) var spendTrend = TrendSeries(points: [])
    /// The month's category split, largest first with "Other" last.
    var categorySlices: [CategorySliceModel] = []
    /// The "Spent by account" rows.
    var accountSpendRows: [AccountSpendRowModel] = []
    /// The most recent posted transactions.
    public internal(set) var recentTransactions: [Domain.Transaction] = []
    /// Every active rule, for the subscriptions list (§7.2).
    ///
    /// This is the only subscription registry: it covers standalone recurring
    /// transactions and Vault-linked subscriptions alike, because both are rules.
    public internal(set) var activeSubscriptions: [Domain.RecurringRule] = []

    /// The most recent posted transactions as rendered rows.
    var recentRows: [RecentRowModel] = []

    /// Accounts by identifier, replacing a linear scan per row.
    var accountsByID: [UUID: Domain.Account] = [:]
    /// Categories by identifier, replacing a linear scan per row.
    var categoriesByID: [UUID: Domain.Category] = [:]
    /// The next scheduled charge per rule, replacing a scan of every transaction per row.
    var nextChargeByRuleID: [UUID: Date] = [:]

    /// Whether the Dashboard's empty state applies — zero accounts (§7.1).
    public var hasNoAccounts: Bool { accounts.isEmpty }

    /// How many recent transactions to render.
    static var recentRowLimit: Int { recentLimit }

    /// Looks up an account by identifier.
    /// - Parameter id: The account's identifier, if any.
    /// - Returns: The account, or `nil` when unset or unknown.
    public func account(id: UUID?) -> Domain.Account? {
        guard let id else { return nil }
        return accountsByID[id]
    }

    /// Looks up a category by identifier.
    /// - Parameter id: The category's identifier, if any.
    /// - Returns: The category, or `nil` when unset or unknown.
    public func category(id: UUID?) -> Domain.Category? {
        guard let id else { return nil }
        return categoriesByID[id]
    }

    /// The next charge date for a rule, if one is scheduled.
    /// - Parameter rule: The rule to inspect.
    /// - Returns: The date, or `nil` when nothing is pending.
    public func nextChargeDate(for rule: Domain.RecurringRule) -> Date? {
        nextChargeByRuleID[rule.id]
    }

    // MARK: - Loading

    /// Loads everything the Dashboard derives from.
    public func load() async {
        do {
            accounts = try await accountRepository.accounts(includeClosed: true)
            transactions = try await transactionRepository.transactions(accountID: nil, in: nil)
            categories = try await categoryRepository.allCategories()
            rules = try await recurringRuleRepository.rules(activeOnly: false)
            products = try await productRepository.products()
            digest = TodayBuilder.digest(from: TodayInput(
                accounts: accounts,
                transactions: transactions,
                statements: try await statementRepository.statements(accountID: nil),
                rules: rules,
                products: products,
                defaultLeadTime: settings.defaultReminderLeadTime
            ))
            errorMessage = nil
        } catch {
            errorMessage = "Could not load your dashboard."
        }
        refresh()
        isLoading = false
    }

    /// The accounts a parked entry may be assigned to (§15.5).
    ///
    /// Open accounts only. A closed one is kept so history stays readable (§4.7), not so
    /// money that has been waiting can be filed into it.
    public var assignableAccounts: [Domain.Account] {
        accounts.filter { !$0.isClosed }
    }

    /// Files a parked entry against the account the user picked.
    ///
    /// The one action the Today sheet offers that changes money. A parked entry counts
    /// toward spend totals and moves no balance, so until this runs the app's own figures
    /// disagree with each other by exactly this much.
    ///
    /// - Parameters:
    ///   - entry: The entry waiting for an account.
    ///   - accountID: The account to file it against.
    public func assign(_ entry: UnassignedEntryItem, to accountID: UUID) async {
        var transaction = entry.transaction
        transaction.accountID = accountID
        do {
            try await transactionRepository.save(transaction)
            await load()
        } catch {
            errorMessage = "Could not file that entry."
        }
    }
}
