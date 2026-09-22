import Foundation
import Observation
import Domain

/// Drives the Ledger screen and the transaction forms (§7.4, §7.8).
@MainActor
@Observable
public final class LedgerViewModel {
    /// Reads and writes ledger transactions.
    private let transactionRepository: any TransactionRepository
    /// Supplies accounts for filters and pickers.
    private let accountRepository: any AccountRepository
    /// Supplies categories for the filter and picker rows.
    private let categoryRepository: any CategoryRepository
    /// Persists rules seeded by the Recurring toggle.
    private let recurringRuleRepository: any RecurringRuleRepository
    /// Generates occurrences and applies scoped series edits (§4.5).
    let recurring: RecurringCoordinator
    /// Caches and queues the upload of a scanned receipt, when one is available.
    ///
    /// Internal rather than private: ``TransactionSheet`` reads attached receipts back
    /// through it to show a thumbnail.
    let receiptStorage: ReceiptStorageCoordinator?

    /// User preferences, for the display currency.
    public let settings: AppSettings

    /// Every transaction, unfiltered.
    public private(set) var allTransactions: [Domain.Transaction] = []
    /// Every account, closed ones included — the filter row shows closed accounts too.
    public private(set) var accounts: [Domain.Account] = []
    /// Every category, for the filter row and the picker.
    public private(set) var categories: [Domain.Category] = []
    /// Active recurring rules, used to resolve a row's series.
    public private(set) var recurringRules: [Domain.RecurringRule] = []
    /// Whether the first load is still running.
    public private(set) var isLoading = true
    /// A load or save failure to surface above the content (§7.0).
    public internal(set) var errorMessage: String?

    /// The active filter combination.
    ///
    /// Writing this rebuilds the derived state immediately, so a caller can never read a
    /// stale `items` after moving the filter. The accessors are written out by hand
    /// because `@Observable` transforms *stored* properties only — this keeps `filter`
    /// observable (the chip rows bind straight into it) while still running `refresh()`
    /// on the way through.
    public var filter: LedgerFilter {
        get {
            access(keyPath: \.filter)
            return storedFilter
        }
        set {
            withMutation(keyPath: \.filter) { storedFilter = newValue }
            refresh()
        }
    }

    /// Backing storage for ``filter``.
    @ObservationIgnored private var storedFilter = LedgerFilter()

    /// The products view model, when the Ledger is allowed to reach into it.
    ///
    /// Held so a purchase can gain products from the transaction form (§7.8). The
    /// *same* instance the Dashboard and the search screen hold, so a product added
    /// from here appears there without a reload, rather than lists that can disagree.
    let productsModel: ProductsViewModel?

    /// Creates the view model.
    /// - Parameters:
    ///   - transactionRepository: Reads and writes transactions.
    ///   - accountRepository: Supplies accounts.
    ///   - categoryRepository: Supplies categories.
    ///   - recurringRuleRepository: Persists recurring rules.
    ///   - settings: The shared preferences object.
    ///   - productsModel: The shared products view model, for the product section (§7.8).
    ///   - receiptStorage: Stores a scanned receipt, when one is available.
    public init(
        transactionRepository: any TransactionRepository,
        accountRepository: any AccountRepository,
        categoryRepository: any CategoryRepository,
        recurringRuleRepository: any RecurringRuleRepository,
        settings: AppSettings,
        productsModel: ProductsViewModel? = nil,
        receiptStorage: ReceiptStorageCoordinator? = nil
    ) {
        self.transactionRepository = transactionRepository
        self.accountRepository = accountRepository
        self.categoryRepository = categoryRepository
        self.recurringRuleRepository = recurringRuleRepository
        self.recurring = RecurringCoordinator(
            transactions: transactionRepository, rules: recurringRuleRepository
        )
        self.settings = settings
        self.productsModel = productsModel
        self.receiptStorage = receiptStorage
    }

    // MARK: - Derived state (§7.4)
    //
    // Everything below is *stored*, recomputed by `refresh()` when the data, the filter
    // or the display currency changes. These were computed properties, which read
    // correctly but meant `filter.apply(to:)` ran eight times per body evaluation — four
    // times for the summary banner alone — and `LedgerAssembler.items` three times, each
    // with its own sort. A screen may read any of these as often as it likes.

    /// The transactions matching every active filter.
    public internal(set) var filteredTransactions: [Domain.Transaction] = []
    /// The rows to render, with transfers collapsed unless an account filter is active.
    public internal(set) var items: [LedgerItem] = []
    /// Unposted rows, soonest first (§7.4).
    public internal(set) var upcomingItems: [LedgerItem] = []
    /// Unposted rows as rendered content, soonest first.
    var upcomingRows: [LedgerRowModel] = []
    /// Posted rows grouped by calendar day, newest first.
    var postedDays: [LedgerDay] = []
    /// Whether the filters matched nothing, as distinct from having no data at all (§7.0).
    public internal(set) var isFilteredToZero = false
    /// Total spent in the period, excluding transfers, adjustments and unposted rows.
    public internal(set) var spendCents = 0
    /// Total income in the period, under the same exclusions.
    public internal(set) var incomeCents = 0
    /// Income minus spend for the period.
    public internal(set) var netCents = 0
    /// How many transactions the banner reports.
    public internal(set) var bannerCount = 0
    /// The label describing the current period and account scope.
    public internal(set) var scopeLabel = ""
    /// Accounts offered in a picker — open ones only (§4.7).
    public internal(set) var selectableAccounts: [Domain.Account] = []
    /// Categories offered in the filter row: those at least one transaction carries,
    /// minus archived and system ones, plus whichever one is currently selected.
    ///
    /// Narrower than the form's picker on purpose: a chip for a category nothing is
    /// filed under can only ever return "no transactions match", and the seeded
    /// catalogue is long enough that those crowd out the chips that mean something.
    public internal(set) var filterCategories: [Domain.Category] = []

    /// Whether no transaction exists at all, which is the first-run empty state.
    public var isEmpty: Bool { allTransactions.isEmpty }

    /// Accounts by identifier, replacing a linear scan per row.
    var accountsByID: [UUID: Domain.Account] = [:]
    /// Categories by identifier, replacing a linear scan per row.
    var categoriesByID: [UUID: Domain.Category] = [:]
    /// Selectable categories per picker context, built once per reload.
    var categoriesByContext: [CategoryContext: [Domain.Category]] = [:]

    // MARK: - Loading

    /// Loads transactions, accounts and categories.
    public func load() async {
        do {
            allTransactions = try await transactionRepository.transactions(accountID: nil, in: nil)
            accounts = try await accountRepository.accounts(includeClosed: true)
            categories = try await categoryRepository.allCategories()
            recurringRules = try await recurringRuleRepository.rules(activeOnly: false)
            errorMessage = nil
        } catch {
            errorMessage = "Could not load your transactions."
        }
        // So the transaction form can list a purchase's products even when nothing
        // else has asked the product repository yet (§7.8).
        await productsModel?.loadIfNeeded()
        refresh()
        isLoading = false
    }

    /// Loads once, for callers that may arrive before the Ledger tab has appeared.
    ///
    /// The search screen opens from the Dashboard (§7.12), which can be the only tab the
    /// user has visited. Without this it would search an empty list.
    public func loadIfNeeded() async {
        guard isLoading else { return }
        await load()
    }

    // MARK: - Writing

    /// Saves the form as an expense, income or transfer, plus its receipt, products
    /// and any recurring rule (§7.8, §9.3).
    ///
    /// A newly scanned receipt is stored against the **transaction**, which is what owns
    /// it: one image can cover every product on the purchase. Replacing or removing a
    /// receipt deletes the file it displaced, but only once the save has succeeded —
    /// cancelling an edit must not destroy the image.
    ///
    /// Products collected on an Add form are written afterwards, because until the
    /// transaction exists there is nothing for them to point at.
    ///
    /// - Parameters:
    ///   - form: The form to commit.
    ///   - receiptImageData: A newly captured receipt to store, if one was scanned.
    /// - Returns: `true` when the form validated and was saved.
    @discardableResult
    public func save(
        _ form: TransactionFormState,
        receiptImageData: Data? = nil
    ) async -> Bool {
        guard form.attemptSave() else { return false }
        let rule = form.commitRecurringRule()
        let displaced = form.existingID
            .flatMap { id in allTransactions.first { $0.id == id } }?
            .receiptFileID
        do {
            if form.mode == .transfer {
                try await saveTransfer(form)
            } else if var transaction = form.commitSingle() {
                if let receiptImageData, let receiptStorage {
                    transaction.receiptFileID = receiptStorage.capture(
                        receiptImageData, for: transaction
                    )
                    transaction.receiptUploadState = .pending
                }
                transaction.recurringRuleID = rule?.id ?? transaction.recurringRuleID
                if let rule { try await recurringRuleRepository.save(rule) }
                try await transactionRepository.save(transaction)
                try await productsModel?.attach(form.products, to: transaction.id)
                if let displaced, displaced != transaction.receiptFileID {
                    await receiptStorage?.discard(fileID: displaced)
                }
            }
            if receiptImageData != nil {
                // The cache is in memory only, so an image that is merely *queued* is
                // gone at the next launch. Drain the queue now, while the user is still
                // looking at the thing they just attached.
                await receiptStorage?.flushUploads()
            }
            await load()
            return true
        } catch {
            errorMessage = "Could not save that transaction."
            return false
        }
    }

    /// Deletes a transaction, its products and its receipt (§4.3, §7.8).
    ///
    /// The products go with the purchase: a product with no transaction is not
    /// representable, and the store cascades them. The receipt file goes too, because
    /// nothing is left to point at it.
    ///
    /// - Parameter transaction: The transaction to delete.
    public func delete(_ transaction: Domain.Transaction) async {
        do {
            try await transactionRepository.delete(id: transaction.id)
            if let fileID = transaction.receiptFileID {
                await receiptStorage?.discard(fileID: fileID)
            }
            await productsModel?.load()
            await load()
        } catch {
            errorMessage = "Could not delete that transaction."
        }
    }

    /// Creates a custom category in one context (§8.4).
    /// - Parameters:
    ///   - label: The category's display text.
    ///   - context: Which picker it belongs to.
    /// - Returns: The identifier to select, whether newly created or already present.
    @discardableResult
    public func addCategory(label: String, context: CategoryContext) async -> UUID? {
        if let existing = categories.first(where: {
            $0.context == context && $0.label.caseInsensitiveCompare(label) == .orderedSame
        }) {
            return existing.id
        }
        let category = Domain.Category(
            label: label,
            context: context,
            sortIndex: selectableCategories(for: context).count
        )
        do {
            try await categoryRepository.save(category)
            await load()
            return category.id
        } catch {
            errorMessage = "Could not save that category."
            return nil
        }
    }

    /// Replaces an existing transfer by deleting both legs and writing new ones.
    ///
    /// Editing either leg edits both, so a half-transfer can never survive an edit (§4.3).
    ///
    /// - Parameter form: The form to commit.
    /// - Throws: A persistence or ``TransferError`` failure.
    private func saveTransfer(_ form: TransactionFormState) async throws {
        guard let legs = try form.commitTransfer() else { return }
        if let existingID = form.existingID,
           let existing = allTransactions.first(where: { $0.id == existingID }),
           let groupID = existing.transferGroupID {
            try await transactionRepository.deleteTransfer(groupID: groupID)
        }
        try await transactionRepository.saveTransfer(outLeg: legs.out, inLeg: legs.in)
    }
}
